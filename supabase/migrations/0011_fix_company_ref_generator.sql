-- Make `companies` insertable, and insertable more than once.
--
-- TWO DEFECTS, ONE CHAIN. Inserting a company fires
-- auto_generate_company_business_ref, which calls generate_gated_business_ref_no:
--
--   SELECT COALESCE(MAX(CAST(SUBSTRING(business_ref_no FROM 'Rigel-([0-9]+)-')
--          AS INTEGER)), 0) + 1
--     FROM public.gated_business_registration_requests;
--
--   1. That table is created by no inherited migration, so the first insert
--      raises 42P01. Sign-up runs handle_new_user, which inserts into companies,
--      so a fresh database cannot register anybody.
--   2. Even with the table present but empty, the counter always falls through
--      to its 1001 floor and returns the same reference every time, which the
--      unique index on companies.business_ref_no then rejects. One company, ever.
--
-- THE FIX. Count from the table actually being numbered. companies.business_ref_no
-- is what the sequence fills, so it is what the sequence should read. That also
-- retires the orphan dependency rather than recreating an empty table to satisfy
-- it.
--
-- WHY THIS WAS NOT CAUGHT EARLIER. Every schema-shaped check passes: structure
-- complete, RLS on, no policy missing. Both defects only appear when something
-- writes. rigel-inventory's acceptance test could not see them either, because
-- it compares against what PostgREST exposes and the orphan has no grants. It
-- took an INSERT in the tenant isolation suite to surface them.
--
-- The reference prefix changes from 'Rigel-' to 'VG-'. Inherited branding on a
-- customer-visible identifier is not something to carry forward, and no data
-- exists yet to migrate.

CREATE OR REPLACE FUNCTION public.generate_gated_business_ref_no() RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  counter       integer;
  current_month text;
  current_year  text;
BEGIN
  current_month := LPAD(EXTRACT(MONTH FROM NOW())::TEXT, 2, '0');
  current_year  := EXTRACT(YEAR FROM NOW())::TEXT;

  -- Read the column this function fills. Anything else can drift out of step
  -- with reality, which is exactly how the previous version could hand out a
  -- reference that already existed.
  SELECT COALESCE(MAX(CAST(SUBSTRING(business_ref_no FROM 'VG-([0-9]+)-') AS INTEGER)), 0) + 1
    INTO counter
    FROM public.companies
   WHERE business_ref_no ~ '^VG-[0-9]+-';

  IF counter < 1001 THEN
    counter := 1001;
  END IF;

  RETURN 'VG-' || LPAD(counter::TEXT, 4, '0') || '-' || current_month || '-' || current_year;
END;
$$;

-- Two companies must be creatable, not one. Asserting the property that was
-- broken rather than trusting that the rewrite fixed it.
DO $$
DECLARE a uuid; b uuid;
BEGIN
  INSERT INTO public.companies (name) VALUES ('__probe one__') RETURNING id INTO a;
  INSERT INTO public.companies (name) VALUES ('__probe two__') RETURNING id INTO b;

  IF (SELECT business_ref_no FROM public.companies WHERE id = a)
   = (SELECT business_ref_no FROM public.companies WHERE id = b) THEN
    RAISE EXCEPTION 'business_ref_no is not unique across inserts';
  END IF;

  DELETE FROM public.companies WHERE id IN (a, b);
END
$$;
