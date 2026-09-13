-- Update debit_notes table to link with supplier invoices from GRN
ALTER TABLE public.debit_notes 
ADD COLUMN supplier_invoice_number text,
ADD COLUMN supplier_invoice_date date,
ALTER COLUMN purchase_order_id DROP NOT NULL;

-- Update the auto-generate trigger to use supplier invoice info when available
CREATE OR REPLACE FUNCTION public.generate_debit_note_number(comp_id uuid)
RETURNS text
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    company_name TEXT;
    first_four_letters TEXT;
    counter INTEGER;
    debit_note_number TEXT;
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
    debit_note_number := first_four_letters || 'DN' || counter::TEXT;
    
    RETURN debit_note_number;
END;
$function$;