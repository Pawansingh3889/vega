-- Update the check constraint on document_format_configs to include sales_order
ALTER TABLE public.document_format_configs 
DROP CONSTRAINT IF EXISTS document_format_configs_document_type_check;

ALTER TABLE public.document_format_configs 
ADD CONSTRAINT document_format_configs_document_type_check 
CHECK (document_type IN (
  'purchase_order',
  'sales_order', 
  'invoice',
  'debit_note',
  'credit_note',
  'customer_id',
  'supplier_id',
  'grn',
  'return_sales_order'
));