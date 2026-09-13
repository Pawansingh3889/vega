-- Fix RSO and Credit Note number generation to follow document format configurations

-- Fix RSO number generation to use correct document_type
CREATE OR REPLACE FUNCTION public.generate_rso_number(p_customer_id uuid, p_company_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    config_record RECORD;
    customer_name TEXT;
    first_four_letters TEXT;
    counter INTEGER;
    rso_number TEXT;
BEGIN
    -- Check for active document format configuration for RSO
    SELECT * INTO config_record
    FROM public.document_format_configs 
    WHERE company_id = p_company_id 
      AND document_type = 'return_sales_order'  -- FIXED: Changed from 'rso'
      AND is_active = true
    LIMIT 1;
    
    -- If configuration exists, use it (prefix + counter only, no suffix)
    IF FOUND THEN
        rso_number := config_record.prefix || config_record.current_counter;
        
        -- Increment the counter
        UPDATE public.document_format_configs 
        SET current_counter = current_counter + 1,
            updated_at = now()
        WHERE id = config_record.id;
        
        RETURN rso_number;
    END IF;
    
    -- Fallback to original hardcoded logic
    SELECT name INTO customer_name FROM public.customers WHERE id = p_customer_id;
    first_four_letters := UPPER(SUBSTRING(REGEXP_REPLACE(customer_name, '[^A-Za-z]', '', 'g') FROM 1 FOR 4));
    
    WHILE LENGTH(first_four_letters) < 4 LOOP
        first_four_letters := first_four_letters || 'X';
    END LOOP;
    
    SELECT COALESCE(MAX(
        CASE 
            WHEN roh.rso_number LIKE first_four_letters || 'RSO%' AND 
                 SUBSTRING(roh.rso_number FROM LENGTH(first_four_letters || 'RSO') + 1) ~ '^[0-9]+$' THEN
                CAST(SUBSTRING(roh.rso_number FROM LENGTH(first_four_letters || 'RSO') + 1) AS INTEGER)
            ELSE 1000
        END
    ), 1000) + 1
    INTO counter
    FROM public.return_order_header roh
    WHERE roh.company_id = p_company_id;
    
    IF counter < 1001 THEN
        counter := 1001;
    END IF;
    
    rso_number := first_four_letters || 'RSO' || counter::TEXT;
    RETURN rso_number;
END;
$function$;

-- Rewrite Credit Note number generation to check document format configurations
CREATE OR REPLACE FUNCTION public.generate_cn_number(comp_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
    config_record RECORD;
    company_name TEXT;
    first_four_letters TEXT;
    counter INTEGER;
    cn_number TEXT;
BEGIN
    -- Check for active document format configuration for Credit Note
    SELECT * INTO config_record
    FROM public.document_format_configs 
    WHERE company_id = comp_id 
      AND document_type = 'credit_note'
      AND is_active = true
    LIMIT 1;
    
    -- If configuration exists, use it (prefix + counter only, no suffix)
    IF FOUND THEN
        cn_number := config_record.prefix || config_record.current_counter;
        
        -- Increment the counter
        UPDATE public.document_format_configs 
        SET current_counter = current_counter + 1,
            updated_at = now()
        WHERE id = config_record.id;
        
        RETURN cn_number;
    END IF;
    
    -- Fallback to original hardcoded logic
    SELECT name INTO company_name FROM public.companies WHERE id = comp_id;
    
    first_four_letters := UPPER(SUBSTRING(REGEXP_REPLACE(company_name, '[^A-Za-z]', '', 'g') FROM 1 FOR 4));
    
    WHILE LENGTH(first_four_letters) < 4 LOOP
        first_four_letters := first_four_letters || 'X';
    END LOOP;
    
    SELECT COALESCE(MAX(
        CASE 
            WHEN cn.cn_number LIKE first_four_letters || '-CN-%' AND 
                 SUBSTRING(cn.cn_number FROM LENGTH(first_four_letters || '-CN-') + 1 FOR LENGTH(cn.cn_number) - LENGTH(first_four_letters || '-CN-') - 1) ~ '^[0-9]+$' THEN
                CAST(SUBSTRING(cn.cn_number FROM LENGTH(first_four_letters || '-CN-') + 1 FOR LENGTH(cn.cn_number) - LENGTH(first_four_letters || '-CN-') - 1) AS INTEGER)
            ELSE 10000
        END
    ), 10000) + 1
    INTO counter
    FROM public.credit_notes cn
    WHERE cn.company_id = comp_id;
    
    IF counter < 10001 THEN
        counter := 10001;
    END IF;
    
    cn_number := first_four_letters || '-CN-' || counter::TEXT || 'S';
    
    RETURN cn_number;
END;
$function$;