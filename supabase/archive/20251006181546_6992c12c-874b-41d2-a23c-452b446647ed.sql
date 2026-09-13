-- Update generate_business_ref_no function to use Rigel instead of PRISM
CREATE OR REPLACE FUNCTION public.generate_business_ref_no(company_name text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    first_four_letters TEXT;
    current_month TEXT;
    current_year TEXT;
    ref_no TEXT;
BEGIN
    -- Extract first 4 letters from company name
    first_four_letters := UPPER(SUBSTRING(REGEXP_REPLACE(company_name, '[^A-Za-z]', '', 'g') FROM 1 FOR 4));
    
    -- Get current month and year
    current_month := LPAD(EXTRACT(MONTH FROM NOW())::TEXT, 2, '0');
    current_year := EXTRACT(YEAR FROM NOW())::TEXT;
    
    -- Generate reference number with Rigel prefix
    ref_no := 'Rigel-' || first_four_letters || '-' || current_month || '-' || current_year;
    
    RETURN ref_no;
END;
$function$;

-- Update generate_gated_business_ref_no function to use Rigel instead of PRISM
CREATE OR REPLACE FUNCTION public.generate_gated_business_ref_no()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    new_ref TEXT;
    counter INTEGER;
    current_month TEXT;
    current_year TEXT;
BEGIN
    -- Get current month and year
    current_month := LPAD(EXTRACT(MONTH FROM NOW())::TEXT, 2, '0');
    current_year := EXTRACT(YEAR FROM NOW())::TEXT;
    
    -- Get the next counter
    SELECT COALESCE(MAX(CAST(SUBSTRING(business_ref_no FROM 'Rigel-([0-9]+)-') AS INTEGER)), 0) + 1
    INTO counter
    FROM public.gated_business_registration_requests;
    
    -- Ensure counter starts from 1001 minimum
    IF counter < 1001 THEN
        counter := 1001;
    END IF;
    
    -- Generate reference number: Rigel-Counter-MM-YYYY
    new_ref := 'Rigel-' || LPAD(counter::TEXT, 4, '0') || '-' || current_month || '-' || current_year;
    
    RETURN new_ref;
END;
$function$;