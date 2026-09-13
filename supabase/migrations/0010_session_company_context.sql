-- A session company context, so multi-company membership stops being decided by
-- an unordered LIMIT 1.
--
-- THE DEFECT. Every RLS policy in the schema scopes with one of four helpers,
-- and all four end in `LIMIT 1` with no ORDER BY:
--
--   user_company_id()            SELECT company_id FROM profiles      ... LIMIT 1
--   get_user_company_id()        SELECT company_id FROM profiles      ... LIMIT 1
--   get_user_company_id_safe()   SELECT company_id FROM company_users ... LIMIT 1
--   get_current_company_context()SELECT company_id FROM profiles      ... LIMIT 1
--
-- company_users exists precisely because a person can belong to several
-- companies, so a user in two gets one of them chosen arbitrarily, with no way
-- to switch and no guarantee the same one comes back next query. SECURITY.md N1
-- requires the boundary to flip with the session's company context; there was no
-- session company context to flip.
--
-- THE FIX. One canonical implementation, and the four existing helpers become
-- thin wrappers over it. That repairs all 96 policies without editing any of
-- them, and leaves one place to reason about tenancy.
--
-- THE HEADER IS NOT TRUSTED. The requested company arrives in a client-set
-- header, so it is a request, not an assertion. It is honoured only when the
-- caller has an active membership in that company. An unrecognised or
-- unauthorised value resolves to NULL, and NULL scopes every policy to nothing,
-- which is deny-by-default rather than a fallback to some other company.

-- Membership, from both sources the inherited schema uses. profiles carries a
-- single company_id and company_users carries the many-to-many rows; a user may
-- appear in either or both.
CREATE OR REPLACE FUNCTION public.user_company_memberships()
RETURNS TABLE (company_id uuid)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT cu.company_id
    FROM public.company_users cu
   WHERE cu.user_id = auth.uid()
     AND upper(coalesce(cu.status, 'ACTIVE')) = 'ACTIVE'
  UNION
  SELECT p.company_id
    FROM public.profiles p
   WHERE p.user_id = auth.uid()
     AND p.company_id IS NOT NULL
$$;

COMMENT ON FUNCTION public.user_company_memberships() IS
  'Every company the current user may act in. The authorisation source for the session company context.';

CREATE OR REPLACE FUNCTION public.current_company_id()
RETURNS uuid
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  requested uuid;
  resolved  uuid;
  n_member  integer;
BEGIN
  -- PostgREST exposes request headers as a GUC. Absent outside a request (psql,
  -- a job, a test that has not set one), which is why this is tolerant of NULL
  -- rather than raising.
  BEGIN
    requested := NULLIF(
      current_setting('request.headers', true)::json ->> 'x-vega-company', ''
    )::uuid;
  EXCEPTION WHEN others THEN
    -- A malformed header is a malformed request, not a reason to fall back to
    -- some other company.
    requested := NULL;
  END;

  IF requested IS NOT NULL THEN
    SELECT m.company_id INTO resolved
      FROM public.user_company_memberships() m
     WHERE m.company_id = requested;
    -- NULL when the caller is not a member: the header asked, the membership
    -- answered no, and no company is selected.
    RETURN resolved;
  END IF;

  -- No header. One membership is unambiguous, so use it and keep every existing
  -- single-company session working exactly as before.
  SELECT count(*) INTO n_member FROM public.user_company_memberships();
  IF n_member = 1 THEN
    SELECT m.company_id INTO resolved FROM public.user_company_memberships() m;
    RETURN resolved;
  END IF;

  -- Several memberships and nothing chosen. Returning one of them arbitrarily is
  -- the defect this migration exists to remove, so return nothing and make the
  -- client choose.
  RETURN NULL;
END;
$$;

COMMENT ON FUNCTION public.current_company_id() IS
  'The company this session is acting in. Reads the x-vega-company header, honours it only against an active membership, and returns NULL when several companies are available and none was chosen.';

-- The four inherited helpers become wrappers. Signatures and semantics are
-- preserved for the 96 policies that call them.
CREATE OR REPLACE FUNCTION public.user_company_id() RETURNS uuid
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
  AS $$ SELECT public.current_company_id() $$;

CREATE OR REPLACE FUNCTION public.get_user_company_id() RETURNS uuid
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
  AS $$ SELECT public.current_company_id() $$;

CREATE OR REPLACE FUNCTION public.get_user_company_id_safe() RETURNS uuid
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
  AS $$ SELECT public.current_company_id() $$;

CREATE OR REPLACE FUNCTION public.get_current_company_context() RETURNS uuid
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
  AS $$ SELECT public.current_company_id() $$;

-- What the client needs to render a company switcher. Exposed as an RPC because
-- a user must be able to see their options before choosing one.
CREATE OR REPLACE FUNCTION public.my_companies()
RETURNS TABLE (company_id uuid, company_name text, is_current boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT c.id, c.name, (c.id = public.current_company_id())
    FROM public.companies c
    JOIN public.user_company_memberships() m ON m.company_id = c.id
   ORDER BY c.name
$$;

REVOKE ALL ON FUNCTION public.user_company_memberships() FROM anon;
REVOKE ALL ON FUNCTION public.current_company_id()       FROM anon;
REVOKE ALL ON FUNCTION public.my_companies()             FROM anon;
GRANT EXECUTE ON FUNCTION public.my_companies() TO authenticated;

-- N1 again: every function added here is SECURITY DEFINER, so none may leave
-- search_path mutable.
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

-- No policy may still reach a company through an unordered LIMIT 1.
DO $$
DECLARE bad text;
BEGIN
  SELECT string_agg(p.proname, ', ') INTO bad
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace AND n.nspname = 'public'
   WHERE p.proname IN ('user_company_id','get_user_company_id','get_user_company_id_safe','get_current_company_context')
     AND pg_get_functiondef(p.oid) NOT LIKE '%current_company_id()%';
  IF bad IS NOT NULL THEN
    RAISE EXCEPTION 'company helper not delegating to current_company_id(): %', bad;
  END IF;
END
$$;
