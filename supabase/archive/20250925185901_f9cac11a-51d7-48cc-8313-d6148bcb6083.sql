-- Update generate_supplier_ref function to use document format configurations
CREATE OR REPLACE FUNCTION public.generate_supplier_ref(supplier_name text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    config_record RECORD;
    supplier_ref TEXT;
    comp_id UUID;
BEGIN
    -- Get the user's company ID
    SELECT user_company_id() INTO comp_id;
    
    -- Check for active document format configuration for supplier_id
    SELECT * INTO config_record
    FROM public.document_format_configs 
    WHERE company_id = comp_id 
      AND document_type = 'supplier_id' 
      AND is_active = true
    LIMIT 1;
    
    -- If configuration exists, use it
    IF FOUND THEN
        -- Generate using configuration
        supplier_ref := config_record.prefix || config_record.current_counter || config_record.suffix;
        
        -- Increment the counter
        UPDATE public.document_format_configs 
        SET current_counter = current_counter + 1,
            updated_at = now()
        WHERE id = config_record.id;
        
        RETURN supplier_ref;
    END IF;
    
    -- Fallback to original hardcoded logic
    DECLARE
        first_four_letters TEXT;
        date_part TEXT;
        ref_no TEXT;
        counter INTEGER := 1;
        final_ref TEXT;
    BEGIN
        -- Extract first 4 letters from supplier name
        first_four_letters := UPPER(SUBSTRING(REGEXP_REPLACE(supplier_name, '[^A-Za-z]', '', 'g') FROM 1 FOR 4));
        
        -- Ensure we have at least 4 characters, pad with 'X' if needed
        WHILE LENGTH(first_four_letters) < 4 LOOP
            first_four_letters := first_four_letters || 'X';
        END LOOP;
        
        -- Get current date in DDMMYYYY format
        date_part := to_char(NOW(), 'DDMMYYYY');
        
        -- Generate base reference number
        ref_no := first_four_letters || date_part;
        final_ref := ref_no;
        
        -- Check for uniqueness and add counter if needed
        WHILE EXISTS (SELECT 1 FROM public.suppliers WHERE supplier_ref = final_ref) LOOP
            final_ref := ref_no || '-' || LPAD(counter::TEXT, 2, '0');
            counter := counter + 1;
        END LOOP;
        
        RETURN final_ref;
    END;
END;
$function$;

-- Update generate_customer_ref function to use document format configurations
CREATE OR REPLACE FUNCTION public.generate_customer_ref(customer_name text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    config_record RECORD;
    customer_ref TEXT;
    comp_id UUID;
BEGIN
    -- Get the user's company ID
    SELECT user_company_id() INTO comp_id;
    
    -- Check for active document format configuration for customer_id
    SELECT * INTO config_record
    FROM public.document_format_configs 
    WHERE company_id = comp_id 
      AND document_type = 'customer_id' 
      AND is_active = true
    LIMIT 1;
    
    -- If configuration exists, use it
    IF FOUND THEN
        -- Generate using configuration
        customer_ref := config_record.prefix || config_record.current_counter || config_record.suffix;
        
        -- Increment the counter
        UPDATE public.document_format_configs 
        SET current_counter = current_counter + 1,
            updated_at = now()
        WHERE id = config_record.id;
        
        RETURN customer_ref;
    END IF;
    
    -- Fallback to original hardcoded logic
    DECLARE
        first_four_letters TEXT;
        current_month TEXT;
        current_year TEXT;
        ref_no TEXT;
        counter INTEGER := 1;
        final_ref TEXT;
    BEGIN
        -- Extract first 4 letters from customer name
        first_four_letters := UPPER(SUBSTRING(REGEXP_REPLACE(customer_name, '[^A-Za-z]', '', 'g') FROM 1 FOR 4));
        
        -- Ensure we have at least 4 characters, pad with 'X' if needed
        WHILE LENGTH(first_four_letters) < 4 LOOP
            first_four_letters := first_four_letters || 'X';
        END LOOP;
        
        -- Get current month and year
        current_month := LPAD(EXTRACT(MONTH FROM NOW())::TEXT, 2, '0');
        current_year := EXTRACT(YEAR FROM NOW())::TEXT;
        
        -- Generate base reference number
        ref_no := first_four_letters || '-' || current_month || current_year;
        final_ref := ref_no;
        
        -- Check for uniqueness and add counter if needed
        WHILE EXISTS (SELECT 1 FROM public.customers WHERE customer_ref = final_ref) LOOP
            final_ref := ref_no || '-' || LPAD(counter::TEXT, 3, '0');
            counter := counter + 1;
        END LOOP;
        
        RETURN final_ref;
    END;
END;
$function$;

-- Update generate_grn_number function to use document format configurations
CREATE OR REPLACE FUNCTION public.generate_grn_number(comp_id uuid)
RETURNS text
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    config_record RECORD;
    grn_number TEXT;
BEGIN
    -- Check for active document format configuration for grn
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
    DECLARE
        company_name TEXT;
        first_four_letters TEXT;
        current_date_str TEXT;
        counter INTEGER;
        v_grn_number TEXT;
    BEGIN
        -- Get company name
        SELECT name INTO company_name FROM public.companies WHERE id = comp_id;

        -- Extract first 4 letters from company name
        first_four_letters := UPPER(SUBSTRING(REGEXP_REPLACE(company_name, '[^A-Za-z]', '', 'g') FROM 1 FOR 4));

        -- Ensure we have at least 4 characters, pad with 'X' if needed
        WHILE LENGTH(first_four_letters) < 4 LOOP
            first_four_letters := first_four_letters || 'X';
        END LOOP;

        -- Get current date in MMDDYYYY format
        current_date_str := to_char(now(), 'MMDDYYYY');

        -- Use table alias to avoid ambiguity with local variables
        SELECT COALESCE(MAX(
            CASE 
                WHEN gh.grn_number LIKE first_four_letters || 'GRN' || current_date_str || '%' THEN
                    CAST(SUBSTRING(gh.grn_number FROM LENGTH(first_four_letters || 'GRN' || current_date_str) + 1) AS INTEGER)
                ELSE 0
            END
        ), 0) + 1
        INTO counter
        FROM public.grn_header gh
        WHERE gh.company_id = comp_id;

        -- Generate GRN number: COMPGRN + MMDDYYYY + counter
        v_grn_number := first_four_letters || 'GRN' || current_date_str || LPAD(counter::TEXT, 3, '0');

        RETURN v_grn_number;
    END;
END;
$function$;

-- Update generate_debit_note_number function to use document format configurations
CREATE OR REPLACE FUNCTION public.generate_debit_note_number(comp_id uuid)
RETURNS text
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    config_record RECORD;
    debit_note_number TEXT;
BEGIN
    -- Check for active document format configuration for debit_note
    SELECT * INTO config_record
    FROM public.document_format_configs 
    WHERE company_id = comp_id 
      AND document_type = 'debit_note' 
      AND is_active = true
    LIMIT 1;
    
    -- If configuration exists, use it
    IF FOUND THEN
        -- Generate using configuration
        debit_note_number := config_record.prefix || config_record.current_counter || config_record.suffix;
        
        -- Increment the counter
        UPDATE public.document_format_configs 
        SET current_counter = current_counter + 1,
            updated_at = now()
        WHERE id = config_record.id;
        
        RETURN debit_note_number;
    END IF;
    
    -- Fallback to original hardcoded logic
    DECLARE
        company_name TEXT;
        first_four_letters TEXT;
        counter INTEGER;
        v_debit_note_number TEXT;
    BEGIN
        -- Get company name
        SELECT name INTO company_name FROM public.companies WHERE id = comp_id;
        
        -- Extract first 4 letters from company name
        first_four_letters := UPPER(SUBSTRING(REGEXP_REPLACE(company_name, '[^A-Za-z]', '', 'g') FROM 1 FOR 4));
        
        -- Ensure we have at least 4 characters, pad with 'X' if needed
        WHILE LENGTH(first_four_letters) < 4 LOOP
            first_four_letters := first_four_letters || 'X';
        END LOOP;
        
        -- Get the next debit note counter starting from 1001
        SELECT COALESCE(MAX(
            CASE 
                WHEN dn.debit_note_number LIKE first_four_letters || 'DN%' AND 
                     SUBSTRING(dn.debit_note_number FROM LENGTH(first_four_letters || 'DN') + 1) ~ '^[0-9]+$' THEN
                    CAST(SUBSTRING(dn.debit_note_number FROM LENGTH(first_four_letters || 'DN') + 1) AS INTEGER)
                ELSE 1000
            END
        ), 1000) + 1
        INTO counter
        FROM public.debit_notes dn
        WHERE dn.company_id = comp_id;
        
        -- Ensure counter starts from 1001 minimum
        IF counter < 1001 THEN
            counter := 1001;
        END IF;
        
        -- Generate debit note number: First4LettersDN + Counter starting from 1001
        v_debit_note_number := first_four_letters || 'DN' || counter::TEXT;
        
        RETURN v_debit_note_number;
    END;
END;
$function$;

-- Update generate_rso_number function to use document format configurations
CREATE OR REPLACE FUNCTION public.generate_rso_number(p_customer_id uuid, p_company_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    config_record RECORD;
    rso_number TEXT;
BEGIN
    -- Check for active document format configuration for return_sales_order
    SELECT * INTO config_record
    FROM public.document_format_configs 
    WHERE company_id = p_company_id 
      AND document_type = 'return_sales_order' 
      AND is_active = true
    LIMIT 1;
    
    -- If configuration exists, use it
    IF FOUND THEN
        -- Generate using configuration
        rso_number := config_record.prefix || config_record.current_counter || config_record.suffix;
        
        -- Increment the counter
        UPDATE public.document_format_configs 
        SET current_counter = current_counter + 1,
            updated_at = now()
        WHERE id = config_record.id;
        
        RETURN rso_number;
    END IF;
    
    -- Fallback to original hardcoded logic
    DECLARE
        customer_name TEXT;
        first_four_letters TEXT;
        counter INTEGER;
        v_rso_number TEXT;
    BEGIN
        -- Get customer name
        SELECT name INTO customer_name FROM public.customers WHERE id = p_customer_id;
        
        -- Extract first 4 letters from customer name
        first_four_letters := UPPER(SUBSTRING(REGEXP_REPLACE(customer_name, '[^A-Za-z]', '', 'g') FROM 1 FOR 4));
        
        -- Ensure we have at least 4 characters, pad with 'X' if needed
        WHILE LENGTH(first_four_letters) < 4 LOOP
            first_four_letters := first_four_letters || 'X';
        END LOOP;
        
        -- Get the next RSO counter starting from 1001
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
        
        -- Ensure counter starts from 1001 minimum
        IF counter < 1001 THEN
            counter := 1001;
        END IF;
        
        -- Generate RSO number: First4LettersRSO + Counter starting from 1001
        v_rso_number := first_four_letters || 'RSO' || counter::TEXT;
        
        RETURN v_rso_number;
    END;
END;
$function$;