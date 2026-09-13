-- Fix all document generation functions to remove suffix field references
-- Update pattern: prefix + current_counter (no suffix)

-- 1. Fix generate_so_number function
CREATE OR REPLACE FUNCTION public.generate_so_number(comp_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    config_record RECORD;
    company_name TEXT;
    first_four_letters TEXT;
    counter INTEGER;
    so_number TEXT;
BEGIN
    -- Check for active document format configuration for sales orders
    SELECT * INTO config_record
    FROM public.document_format_configs 
    WHERE company_id = comp_id 
      AND document_type = 'sales_order' 
      AND is_active = true
    LIMIT 1;
    
    -- If configuration exists, use it (prefix + counter only, no suffix)
    IF FOUND THEN
        so_number := config_record.prefix || config_record.current_counter;
        
        -- Increment the counter
        UPDATE public.document_format_configs 
        SET current_counter = current_counter + 1,
            updated_at = now()
        WHERE id = config_record.id;
        
        RETURN so_number;
    END IF;
    
    -- Fallback to original hardcoded logic
    SELECT name INTO company_name FROM public.companies WHERE id = comp_id;
    first_four_letters := UPPER(SUBSTRING(REGEXP_REPLACE(company_name, '[^A-Za-z]', '', 'g') FROM 1 FOR 4));
    
    WHILE LENGTH(first_four_letters) < 4 LOOP
        first_four_letters := first_four_letters || 'X';
    END LOOP;
    
    SELECT COALESCE(MAX(
        CASE 
            WHEN so.order_number LIKE first_four_letters || 'SO%' AND 
                 SUBSTRING(so.order_number FROM LENGTH(first_four_letters || 'SO') + 1) ~ '^[0-9]+$' THEN
                CAST(SUBSTRING(so.order_number FROM LENGTH(first_four_letters || 'SO') + 1) AS INTEGER)
            ELSE 1000
        END
    ), 1000) + 1
    INTO counter
    FROM public.sales_orders so
    WHERE so.company_id = comp_id;
    
    IF counter < 1001 THEN
        counter := 1001;
    END IF;
    
    so_number := first_four_letters || 'SO' || counter::TEXT;
    RETURN so_number;
END;
$function$;

-- 2. Fix generate_transfer_number function
CREATE OR REPLACE FUNCTION public.generate_transfer_number(comp_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    config_record RECORD;
    company_name TEXT;
    first_four_letters TEXT;
    counter INTEGER;
    transfer_number TEXT;
BEGIN
    -- Check for active document format configuration for transfers
    SELECT * INTO config_record
    FROM public.document_format_configs 
    WHERE company_id = comp_id 
      AND document_type = 'transfer' 
      AND is_active = true
    LIMIT 1;
    
    -- If configuration exists, use it (prefix + counter only, no suffix)
    IF FOUND THEN
        transfer_number := config_record.prefix || config_record.current_counter;
        
        -- Increment the counter
        UPDATE public.document_format_configs 
        SET current_counter = current_counter + 1,
            updated_at = now()
        WHERE id = config_record.id;
        
        RETURN transfer_number;
    END IF;
    
    -- Fallback to original hardcoded logic
    SELECT name INTO company_name FROM public.companies WHERE id = comp_id;
    first_four_letters := UPPER(SUBSTRING(REGEXP_REPLACE(company_name, '[^A-Za-z]', '', 'g') FROM 1 FOR 4));
    
    WHILE LENGTH(first_four_letters) < 4 LOOP
        first_four_letters := first_four_letters || 'X';
    END LOOP;
    
    SELECT COALESCE(MAX(
        CASE 
            WHEN it.transfer_number LIKE 'TRF-' || first_four_letters || '-%' AND 
                 SUBSTRING(it.transfer_number FROM LENGTH('TRF-' || first_four_letters || '-') + 1) ~ '^[0-9]+$' THEN
                CAST(SUBSTRING(it.transfer_number FROM LENGTH('TRF-' || first_four_letters || '-') + 1) AS INTEGER)
            ELSE 1000
        END
    ), 1000) + 1
    INTO counter
    FROM public.inventory_transfers it
    WHERE it.company_id = comp_id;
    
    IF counter < 1001 THEN
        counter := 1001;
    END IF;
    
    transfer_number := 'TRF-' || first_four_letters || '-' || LPAD(counter::TEXT, 4, '0');
    RETURN transfer_number;
END;
$function$;

-- 3. Fix generate_rso_number function
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
      AND document_type = 'rso' 
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

-- 4. Fix generate_performa_invoice_number function
CREATE OR REPLACE FUNCTION public.generate_performa_invoice_number()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    config_record RECORD;
    comp_id UUID;
    performa_number TEXT;
BEGIN
    SELECT user_company_id() INTO comp_id;
    
    -- Check for active document format configuration
    SELECT * INTO config_record
    FROM public.document_format_configs 
    WHERE company_id = comp_id 
      AND document_type = 'performa_invoice' 
      AND is_active = true
    LIMIT 1;
    
    -- If configuration exists, use it (prefix + counter only, no suffix)
    IF FOUND THEN
        performa_number := config_record.prefix || config_record.current_counter;
        
        -- Increment the counter
        UPDATE public.document_format_configs 
        SET current_counter = current_counter + 1,
            updated_at = now()
        WHERE id = config_record.id;
        
        RETURN performa_number;
    END IF;
    
    -- Fallback to using generate_company_invoice_number
    RETURN generate_company_invoice_number(comp_id);
END;
$function$;

-- 5. Fix generate_po_number function
CREATE OR REPLACE FUNCTION public.generate_po_number(comp_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    config_record RECORD;
    company_name TEXT;
    first_four_letters TEXT;
    counter INTEGER;
    po_number TEXT;
BEGIN
    -- Check for active document format configuration for purchase orders
    SELECT * INTO config_record
    FROM public.document_format_configs 
    WHERE company_id = comp_id 
      AND document_type = 'purchase_order' 
      AND is_active = true
    LIMIT 1;
    
    -- If configuration exists, use it (prefix + counter only, no suffix)
    IF FOUND THEN
        po_number := config_record.prefix || config_record.current_counter;
        
        -- Increment the counter
        UPDATE public.document_format_configs 
        SET current_counter = current_counter + 1,
            updated_at = now()
        WHERE id = config_record.id;
        
        RETURN po_number;
    END IF;
    
    -- Fallback to original hardcoded logic
    SELECT name INTO company_name FROM public.companies WHERE id = comp_id;
    first_four_letters := UPPER(SUBSTRING(REGEXP_REPLACE(company_name, '[^A-Za-z]', '', 'g') FROM 1 FOR 4));
    
    WHILE LENGTH(first_four_letters) < 4 LOOP
        first_four_letters := first_four_letters || 'X';
    END LOOP;
    
    SELECT COALESCE(MAX(
        CASE 
            WHEN po.po_number LIKE 'PO-' || first_four_letters || '-%' AND 
                 SUBSTRING(po.po_number FROM LENGTH('PO-' || first_four_letters || '-') + 1) ~ '^[0-9]+$' THEN
                CAST(SUBSTRING(po.po_number FROM LENGTH('PO-' || first_four_letters || '-') + 1) AS INTEGER)
            ELSE 1000
        END
    ), 1000) + 1
    INTO counter
    FROM public.purchase_orders po
    WHERE po.company_id = comp_id;
    
    IF counter < 1001 THEN
        counter := 1001;
    END IF;
    
    po_number := 'PO-' || first_four_letters || '-' || LPAD(counter::TEXT, 4, '0');
    RETURN po_number;
END;
$function$;