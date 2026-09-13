-- Add comprehensive RLS policies for child tables

-- BOM Components policies (child of bom_headers)
CREATE POLICY "Company isolation for bom_components - all operations"
ON public.bom_components
FOR ALL
USING (
  bom_id IN (
    SELECT id FROM public.bom_headers 
    WHERE company_id = user_company_id()
  )
)
WITH CHECK (
  bom_id IN (
    SELECT id FROM public.bom_headers 
    WHERE company_id = user_company_id()
  )
);

-- Performa Invoice Items policies (child of performa_invoices)
CREATE POLICY "Performa invoice items access - all operations"
ON public.performa_invoice_items
FOR ALL
USING (
  performa_invoice_id IN (
    SELECT id FROM public.performa_invoices 
    WHERE company_id = user_company_id()
  )
)
WITH CHECK (
  performa_invoice_id IN (
    SELECT id FROM public.performa_invoices 
    WHERE company_id = user_company_id()
  )
);

COMMENT ON POLICY "Company isolation for bom_components - all operations" ON public.bom_components IS 
'Ensures users can only access BOM components for their company by checking parent bom_headers table';

COMMENT ON POLICY "Performa invoice items access - all operations" ON public.performa_invoice_items IS 
'Ensures users can only access performa invoice items for their company by checking parent performa_invoices table';