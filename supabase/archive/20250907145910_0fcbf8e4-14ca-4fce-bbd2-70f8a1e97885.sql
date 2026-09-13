-- Create function to generate debit note number based on supplier name
CREATE OR REPLACE FUNCTION public.generate_debit_note_number_by_supplier(p_supplier_id uuid, p_company_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    supplier_name TEXT;
    first_four_letters TEXT;
    counter INTEGER;
    debit_note_number TEXT;
BEGIN
    -- Get supplier name
    SELECT name INTO supplier_name FROM public.suppliers WHERE id = p_supplier_id;
    
    -- Extract first 4 letters from supplier name
    first_four_letters := UPPER(SUBSTRING(REGEXP_REPLACE(supplier_name, '[^A-Za-z]', '', 'g') FROM 1 FOR 4));
    
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
    WHERE dn.company_id = p_company_id AND dn.supplier_id = p_supplier_id;
    
    -- Ensure counter starts from 1001 minimum
    IF counter < 1001 THEN
        counter := 1001;
    END IF;
    
    -- Generate debit note number: First4LettersDN + Counter starting from 1001
    debit_note_number := first_four_letters || 'DN' || counter::TEXT;
    
    RETURN debit_note_number;
END;
$function$;

-- Update the auto-generation trigger to use supplier-based numbering
CREATE OR REPLACE FUNCTION public.auto_generate_debit_note_number_by_supplier()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NEW.debit_note_number IS NULL OR NEW.debit_note_number = '' THEN
        NEW.debit_note_number := public.generate_debit_note_number_by_supplier(NEW.supplier_id, NEW.company_id);
    END IF;
    RETURN NEW;
END;
$function$;

-- Drop the old trigger and create the new one
DROP TRIGGER IF EXISTS trigger_auto_generate_debit_note_number ON public.debit_notes;
CREATE TRIGGER trigger_auto_generate_debit_note_number_by_supplier
    BEFORE INSERT ON public.debit_notes
    FOR EACH ROW EXECUTE FUNCTION public.auto_generate_debit_note_number_by_supplier();