-- Update existing companies with PRISM prefix to Rigel prefix
UPDATE public.companies 
SET business_ref_no = REPLACE(business_ref_no, 'PRISM-', 'Rigel-')
WHERE business_ref_no LIKE 'PRISM-%';

-- Update existing gated_business_registration_requests if they exist
-- (Check if table exists first)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables 
    WHERE table_schema = 'public'
    AND table_name = 'gated_business_registration_requests'
  ) THEN
    UPDATE public.gated_business_registration_requests 
    SET business_ref_no = REPLACE(business_ref_no, 'PRISM-', 'Rigel-')
    WHERE business_ref_no LIKE 'PRISM-%';
  END IF;
END $$;