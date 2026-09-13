-- Add comprehensive tracking fields to sales_orders table
ALTER TABLE public.sales_orders ADD COLUMN IF NOT EXISTS destination text;
ALTER TABLE public.sales_orders ADD COLUMN IF NOT EXISTS item_count integer DEFAULT 0;
ALTER TABLE public.sales_orders ADD COLUMN IF NOT EXISTS eway_bill_no text;
ALTER TABLE public.sales_orders ADD COLUMN IF NOT EXISTS eway_bill_date date;
ALTER TABLE public.sales_orders ADD COLUMN IF NOT EXISTS carrier_transporter text;
ALTER TABLE public.sales_orders ADD COLUMN IF NOT EXISTS awb_no text;
ALTER TABLE public.sales_orders ADD COLUMN IF NOT EXISTS eta date;
ALTER TABLE public.sales_orders ADD COLUMN IF NOT EXISTS pod_document_url text;
ALTER TABLE public.sales_orders ADD COLUMN IF NOT EXISTS tracking_status text DEFAULT 'pending';
ALTER TABLE public.sales_orders ADD COLUMN IF NOT EXISTS dispatch_date date;
ALTER TABLE public.sales_orders ADD COLUMN IF NOT EXISTS delivery_date date;

-- Add comprehensive tracking fields to debit_notes table
ALTER TABLE public.debit_notes ADD COLUMN IF NOT EXISTS destination text;
ALTER TABLE public.debit_notes ADD COLUMN IF NOT EXISTS item_count integer DEFAULT 0;
ALTER TABLE public.debit_notes ADD COLUMN IF NOT EXISTS eway_bill_no text;
ALTER TABLE public.debit_notes ADD COLUMN IF NOT EXISTS eway_bill_date date;
ALTER TABLE public.debit_notes ADD COLUMN IF NOT EXISTS carrier_transporter text;
ALTER TABLE public.debit_notes ADD COLUMN IF NOT EXISTS awb_no text;
ALTER TABLE public.debit_notes ADD COLUMN IF NOT EXISTS eta date;
ALTER TABLE public.debit_notes ADD COLUMN IF NOT EXISTS pod_document_url text;
ALTER TABLE public.debit_notes ADD COLUMN IF NOT EXISTS tracking_status text DEFAULT 'pending';
ALTER TABLE public.debit_notes ADD COLUMN IF NOT EXISTS dispatch_date date;
ALTER TABLE public.debit_notes ADD COLUMN IF NOT EXISTS delivery_date date;