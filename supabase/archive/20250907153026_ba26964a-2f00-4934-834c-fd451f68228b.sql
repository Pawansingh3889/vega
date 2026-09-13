-- Add debit_note_id relationship to supplier_credit_notes table
ALTER TABLE public.supplier_credit_notes 
ADD COLUMN debit_note_id uuid REFERENCES public.debit_notes(id);

-- Add index for better performance
CREATE INDEX idx_supplier_credit_notes_debit_note_id ON public.supplier_credit_notes(debit_note_id);

-- Update RLS policies to include debit note relationship
DROP POLICY IF EXISTS "Company isolation for supplier_credit_notes" ON public.supplier_credit_notes;

CREATE POLICY "Company isolation for supplier_credit_notes" 
ON public.supplier_credit_notes 
FOR ALL 
USING (
  company_id = user_company_id() OR 
  debit_note_id IN (
    SELECT id FROM public.debit_notes 
    WHERE company_id = user_company_id()
  )
);