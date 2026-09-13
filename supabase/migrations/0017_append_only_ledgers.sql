-- SECURITY.md N2: append-only, enforced by grants and a trigger rather than by
-- convention.
--
-- N2 has been written down since the first commit and enforced by nothing. A
-- non-negotiable that only exists in a document is a convention, and the whole
-- point of these tables is that somebody can be told, later and under pressure,
-- that nothing was quietly changed.
--
-- ENFORCED TWICE, deliberately, following Seamly's pattern:
--
--   1. A trigger that raises on UPDATE and DELETE. This binds EVERY role,
--      including service_role, which bypasses row level security but not
--      triggers. That matters here: the audit tables are exactly what somebody
--      with the service key would want to edit.
--   2. Withheld grants, so the ordinary roles cannot even attempt it and get a
--      clear refusal rather than a trigger exception.
--
-- WHICH TABLES. The ledgers that exist today:
--
--   security_audit_log, transaction_audit_log   what happened, and when
--   batch_movements                             the traceability ledger
--   fx_rates                                    a rate for a day does not change
--
-- NOT YET: issued invoices and credit notes. sales_invoices.status is currently
-- constrained to 'finalized' alone, so there is no draft state to become
-- immutable FROM. Making it append-only now would block the drafting Phase 3
-- introduces. It lands with Phase 3, where issuing is a real transition.

CREATE OR REPLACE FUNCTION public.refuse_mutation()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  RAISE EXCEPTION
    '% is append-only: % is not permitted. Correct the record by appending, not by rewriting.',
    TG_TABLE_NAME, TG_OP
    USING ERRCODE = 'restrict_violation';
END;
$$;

COMMENT ON FUNCTION public.refuse_mutation() IS
  'Refuses UPDATE and DELETE on append-only ledgers. Binds every role including service_role, which bypasses RLS but not triggers.';

DO $$
DECLARE
  t text;
  ledgers text[] := ARRAY[
    'security_audit_log',
    'transaction_audit_log',
    'batch_movements',
    'fx_rates'
  ];
BEGIN
  FOREACH t IN ARRAY ledgers LOOP
    IF to_regclass('public.' || t) IS NULL THEN
      RAISE EXCEPTION 'expected append-only ledger public.% to exist', t;
    END IF;

    EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I', t || '_append_only', t);
    EXECUTE format(
      'CREATE TRIGGER %I BEFORE UPDATE OR DELETE ON public.%I '
      'FOR EACH ROW EXECUTE FUNCTION public.refuse_mutation()',
      t || '_append_only', t);

    -- Second layer. anon and authenticated lose the ability to try at all;
    -- service_role keeps INSERT because the edge functions write these.
    EXECUTE format('REVOKE UPDATE, DELETE ON public.%I FROM anon, authenticated, service_role', t);
  END LOOP;
END
$$;

-- Prove both layers, rather than trusting that creating a trigger means it
-- fires. A migration that says it enforced something and did not is worse than
-- one that did nothing.
DO $$
DECLARE
  probe_id uuid;
  refused  boolean := false;
BEGIN
  INSERT INTO public.security_audit_log (action, details, severity)
  VALUES ('vega.n2_probe',
          '{"why":"proving the append-only trigger fires"}'::jsonb,
          'info')
  RETURNING id INTO probe_id;

  BEGIN
    UPDATE public.security_audit_log SET action = 'tampered' WHERE id = probe_id;
  EXCEPTION WHEN restrict_violation THEN
    refused := true;
  END;
  IF NOT refused THEN
    RAISE EXCEPTION 'the append-only trigger did not refuse an UPDATE';
  END IF;

  refused := false;
  BEGIN
    DELETE FROM public.security_audit_log WHERE id = probe_id;
  EXCEPTION WHEN restrict_violation THEN
    refused := true;
  END;
  IF NOT refused THEN
    RAISE EXCEPTION 'the append-only trigger did not refuse a DELETE';
  END IF;

  -- The probe row stays. That is the nature of the thing being proved: it
  -- cannot be tidied away, which is precisely the property N2 wants.
END
$$;
