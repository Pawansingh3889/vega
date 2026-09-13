-- Add support for multiple invoices in RSO
-- Add new array columns for multiple invoice support
ALTER TABLE return_order_header 
ADD COLUMN IF NOT EXISTS invoice_ids uuid[],
ADD COLUMN IF NOT EXISTS invoice_numbers text[];

-- Migrate existing single invoice data to array format
UPDATE return_order_header 
SET invoice_ids = ARRAY[invoice_id]::uuid[],
    invoice_numbers = ARRAY[invoice_number]::text[]
WHERE invoice_id IS NOT NULL 
  AND (invoice_ids IS NULL OR array_length(invoice_ids, 1) IS NULL);

-- Add source_invoice_id to return_order_lines to track which invoice each line came from
ALTER TABLE return_order_lines
ADD COLUMN IF NOT EXISTS source_invoice_id uuid;