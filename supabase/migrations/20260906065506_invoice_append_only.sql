-- SECURITY.md N2, part two: issued invoices and credit notes become append-only.
--
-- Migration 0017 made four ledgers append-only and deliberately left invoices
-- out, because 'finalized' left no state to become immutable FROM. The
-- lifecycle migration gave invoices a draft state; this freezes what leaving
-- it produces.
--
-- The shape differs from 0017 in one way, and it matters. 0017's tables have
-- no legitimate mutable state, so it refuses every UPDATE and DELETE and
-- withholds the grants outright. Draft invoices and credit notes do have
-- legitimate mutable state: a draft is being edited by definition. So the
-- protection is conditional on status and lives entirely in triggers:
--
--   A trigger binds EVERY role. service_role bypasses row level security but
--   not triggers, and the table owner bypasses FORCE ROW LEVEL SECURITY but
--   not triggers. Revoking UPDATE would break every draft, so the grants
--   layer of 0017 is deliberately absent here and the trigger is the whole
--   control. DELETE is likewise left available for drafts, which may be
--   abandoned; the trigger is what refuses it on issued rows.
--
-- The refusal is tested against the PRE-update state (OLD), so one test
-- covers renumbering, the issued-to-draft backtrack, and every other edit.
--
-- The error names the table and says what to do instead (N6): corrections are
-- credit notes, which is what the VAT return reconciles against.

CREATE OR REPLACE FUNCTION public.refuse_issued_mutation()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  RAISE EXCEPTION
    '% is append-only once issued: % is not permitted. Correct the record by appending a credit note, not by rewriting.',
    TG_TABLE_NAME, TG_OP
    USING ERRCODE = 'restrict_violation';
END;
$$;

COMMENT ON FUNCTION public.refuse_issued_mutation() IS
  'Refuses UPDATE and DELETE on rows whose issuing state has passed. The caller decides which state that is: invoices on status = issued, credit notes on Confirmed. Binds every role including service_role and the table owner, which bypass RLS and FORCE RLS but not triggers.';

-- The invoice itself: frozen once issued, in either direction of the law.
CREATE TRIGGER sales_invoices_append_only
BEFORE UPDATE OR DELETE ON public.sales_invoices
FOR EACH ROW
WHEN (OLD.status = 'issued')
EXECUTE FUNCTION public.refuse_issued_mutation();

-- Credit notes inherit the vocabulary of the schema they came from: 'Draft'
-- and 'Confirmed'. Confirmed is the issued equivalent: it has been raised
-- against an invoice and belongs to the return.
CREATE TRIGGER credit_notes_append_only
BEFORE UPDATE OR DELETE ON public.credit_notes
FOR EACH ROW
WHEN (OLD.status = 'Confirmed')
EXECUTE FUNCTION public.refuse_issued_mutation();

-- Lines carry no status column and get none. They are frozen through their
-- parent: a line whose invoice is issued refuses UPDATE and DELETE. INSERT is
-- refused too, which the acceptance list does not name but the principle
-- does: a new line rewrites the invoice's totals, which is an edit wearing
-- different clothes.
CREATE OR REPLACE FUNCTION public.refuse_mutation_of_issued_parent()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_status text;
BEGIN
  SELECT status INTO v_status
    FROM public.sales_invoices WHERE id = COALESCE(NEW.sales_invoice_id, OLD.sales_invoice_id);
  IF v_status = 'issued' THEN
    RAISE EXCEPTION
      '% is append-only once issued: % is not permitted. Correct the record by appending a credit note, not by rewriting.',
      TG_TABLE_NAME, TG_OP
      USING ERRCODE = 'restrict_violation';
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$;

COMMENT ON FUNCTION public.refuse_mutation_of_issued_parent() IS
  'Refuses INSERT, UPDATE and DELETE on lines belonging to an issued invoice. The line table has no status of its own; the parent decides.';

CREATE TRIGGER sales_invoice_items_append_only
BEFORE INSERT OR UPDATE OR DELETE ON public.sales_invoice_items
FOR EACH ROW EXECUTE FUNCTION public.refuse_mutation_of_issued_parent();

-- Prove it, in the transaction itself, then put the database back the way it
-- was: the block ends by raising, which rolls back every row it inserted. A
-- migration that claims a control exists and leaves no evidence of the
-- refusal is worse than one that fails loudly, and N6 is the reason this
-- block refuses to finish quietly if any refusal does not fire.
DO $$
DECLARE
  v_company uuid;
  v_customer uuid;
  v_invoice uuid;
  v_item uuid;
  refused boolean := false;
BEGIN
  INSERT INTO public.companies (name) VALUES ('append-only probe') RETURNING id INTO v_company;
  INSERT INTO public.customers (company_id, name)
    VALUES (v_company, 'append-only probe customer') RETURNING id INTO v_customer;
  INSERT INTO public.products (company_id, sku, name)
    VALUES (v_company, 'PROBE-1', 'probe product');

  -- A draft, editable by construction, so the refusal is proven to be about
  -- status rather than about the trigger firing at everything.
  INSERT INTO public.sales_invoices (company_id, customer_id, customer_name, created_by)
    VALUES (v_company, v_customer, 'append-only probe customer', gen_random_uuid())
    RETURNING id INTO v_invoice;
  INSERT INTO public.sales_invoice_items (sales_invoice_id, product_id, item_code, item_description)
    SELECT v_invoice, p.id, 'PROBE-1', 'probe line'
      FROM public.products p WHERE p.company_id = v_company LIMIT 1
    RETURNING id INTO v_item;
  IF v_item IS NULL THEN
    RAISE EXCEPTION 'the probe seeded no line, so it would prove nothing';
  END IF;
  UPDATE public.sales_invoices SET notes = 'drafts are editable' WHERE id = v_invoice;

  -- The transition, one way.
  UPDATE public.sales_invoices SET status = 'issued' WHERE id = v_invoice;

  BEGIN
    UPDATE public.sales_invoices SET notes = 'tampered' WHERE id = v_invoice;
  EXCEPTION WHEN restrict_violation THEN refused := true; END;
  IF NOT refused THEN
    RAISE EXCEPTION 'the issued-invoice immutability trigger did not refuse an UPDATE';
  END IF;

  refused := false;
  BEGIN
    UPDATE public.sales_invoices SET status = 'draft' WHERE id = v_invoice;
  EXCEPTION WHEN restrict_violation THEN refused := true; END;
  IF NOT refused THEN
    RAISE EXCEPTION 'the immutability trigger did not refuse the issued-to-draft backtrack';
  END IF;

  refused := false;
  BEGIN
    DELETE FROM public.sales_invoices WHERE id = v_invoice;
  EXCEPTION WHEN restrict_violation THEN refused := true; END;
  IF NOT refused THEN
    RAISE EXCEPTION 'the immutability trigger did not refuse a DELETE';
  END IF;

  refused := false;
  BEGIN
    UPDATE public.sales_invoice_items SET quantity_invoiced = 99 WHERE id = v_item;
  EXCEPTION WHEN restrict_violation THEN refused := true; END;
  IF NOT refused THEN
    RAISE EXCEPTION 'the line trigger did not refuse an UPDATE on an issued invoice';
  END IF;

  refused := false;
  BEGIN
    DELETE FROM public.sales_invoice_items WHERE id = v_item;
  EXCEPTION WHEN restrict_violation THEN refused := true; END;
  IF NOT refused THEN
    RAISE EXCEPTION 'the line trigger did not refuse a DELETE on an issued invoice';
  END IF;

  refused := false;
  BEGIN
    INSERT INTO public.sales_invoice_items (sales_invoice_id, product_id, item_code, item_description)
      SELECT v_invoice, p.id, 'PROBE-2', 'smuggled line'
        FROM public.products p WHERE p.company_id = v_company LIMIT 1;
  EXCEPTION WHEN restrict_violation THEN refused := true; END;
  IF NOT refused THEN
    RAISE EXCEPTION 'the line trigger did not refuse an INSERT onto an issued invoice';
  END IF;

  -- And the probe rows leave the way the probe rows of 0017 cannot: an
  -- invoice is frozen, so the only exit is to roll the whole probe back.
  RAISE EXCEPTION 'probe-complete: rolling back';
EXCEPTION
  WHEN raise_exception THEN
    IF SQLERRM <> 'probe-complete: rolling back' THEN
      RAISE;
    END IF;
END;
$$;
