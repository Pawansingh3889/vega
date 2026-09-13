-- SECURITY.md V2: the two SECURITY DEFINER functions with a mutable search_path.
--
-- N1 makes an unpinned definer a build failure rather than a review item, so
-- these had to go one way or the other. Pinning them would have been the obvious
-- fix and the wrong one, because both are dead:
--
--   auto_generate_business_ref()   a trigger function attached to no trigger.
--   generate_business_ref_no()     queries public.businesses, which does not
--                                  exist in this schema. Calling it raises.
--
-- So this drops them. A pinned search_path on an unreachable function that would
-- error if reached is a green check over a dead body.
--
-- The one-argument overload generate_business_ref_no(company_name text) is a
-- different function: it already pins search_path, it works, and it stays.

DROP FUNCTION IF EXISTS public.auto_generate_business_ref();
DROP FUNCTION IF EXISTS public.generate_business_ref_no();

DO $$
DECLARE
  unpinned text;
BEGIN
  SELECT string_agg(p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')', ', ')
    INTO unpinned
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace AND n.nspname = 'public'
   WHERE p.prosecdef
     AND (p.proconfig IS NULL
          OR NOT EXISTS (SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE 'search_path=%'));

  IF unpinned IS NOT NULL THEN
    RAISE EXCEPTION 'SECURITY DEFINER without a pinned search_path: %', unpinned;
  END IF;
END
$$;
