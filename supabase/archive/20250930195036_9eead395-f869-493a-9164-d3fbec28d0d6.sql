-- Remove suffix column from document_format_configs table
ALTER TABLE public.document_format_configs DROP COLUMN IF EXISTS suffix;

-- Update generate_grn_number function to remove suffix
CREATE OR REPLACE FUNCTION public.generate_grn_number(comp_id uuid)
RETURNS text
LANGUAGE plpgsql
VOLATILE
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
        -- Generate using configuration (without suffix)
        grn_number := config_record.prefix || config_record.current_counter;
        
        -- Increment the counter
        UPDATE public.document_format_configs 
        SET current_counter = current_counter + 1,
            updated_at = now()
        WHERE id = config_record.id;
        
        RETURN grn_number;
    END IF;
    
    -- Fallback to original hardcoded logic
    SELECT name INTO company_name FROM public.companies WHERE id = comp_id;
    first_four_letters := UPPER(SUBSTRING(REGEXP_REPLACE(company_name, '[^A-Za-z]', '', 'g') FROM 1 FOR 4));
    
    WHILE LENGTH(first_four_letters) < 4 LOOP
        first_four_letters := first_four_letters || 'X';
    END LOOP;
    
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
    
    IF counter < 1001 THEN
        counter := 1001;
    END IF;
    
    grn_number := 'GRN-' || first_four_letters || '-' || LPAD(counter::TEXT, 4, '0');
    RETURN grn_number;
END;
$function$;

-- Update generate_invoice_number function to remove suffix
CREATE OR REPLACE FUNCTION public.generate_invoice_number(comp_id uuid)
RETURNS text
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
    config_record RECORD;
    company_name TEXT;
    first_four_letters TEXT;
    counter INTEGER;
    invoice_number TEXT;
BEGIN
    SELECT * INTO config_record
    FROM public.document_format_configs 
    WHERE company_id = comp_id 
    AND document_type = 'sales_invoice' 
    AND is_active = true
    LIMIT 1;
    
    IF FOUND THEN
        invoice_number := config_record.prefix || config_record.current_counter;
        
        UPDATE public.document_format_configs 
        SET current_counter = current_counter + 1,
            updated_at = now()
        WHERE id = config_record.id;
        
        RETURN invoice_number;
    ELSE
        SELECT name INTO company_name FROM public.companies WHERE id = comp_id;
        first_four_letters := UPPER(SUBSTRING(REGEXP_REPLACE(company_name, '[^A-Za-z]', '', 'g') FROM 1 FOR 4));
        
        WHILE LENGTH(first_four_letters) < 4 LOOP
            first_four_letters := first_four_letters || 'X';
        END LOOP;
        
        SELECT COALESCE(MAX(
            CASE 
                WHEN si.invoice_number LIKE first_four_letters || 'INV%' AND 
                     SUBSTRING(si.invoice_number FROM LENGTH(first_four_letters || 'INV') + 1) ~ '^[0-9]+$' THEN
                    CAST(SUBSTRING(si.invoice_number FROM LENGTH(first_four_letters || 'INV') + 1) AS INTEGER)
                ELSE 1000
            END
        ), 1000) + 1
        INTO counter
        FROM public.sales_invoices si
        WHERE si.company_id = comp_id;
        
        IF counter < 1001 THEN
            counter := 1001;
        END IF;
        
        invoice_number := first_four_letters || 'INV' || counter::TEXT;
        RETURN invoice_number;
    END IF;
END;
$function$;

-- Update generate_debit_note_number function to remove suffix
CREATE OR REPLACE FUNCTION public.generate_debit_note_number(comp_id uuid)
RETURNS text
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
    config_record RECORD;
    debit_note_number TEXT;
    company_name TEXT;
    first_four_letters TEXT;
    counter INTEGER;
BEGIN
    SELECT * INTO config_record
    FROM public.document_format_configs 
    WHERE company_id = comp_id 
      AND document_type = 'debit_note' 
      AND is_active = true
    LIMIT 1;
    
    IF FOUND THEN
        debit_note_number := config_record.prefix || config_record.current_counter;
        
        UPDATE public.document_format_configs 
        SET current_counter = current_counter + 1,
            updated_at = now()
        WHERE id = config_record.id;
        
        RETURN debit_note_number;
    END IF;
    
    SELECT name INTO company_name FROM public.companies WHERE id = comp_id;
    first_four_letters := UPPER(SUBSTRING(REGEXP_REPLACE(company_name, '[^A-Za-z]', '', 'g') FROM 1 FOR 4));
    
    WHILE LENGTH(first_four_letters) < 4 LOOP
        first_four_letters := first_four_letters || 'X';
    END LOOP;
    
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
    
    IF counter < 1001 THEN
        counter := 1001;
    END IF;
    
    debit_note_number := first_four_letters || 'DN' || counter::TEXT;
    RETURN debit_note_number;
END;
$function$;

-- Update generate_customer_ref function to remove suffix
CREATE OR REPLACE FUNCTION public.generate_customer_ref(customer_name text)
RETURNS text
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
    config_record RECORD;
    customer_ref TEXT;
    comp_id UUID;
    first_four_letters TEXT;
    current_month TEXT;
    current_year TEXT;
    ref_no TEXT;
    counter INTEGER := 1;
    final_ref TEXT;
BEGIN
    SELECT user_company_id() INTO comp_id;
    
    SELECT * INTO config_record
    FROM public.document_format_configs 
    WHERE company_id = comp_id 
      AND document_type = 'customer_id' 
      AND is_active = true
    LIMIT 1;
    
    IF FOUND THEN
        customer_ref := config_record.prefix || config_record.current_counter;
        
        UPDATE public.document_format_configs 
        SET current_counter = current_counter + 1,
            updated_at = now()
        WHERE id = config_record.id;
        
        RETURN customer_ref;
    END IF;
    
    first_four_letters := UPPER(SUBSTRING(REGEXP_REPLACE(customer_name, '[^A-Za-z]', '', 'g') FROM 1 FOR 4));
    
    WHILE LENGTH(first_four_letters) < 4 LOOP
        first_four_letters := first_four_letters || 'X';
    END LOOP;
    
    current_month := LPAD(EXTRACT(MONTH FROM NOW())::TEXT, 2, '0');
    current_year := EXTRACT(YEAR FROM NOW())::TEXT;
    ref_no := first_four_letters || '-' || current_month || current_year;
    final_ref := ref_no;
    
    WHILE EXISTS (SELECT 1 FROM public.customers WHERE customer_ref = final_ref) LOOP
        final_ref := ref_no || '-' || LPAD(counter::TEXT, 3, '0');
        counter := counter + 1;
    END LOOP;
    
    RETURN final_ref;
END;
$function$;

-- Update generate_supplier_ref function to remove suffix
CREATE OR REPLACE FUNCTION public.generate_supplier_ref(supplier_name text)
RETURNS text
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
    config_record RECORD;
    supplier_ref TEXT;
    comp_id UUID;
    first_four_letters TEXT;
    date_part TEXT;
    ref_no TEXT;
    counter INTEGER := 1;
    final_ref TEXT;
BEGIN
    SELECT user_company_id() INTO comp_id;
    
    SELECT * INTO config_record
    FROM public.document_format_configs 
    WHERE company_id = comp_id 
      AND document_type = 'supplier_id' 
      AND is_active = true
    LIMIT 1;
    
    IF FOUND THEN
        supplier_ref := config_record.prefix || config_record.current_counter;
        
        UPDATE public.document_format_configs 
        SET current_counter = current_counter + 1,
            updated_at = now()
        WHERE id = config_record.id;
        
        RETURN supplier_ref;
    END IF;
    
    first_four_letters := UPPER(SUBSTRING(REGEXP_REPLACE(supplier_name, '[^A-Za-z]', '', 'g') FROM 1 FOR 4));
    
    WHILE LENGTH(first_four_letters) < 4 LOOP
        first_four_letters := first_four_letters || 'X';
    END LOOP;
    
    date_part := to_char(NOW(), 'DDMMYYYY');
    ref_no := first_four_letters || date_part;
    final_ref := ref_no;
    
    WHILE EXISTS (SELECT 1 FROM public.suppliers WHERE supplier_ref = final_ref) LOOP
        final_ref := ref_no || '-' || LPAD(counter::TEXT, 2, '0');
        counter := counter + 1;
    END LOOP;
    
    RETURN final_ref;
END;
$function$;