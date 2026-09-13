-- Fix: Change generate_grn_number function from STABLE to VOLATILE to allow UPDATE operations
CREATE OR REPLACE FUNCTION public.generate_grn_number(comp_id uuid)
RETURNS text
LANGUAGE plpgsql
VOLATILE  -- Changed from STABLE to VOLATILE to allow UPDATE operations
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
    config_record RECORD;
    company_name TEXT;
    first_four_letters TEXT;
    counter INTEGER;
    grn_number TEXT;
BEGIN
    -- Check for active document format configuration for GRN
    SELECT * INTO config_record
    FROM public.document_format_configs 
    WHERE company_id = comp_id 
      AND document_type = 'grn' 
      AND is_active = true
    LIMIT 1;
    
    -- If configuration exists, use it
    IF FOUND THEN
        -- Generate using configuration
        grn_number := config_record.prefix || config_record.current_counter || config_record.suffix;
        
        -- Increment the counter
        UPDATE public.document_format_configs 
        SET current_counter = current_counter + 1,
            updated_at = now()
        WHERE id = config_record.id;
        
        RETURN grn_number;
    END IF;
    
    -- Fallback to original hardcoded logic
    -- Get company name
    SELECT name INTO company_name FROM public.companies WHERE id = comp_id;
    
    -- Extract first 4 letters from company name
    first_four_letters := UPPER(SUBSTRING(REGEXP_REPLACE(company_name, '[^A-Za-z]', '', 'g') FROM 1 FOR 4));
    
    -- Ensure we have at least 4 characters, pad with 'X' if needed
    WHILE LENGTH(first_four_letters) < 4 LOOP
        first_four_letters := first_four_letters || 'X';
    END LOOP;
    
    -- Get the next GRN counter starting from 1001
    SELECT COALESCE(MAX(
        CASE 
            WHEN gh.grn_number LIKE 'GRN-' || first_four_letters || '-%' AND 
                 SUBSTRING(gh.grn_number FROM LENGTH('GRN-' || first_four_letters || '-') + 1) ~ '^[0-9]+$' THEN
                CAST(SUBSTRING(gh.grn_number FROM LENGTH('GRN-' || first_four_letters || '-') + 1) AS INTEGER)
            ELSE 1000
        END
    ), 1000) + 1
    INTO counter
    FROM public.grn_header gh
    WHERE gh.company_id = comp_id;
    
    -- Ensure counter starts from 1001 minimum
    IF counter < 1001 THEN
        counter := 1001;
    END IF;
    
    -- Generate GRN number: GRN-First4Letters-Counter
    grn_number := 'GRN-' || first_four_letters || '-' || LPAD(counter::TEXT, 4, '0');
    
    RETURN grn_number;
END;
$function$;