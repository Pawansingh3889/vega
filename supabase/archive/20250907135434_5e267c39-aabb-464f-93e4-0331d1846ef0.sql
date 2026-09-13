-- Create debit_notes table (company issues debit notes to suppliers)
CREATE TABLE public.debit_notes (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id UUID NOT NULL,
    supplier_id UUID NOT NULL,
    purchase_order_id UUID,
    grn_id UUID,
    debit_note_number TEXT,
    debit_note_date DATE NOT NULL DEFAULT CURRENT_DATE,
    supplier_name TEXT NOT NULL,
    reason TEXT NOT NULL,
    subtotal_amount NUMERIC NOT NULL DEFAULT 0,
    discount_amount NUMERIC NOT NULL DEFAULT 0,
    tax_amount NUMERIC NOT NULL DEFAULT 0,
    total_amount NUMERIC NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'draft',
    notes TEXT,
    created_by UUID NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create debit_note_items table
CREATE TABLE public.debit_note_items (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    debit_note_id UUID NOT NULL,
    product_id UUID NOT NULL,
    product_name TEXT NOT NULL,
    product_sku TEXT NOT NULL,
    quantity INTEGER NOT NULL,
    unit_price NUMERIC NOT NULL DEFAULT 0,
    discount_percentage NUMERIC DEFAULT 0,
    discount_amount NUMERIC NOT NULL DEFAULT 0,
    cgst_rate NUMERIC DEFAULT 0,
    cgst_amount NUMERIC DEFAULT 0,
    sgst_rate NUMERIC DEFAULT 0,
    sgst_amount NUMERIC DEFAULT 0,
    igst_rate NUMERIC DEFAULT 0,
    igst_amount NUMERIC DEFAULT 0,
    tax_amount NUMERIC NOT NULL DEFAULT 0,
    line_subtotal NUMERIC NOT NULL DEFAULT 0,
    line_total NUMERIC NOT NULL DEFAULT 0,
    unit_of_measure TEXT NOT NULL DEFAULT 'pcs',
    hsn_sac_code TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create supplier_credit_notes table (credit notes received from suppliers)
CREATE TABLE public.supplier_credit_notes (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id UUID NOT NULL,
    supplier_id UUID NOT NULL,
    purchase_order_id UUID,
    supplier_credit_note_number TEXT NOT NULL,
    supplier_credit_note_date DATE NOT NULL DEFAULT CURRENT_DATE,
    supplier_name TEXT NOT NULL,
    reason TEXT NOT NULL,
    subtotal_amount NUMERIC NOT NULL DEFAULT 0,
    discount_amount NUMERIC NOT NULL DEFAULT 0,
    tax_amount NUMERIC NOT NULL DEFAULT 0,
    total_amount NUMERIC NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'received',
    notes TEXT,
    created_by UUID NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create supplier_credit_note_items table
CREATE TABLE public.supplier_credit_note_items (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    supplier_credit_note_id UUID NOT NULL,
    product_id UUID NOT NULL,
    product_name TEXT NOT NULL,
    product_sku TEXT NOT NULL,
    quantity INTEGER NOT NULL,
    unit_price NUMERIC NOT NULL DEFAULT 0,
    discount_percentage NUMERIC DEFAULT 0,
    discount_amount NUMERIC NOT NULL DEFAULT 0,
    cgst_rate NUMERIC DEFAULT 0,
    cgst_amount NUMERIC DEFAULT 0,
    sgst_rate NUMERIC DEFAULT 0,
    sgst_amount NUMERIC DEFAULT 0,
    igst_rate NUMERIC DEFAULT 0,
    igst_amount NUMERIC DEFAULT 0,
    tax_amount NUMERIC NOT NULL DEFAULT 0,
    line_subtotal NUMERIC NOT NULL DEFAULT 0,
    line_total NUMERIC NOT NULL DEFAULT 0,
    unit_of_measure TEXT NOT NULL DEFAULT 'pcs',
    hsn_sac_code TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.debit_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.debit_note_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_credit_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_credit_note_items ENABLE ROW LEVEL SECURITY;

-- Create RLS policies for debit_notes
CREATE POLICY "Company isolation for debit_notes"
ON public.debit_notes
FOR ALL
USING (company_id = user_company_id());

-- Create RLS policies for debit_note_items
CREATE POLICY "Debit note items access"
ON public.debit_note_items
FOR ALL
USING (debit_note_id IN (
    SELECT id FROM public.debit_notes WHERE company_id = user_company_id()
));

-- Create RLS policies for supplier_credit_notes
CREATE POLICY "Company isolation for supplier_credit_notes"
ON public.supplier_credit_notes
FOR ALL
USING (company_id = user_company_id());

-- Create RLS policies for supplier_credit_note_items
CREATE POLICY "Supplier credit note items access"
ON public.supplier_credit_note_items
FOR ALL
USING (supplier_credit_note_id IN (
    SELECT id FROM public.supplier_credit_notes WHERE company_id = user_company_id()
));

-- Create auto-generation functions for debit notes
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

-- Create trigger for auto-generating debit note numbers
CREATE OR REPLACE FUNCTION public.auto_generate_debit_note_number()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
    IF NEW.debit_note_number IS NULL OR NEW.debit_note_number = '' THEN
        NEW.debit_note_number := public.generate_debit_note_number(NEW.company_id);
    END IF;
    RETURN NEW;
END;
$function$;

CREATE TRIGGER auto_generate_debit_note_number_trigger
    BEFORE INSERT ON public.debit_notes
    FOR EACH ROW
    EXECUTE FUNCTION public.auto_generate_debit_note_number();

-- Add updated_at trigger for debit_notes
CREATE TRIGGER update_debit_notes_updated_at
    BEFORE UPDATE ON public.debit_notes
    FOR EACH ROW
    EXECUTE FUNCTION public.set_current_timestamp_updated_at();

-- Add updated_at trigger for supplier_credit_notes
CREATE TRIGGER update_supplier_credit_notes_updated_at
    BEFORE UPDATE ON public.supplier_credit_notes
    FOR EACH ROW
    EXECUTE FUNCTION public.set_current_timestamp_updated_at();