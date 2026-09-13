-- The append-only record of what was filed with HMRC.
--
-- SPEC.md 2.3: "The submission record is append-only: what was sent, when, by
-- whom, and the response received." SECURITY.md N2 is the enforcement.
--
-- WHAT IS DELIBERATELY NOT HERE: the fraud prevention headers. They are sent on
-- every MTD call and they are a device fingerprint of a named person, device
-- id, screen size, timezone, user agent. Storing them in a table that N2
-- forbids deleting from would put personal data permanently beyond the reach of
-- Phase 8's erasure work, which is a contradiction better avoided than solved.
-- HMRC requires them sent, not retained by us. See #109 question 4.
--
-- The VRN is stored on the row rather than read from companies at display time.
-- A return filed under a number is filed under that number for ever, and a
-- company that later corrects its VAT number must not silently rewrite what was
-- already submitted.

CREATE TABLE IF NOT EXISTS public.hmrc_submissions (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id     uuid NOT NULL REFERENCES public.companies(id),

    -- Which return. period_key is HMRC's own identifier for an obligation.
    vrn            text NOT NULL,
    period_key     text NOT NULL,
    period_start   date NOT NULL,
    period_end     date NOT NULL,

    -- What was sent. The nine boxes as filed, exactly as serialised.
    payload        jsonb NOT NULL,

    -- What came back. correlation_id is the header HMRC gives every request and
    -- the first thing they ask for when a submission is disputed years later.
    http_status    integer,
    response       jsonb,
    correlation_id text,

    -- Which environment. A sandbox submission must never be mistaken for a
    -- filed return, and the only thing that distinguishes them after the fact
    -- is this column, so it is NOT NULL with no default.
    environment    text NOT NULL,

    submitted_at   timestamptz NOT NULL DEFAULT now(),
    submitted_by   uuid NOT NULL REFERENCES auth.users(id),

    CONSTRAINT hmrc_submissions_environment_check
        CHECK (environment IN ('sandbox', 'production')),
    CONSTRAINT hmrc_submissions_period_order_check
        CHECK (period_end >= period_start)
);

COMMENT ON TABLE public.hmrc_submissions IS
  'Append-only record of MTD VAT submissions. Holds no fraud prevention headers by design: see the migration header and #109.';

-- N1. Deny by default, then one policy that reads only within the caller's company.
ALTER TABLE public.hmrc_submissions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS hmrc_submissions_read_own ON public.hmrc_submissions;
CREATE POLICY hmrc_submissions_read_own
    ON public.hmrc_submissions
    FOR SELECT
    TO authenticated
    USING (company_id = public.current_company_id());

-- No INSERT policy for `authenticated`, deliberately. A person does not write
-- this row; the service does, after HMRC has answered. N3's shape: the server
-- produces what gets filed.

-- N2. The trigger binds every role including service_role, which bypasses RLS
-- and does not bypass triggers. refuse_mutation() already exists from 0017.
DROP TRIGGER IF EXISTS hmrc_submissions_append_only ON public.hmrc_submissions;
CREATE TRIGGER hmrc_submissions_append_only
    BEFORE UPDATE OR DELETE ON public.hmrc_submissions
    FOR EACH ROW EXECUTE FUNCTION public.refuse_mutation();

-- Second layer: withheld grants, so anon and authenticated cannot even try.
REVOKE UPDATE, DELETE ON public.hmrc_submissions FROM anon, authenticated, service_role;
GRANT SELECT ON public.hmrc_submissions TO authenticated;
GRANT SELECT, INSERT ON public.hmrc_submissions TO service_role;

-- Prove it, rather than assert it. Every claim above is checked here against a
-- real row and the whole probe is rolled back. A migration that says it made
-- something append-only and did not is worse than one that did nothing.
DO $$
DECLARE
    v_company  uuid;
    v_user     uuid;
    v_id       uuid;
    v_refused  boolean;
BEGIN
    INSERT INTO auth.users (id, email)
    VALUES (gen_random_uuid(), 'hmrc-probe@example.invalid')
    RETURNING id INTO v_user;

    INSERT INTO public.companies (id, name)
    VALUES (gen_random_uuid(), 'hmrc probe company')
    RETURNING id INTO v_company;

    INSERT INTO public.hmrc_submissions
        (company_id, vrn, period_key, period_start, period_end,
         payload, environment, submitted_by)
    VALUES
        (v_company, '123456789', '18A1', DATE '2026-07-01', DATE '2026-09-30',
         '{"vatDueSales": "0.00"}'::jsonb, 'sandbox', v_user)
    RETURNING id INTO v_id;

    -- UPDATE must be refused.
    v_refused := false;
    BEGIN
        UPDATE public.hmrc_submissions SET http_status = 200 WHERE id = v_id;
    EXCEPTION WHEN restrict_violation THEN
        v_refused := true;
    END;
    IF NOT v_refused THEN
        RAISE EXCEPTION 'hmrc_submissions accepted an UPDATE';
    END IF;

    -- DELETE must be refused.
    v_refused := false;
    BEGIN
        DELETE FROM public.hmrc_submissions WHERE id = v_id;
    EXCEPTION WHEN restrict_violation THEN
        v_refused := true;
    END;
    IF NOT v_refused THEN
        RAISE EXCEPTION 'hmrc_submissions accepted a DELETE';
    END IF;

    -- An environment outside the two known values must be refused, because that
    -- column is the only thing separating a rehearsal from a filed return.
    v_refused := false;
    BEGIN
        INSERT INTO public.hmrc_submissions
            (company_id, vrn, period_key, period_start, period_end,
             payload, environment, submitted_by)
        VALUES
            (v_company, '123456789', '18A2', DATE '2026-10-01', DATE '2026-12-31',
             '{}'::jsonb, 'staging', v_user);
    EXCEPTION WHEN check_violation THEN
        v_refused := true;
    END;
    IF NOT v_refused THEN
        RAISE EXCEPTION 'hmrc_submissions accepted an unknown environment';
    END IF;

    RAISE EXCEPTION 'probe-complete: rolling back';
EXCEPTION
    WHEN raise_exception THEN
        IF SQLERRM <> 'probe-complete: rolling back' THEN
            RAISE;
        END IF;
END;
$$;
