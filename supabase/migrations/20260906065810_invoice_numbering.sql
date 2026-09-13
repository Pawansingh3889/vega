-- SECURITY.md N5, enforced rather than written down: money sequences serialise
-- per company. SPEC 3.2 and ADR 0006 decided the mechanism and why; this is
-- the implementation.
--
-- The row *is* the sequence. A number is taken from a counter row held under
-- SELECT ... FOR UPDATE, in the same transaction as the issue, so an
-- allocation path cannot forget to lock: reading the next number requires
-- taking the lock that serialises it. The two alternatives are dead ends and
-- ADR 0006 says why: an advisory lock separates the lock from the allocation
-- so a new path can forget it, and a Postgres SEQUENCE deliberately burns
-- numbers on rollback, which is the defect, not a trade-off.
--
-- Numbers are allocated at the draft-to-issued transition, so an abandoned
-- draft leaves no gap. The format is YYYY-NNNNNN: the counter is per company
-- and per year (SPEC 3.1), so a bare sequence would repeat across years, and
-- the year prefix makes every number unique within the company and sorts with
-- the filing period it belongs to. Invoices issued before this migration keep
-- the numbers the inherited auto-generation gave them; renumbering them is
-- exactly what N5 forbids.

CREATE TABLE public.invoice_counters (
    company_id uuid NOT NULL REFERENCES public.companies(id),
    year integer NOT NULL CHECK (year BETWEEN 2000 AND 2100),
    next_number integer NOT NULL CHECK (next_number > 0),
    PRIMARY KEY (company_id, year)
);

COMMENT ON TABLE public.invoice_counters IS
  'Gapless number sequences per company and year (SECURITY.md N5, ADR 0006). The row is the sequence: it is only ever read under SELECT ... FOR UPDATE, by allocate_invoice_number.';

-- N1: tenant data, denied by default. A member may read their own counter;
-- nobody may write one directly. The only write path is the SECURITY DEFINER
-- allocation function, which runs as the owner and so bypasses RLS entirely.
ALTER TABLE public.invoice_counters ENABLE ROW LEVEL SECURITY;

CREATE POLICY invoice_counters_read_own
ON public.invoice_counters FOR SELECT
TO authenticated
USING (company_id = current_company_id());

COMMENT ON POLICY invoice_counters_read_own ON public.invoice_counters IS
  'Members read their own counter. No permissive write policy exists: RLS enabled with none means writes are blocked, which is the N1 default.';

-- The grants agree with the policy: even a future policy mistake cannot turn
-- into a client-side counter edit, and service_role has no business editing a
-- sequence by hand either. The allocation function runs as the owner and is
-- unaffected.
REVOKE INSERT, UPDATE, DELETE ON public.invoice_counters FROM anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.allocate_invoice_number(p_company_id uuid, p_year integer)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_next integer;
BEGIN
    -- The missing row is its own race. Two first-ever invoices for one company
    -- both find nothing, so both must try to insert; ON CONFLICT DO NOTHING
    -- lets the loser fall through to the locked SELECT, where it blocks on the
    -- row lock the winner holds and re-reads. An unconditional INSERT, as the
    -- first attempt at this issue had, dies on the primary key instead.
    INSERT INTO public.invoice_counters (company_id, year, next_number)
    VALUES (p_company_id, p_year, 1)
    ON CONFLICT (company_id, year) DO NOTHING;

    SELECT next_number INTO v_next
    FROM public.invoice_counters
    WHERE company_id = p_company_id AND year = p_year
    FOR UPDATE;

    UPDATE public.invoice_counters
    SET next_number = v_next + 1
    WHERE company_id = p_company_id AND year = p_year;

    RETURN v_next;
END;
$$;

COMMENT ON FUNCTION public.allocate_invoice_number(uuid, integer) IS
  'Returns the next gapless invoice number for a company and year, under the counter row lock. The FOR UPDATE is the serialisation (N5); a number is issued exactly once, and rollback restores it.';

-- Consistency: an issued invoice is countable, so it carries its number; a
-- draft has none, so abandoning it costs nothing. Validated against the data
-- first, with a message that says what to do, rather than a constraint error
-- that does not (N6).
DO $$
DECLARE
    v_unnumbered integer;
    v_duplicated integer;
BEGIN
    SELECT count(*) INTO v_unnumbered
    FROM public.sales_invoices
    WHERE status = 'issued' AND invoice_number IS NULL;

    IF v_unnumbered > 0 THEN
        RAISE EXCEPTION
            '% issued invoices carry no number. N5 forbids renumbering, so each needs a decision before this migration can apply: either the number was lost and must be recovered from the document, or the row is not really issued.',
            v_unnumbered;
    END IF;

    -- The inherited generator was MAX+1 over the invoice table, which is
    -- itself a duplicate under concurrency. If the live data already carries
    -- duplicates, the unique index below must not discover that with a
    -- message about index creation; name the defect instead.
    SELECT count(*) INTO v_duplicated
    FROM (
        SELECT company_id, invoice_number
        FROM public.sales_invoices
        WHERE invoice_number IS NOT NULL
        GROUP BY company_id, invoice_number
        HAVING count(*) > 1
    ) d;

    IF v_duplicated > 0 THEN
        RAISE EXCEPTION
            '% (company, invoice_number) pairs are duplicated in the live data, a defect this migration exists to prevent from recurring. The duplicates need resolving before the unique index can be created.',
            v_duplicated;
    END IF;
END;
$$;

ALTER TABLE public.sales_invoices
    ADD CONSTRAINT sales_invoices_number_state_check
    CHECK (
        (status = 'draft' AND invoice_number IS NULL)
        OR (status = 'issued' AND invoice_number IS NOT NULL)
    );

-- A duplicate would otherwise only be caught by whoever reconciles the
-- return. The counter is the allocator, but a defence that only exists in
-- happy-path code is not a defence: the index catches a bypass, whatever
-- caused it.
CREATE UNIQUE INDEX sales_invoices_number_unique_per_company
ON public.sales_invoices (company_id, invoice_number)
WHERE invoice_number IS NOT NULL;

CREATE OR REPLACE FUNCTION public.allocate_invoice_on_issue()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_year integer;
    v_seq integer;
BEGIN
    -- Renumbering is the defect N5 exists for, refused independently of the
    -- immutability trigger (#26), which refuses any update of an issued row.
    -- Both controls hold even if the other lands or is dropped first.
    IF OLD.invoice_number IS DISTINCT FROM NEW.invoice_number
       AND OLD.invoice_number IS NOT NULL THEN
        RAISE EXCEPTION
            'sales_invoices is append-only once issued: renumbering is not permitted. Correct the record by appending a credit note, not by rewriting.'
            USING ERRCODE = 'restrict_violation';
    END IF;

    IF NEW.status = 'issued' AND OLD.status IS DISTINCT FROM 'issued' THEN
        IF NEW.invoice_number IS NOT NULL THEN
            RAISE EXCEPTION
                'invoice_number is allocated here, not supplied: leave it NULL and the counter will issue it (SECURITY.md N5)'
                USING ERRCODE = 'restrict_violation';
        END IF;

        -- The number belongs to the year the invoice dates from: that is the
        -- filing period the sequence must reconcile against.
        v_year := EXTRACT(YEAR FROM NEW.invoice_date)::integer;
        v_seq := public.allocate_invoice_number(NEW.company_id, v_year);
        NEW.invoice_number :=
            lpad(v_year::text, 4, '0') || '-' || lpad(v_seq::text, 6, '0');
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.allocate_invoice_on_issue() IS
  'Allocates the invoice number at the draft-to-issued transition, from the per-company per-year counter under its row lock. Refuses a client-supplied number and any change to a number once set.';

CREATE TRIGGER trg_allocate_invoice_on_issue
BEFORE UPDATE ON public.sales_invoices
FOR EACH ROW EXECUTE FUNCTION public.allocate_invoice_on_issue();

-- A row may also arrive already issued, by import or by an INSERT that skips
-- the draft. Same rule: the counter issues the number, the client does not.
CREATE TRIGGER trg_allocate_invoice_on_insert
BEFORE INSERT ON public.sales_invoices
FOR EACH ROW
WHEN (NEW.status = 'issued')
EXECUTE FUNCTION public.allocate_invoice_on_issue();

-- Prove the sequence, in the transaction itself. The block ends by raising,
-- which rolls back every row it inserted, so a live database gains nothing
-- and the migration fails loudly if the control does not hold (N6).
DO $$
DECLARE
    v_company uuid;
    v_customer uuid;
    v_invoice uuid;
    v_number text;
    v_again text;
    v_refused boolean := false;
BEGIN
    INSERT INTO public.companies (name) VALUES ('numbering probe') RETURNING id INTO v_company;
    INSERT INTO public.customers (company_id, name)
        VALUES (v_company, 'numbering probe customer') RETURNING id INTO v_customer;
    INSERT INTO public.products (company_id, sku, name) VALUES (v_company, 'PROBE-N', 'probe product');

    INSERT INTO public.sales_invoices (company_id, customer_id, customer_name, created_by)
        VALUES (v_company, v_customer, 'numbering probe customer', gen_random_uuid())
        RETURNING id INTO v_invoice;

    UPDATE public.sales_invoices SET status = 'issued' WHERE id = v_invoice
        RETURNING invoice_number INTO v_number;
    IF v_number IS NULL OR v_number NOT LIKE '20%-000001' THEN
        RAISE EXCEPTION 'the first issued invoice took the number %, expected 000001 for the current year', v_number;
    END IF;

    -- The second number is the first plus one, and the counter row moved.
    INSERT INTO public.sales_invoices (company_id, customer_id, customer_name, created_by)
        VALUES (v_company, v_customer, 'numbering probe customer', gen_random_uuid())
        RETURNING id INTO v_invoice;
    UPDATE public.sales_invoices SET status = 'issued' WHERE id = v_invoice
        RETURNING invoice_number INTO v_again;
    IF right(v_again, 6) <> lpad((right(v_number, 6)::integer + 1)::text, 6, '0') THEN
        RAISE EXCEPTION 'the sequence is not consecutive: % then %', v_number, v_again;
    END IF;

    IF (SELECT next_number FROM public.invoice_counters
        WHERE company_id = v_company
          AND year = EXTRACT(YEAR FROM current_date)::integer) <> 3 THEN
        RAISE EXCEPTION 'the counter did not advance with the numbers issued';
    END IF;

    -- A supplied number is a claim, not a result (N3's cousin): refused.
    v_refused := false;
    BEGIN
        INSERT INTO public.sales_invoices
            (company_id, customer_id, customer_name, created_by, status, invoice_number)
        VALUES
            (v_company, v_customer, 'numbering probe customer', gen_random_uuid(), 'issued', '2026-999999');
    EXCEPTION WHEN restrict_violation THEN
        v_refused := true;
    END;
    IF NOT v_refused THEN
        RAISE EXCEPTION 'a client-supplied invoice number was accepted';
    END IF;

    RAISE EXCEPTION 'probe-complete: rolling back';
EXCEPTION
    WHEN raise_exception THEN
        IF SQLERRM <> 'probe-complete: rolling back' THEN
            RAISE;
        END IF;
END;
$$;
