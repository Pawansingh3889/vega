-- Add the missing updated_at column to sales_order_items table
ALTER TABLE public.sales_order_items 
ADD COLUMN IF NOT EXISTS updated_at timestamp with time zone DEFAULT now();

-- Backfill existing records with created_at value
UPDATE public.sales_order_items 
SET updated_at = created_at 
WHERE updated_at IS NULL;