-- A developer override, deliberately built to be removable.
--
-- WHAT IT DOES. A named developer can act in ANY company by setting the
-- x-vega-company header, without being a member of it. Everything else is
-- unchanged: still one company at a time, still through current_company_id(),
-- so every screen, report and policy behaves exactly as it does for a real
-- user. That is the point. An override that returns every tenant's rows at once
-- would break every company-scoped query in the product and would be a
-- different, larger hole.
--
-- WHY IT IS NOT BYPASSRLS. A role with BYPASSRLS sees everything everywhere and
-- nothing in the schema can constrain it. This override is expressed in the same
-- helper the policies already use, so it cannot reach further than the policies
-- do, and revoking it is a DELETE.
--
-- HONEST LIMITS, so nobody discovers these later:
--   * There is no per-query audit trail. current_company_id() is evaluated
--     inside policy checks, potentially per row, and writing an audit row there
--     would be a performance disaster. The grant below IS the record: who, why,
--     and until when.
--   * While a grant is live, that account can read any tenant's data. It is a
--     real hole, opened on purpose, with an expiry attached.
--
-- REMOVING IT. Delete the row, or drop the table and re-run 0010's definition of
-- current_company_id(). The teardown is one migration, which is why the override
-- lives in its own table rather than being sprinkled through 96 policies.

CREATE TABLE public.developer_access (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email       text NOT NULL UNIQUE,
  reason      text NOT NULL,
  granted_at  timestamp with time zone NOT NULL DEFAULT now(),
  -- Not nullable on purpose. A grant with no end is a permanent backdoor
  -- wearing a temporary label.
  expires_at  timestamp with time zone NOT NULL,
  CONSTRAINT developer_access_expiry_forward CHECK (expires_at > granted_at),
  CONSTRAINT developer_access_reason_meaningful CHECK (length(reason) >= 20)
);

COMMENT ON TABLE public.developer_access IS
  'Accounts that may act in any company without membership. Every row is a live cross-tenant hole; keep the list short and the expiry near.';

-- Nobody reaches this table through the API. Adding or removing a grant is a
-- deliberate act with the service role or a migration, not something the
-- application can do to itself.
ALTER TABLE public.developer_access ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Service role manages developer access" ON public.developer_access
  FOR ALL TO service_role USING (true) WITH CHECK (true);
REVOKE ALL ON public.developer_access FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.is_developer()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT EXISTS (
    SELECT 1
      FROM public.developer_access d
      JOIN auth.users u ON lower(u.email) = lower(d.email)
     WHERE u.id = auth.uid()
       AND d.expires_at > now()
  )
$$;

COMMENT ON FUNCTION public.is_developer() IS
  'True when the caller holds an unexpired developer grant. Expiry is checked here, so a lapsed grant stops working without anyone remembering to delete it.';

-- current_company_id() gains one branch. Everything else is 0010 unchanged.
CREATE OR REPLACE FUNCTION public.current_company_id()
RETURNS uuid
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  requested uuid;
  resolved  uuid;
  n_member  integer;
BEGIN
  BEGIN
    requested := NULLIF(
      current_setting('request.headers', true)::json ->> 'x-vega-company', ''
    )::uuid;
  EXCEPTION WHEN others THEN
    requested := NULL;
  END;

  -- The developer branch. A held grant means the requested company is honoured
  -- without membership. Note it still requires a company to be REQUESTED: a
  -- developer with no header is treated like anyone else and gets their own
  -- memberships, so the override never fires by accident.
  IF requested IS NOT NULL AND public.is_developer() THEN
    RETURN (SELECT c.id FROM public.companies c WHERE c.id = requested);
  END IF;

  IF requested IS NOT NULL THEN
    SELECT m.company_id INTO resolved
      FROM public.user_company_memberships() m
     WHERE m.company_id = requested;
    RETURN resolved;
  END IF;

  SELECT count(*) INTO n_member FROM public.user_company_memberships();
  IF n_member = 1 THEN
    SELECT m.company_id INTO resolved FROM public.user_company_memberships() m;
    RETURN resolved;
  END IF;

  RETURN NULL;
END;
$$;

-- A developer also needs to see which companies exist in order to choose one.
CREATE OR REPLACE FUNCTION public.my_companies()
RETURNS TABLE (company_id uuid, company_name text, is_current boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT c.id, c.name, (c.id = public.current_company_id())
    FROM public.companies c
   WHERE public.is_developer()
      OR EXISTS (SELECT 1 FROM public.user_company_memberships() m WHERE m.company_id = c.id)
   ORDER BY c.name
$$;

GRANT EXECUTE ON FUNCTION public.is_developer() TO authenticated;
REVOKE ALL ON FUNCTION public.is_developer() FROM anon;

DO $$
DECLARE unpinned text;
BEGIN
  SELECT string_agg(p.proname, ', ') INTO unpinned
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace AND n.nspname = 'public'
   WHERE p.prosecdef
     AND (p.proconfig IS NULL
          OR NOT EXISTS (SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE 'search_path=%'));
  IF unpinned IS NOT NULL THEN
    RAISE EXCEPTION 'SECURITY DEFINER without a pinned search_path: %', unpinned;
  END IF;
END
$$;
