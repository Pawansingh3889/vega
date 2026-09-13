-- Now implement document format integration with backward compatibility
-- Update generation functions to check for configurations first, then fall back to hardcoded logic

-- First, update the generate_po_number function to support document format configs
CREATE OR REPLACE FUNCTION public.generate_po_number(comp_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    config_record RECORD;
    company_name TEXT;
    first_four_letters TEXT;
    counter INTEGER;
    po_number TEXT;
BEGIN
    -- Check if there's an active document format configuration for purchase_order
    SELECT * INTO config_record
    FROM public.document_format_configs 
    WHERE company_id = comp_id 
    AND document_type = 'purchase_order' 
    AND is_active = true
    LIMIT 1;
    
    IF FOUND THEN
        -- Use configured format
        po_number := config_record.prefix || config_record.current_counter || config_record.suffix;
        
        -- Increment counter for next use
        UPDATE public.document_format_configs 
        SET current_counter = current_counter + 1,
            updated_at = now()
        WHERE id = config_record.id;
        
        RETURN po_number;
    ELSE
        -- Fall back to original hardcoded logic
        SELECT name INTO company_name FROM companies WHERE id = comp_id;
        
        first_four_letters := UPPER(SUBSTRING(REGEXP_REPLACE(company_name, '[^A-Za-z]', '', 'g') FROM 1 FOR 4));
        
        WHILE LENGTH(first_four_letters) < 4 LOOP
            first_four_letters := first_four_letters || 'X';
        END LOOP;
        
        SELECT COALESCE(MAX(CAST(SUBSTRING(po.po_number FROM LENGTH('PO-' || first_four_letters) + 1) AS INTEGER)), 0) + 1
        INTO counter
        FROM purchase_orders po
        WHERE po.company_id = comp_id 
        AND po.po_number LIKE 'PO-' || first_four_letters || '%';
        
        po_number := 'PO-' || first_four_letters || LPAD(counter::TEXT, 3, '0');
        
        RETURN po_number;
    END IF;
END;
$$;

-- Update the generate_invoice_number function
CREATE OR REPLACE FUNCTION public.generate_invoice_number(comp_id uuid)
RETURNS text
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    config_record RECORD;
    company_name TEXT;
    first_four_letters TEXT;
    counter INTEGER;
    invoice_number TEXT;
BEGIN
    -- Check if there's an active document format configuration for sales_invoice
    SELECT * INTO config_record
    FROM public.document_format_configs 
    WHERE company_id = comp_id 
    AND document_type = 'sales_invoice' 
    AND is_active = true
    LIMIT 1;
    
    IF FOUND THEN
        -- Use configured format
        invoice_number := config_record.prefix || config_record.current_counter || config_record.suffix;
        
        -- Increment counter for next use
        UPDATE public.document_format_configs 
        SET current_counter = current_counter + 1,
            updated_at = now()
        WHERE id = config_record.id;
        
        RETURN invoice_number;
    ELSE
        -- Fall back to original hardcoded logic
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
$$;

-- Update the generate_so_number function  
CREATE OR REPLACE FUNCTION public.generate_so_number(comp_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    config_record RECORD;
    company_name TEXT;
    first_four_letters TEXT;
    counter INTEGER;
    so_number TEXT;
BEGIN
    -- Check if there's an active document format configuration for sales_order
    SELECT * INTO config_record
    FROM public.document_format_configs 
    WHERE company_id = comp_id 
    AND document_type = 'sales_order' 
    AND is_active = true
    LIMIT 1;
    
    IF FOUND THEN
        -- Use configured format
        so_number := config_record.prefix || config_record.current_counter || config_record.suffix;
        
        -- Increment counter for next use
        UPDATE public.document_format_configs 
        SET current_counter = current_counter + 1,
            updated_at = now()
        WHERE id = config_record.id;
        
        RETURN so_number;
    ELSE
        -- Fall back to original hardcoded logic
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
    END IF;
END;
$$;