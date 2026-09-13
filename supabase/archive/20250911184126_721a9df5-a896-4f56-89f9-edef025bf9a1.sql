-- Add delivery address fields to sales_orders table
ALTER TABLE public.sales_orders ADD COLUMN IF NOT EXISTS same_as_registered_address boolean DEFAULT false;
ALTER TABLE public.sales_orders ADD COLUMN IF NOT EXISTS delivery_address_line1 text;
ALTER TABLE public.sales_orders ADD COLUMN IF NOT EXISTS delivery_address_line2 text;
ALTER TABLE public.sales_orders ADD COLUMN IF NOT EXISTS delivery_city text;
ALTER TABLE public.sales_orders ADD COLUMN IF NOT EXISTS delivery_state text;
ALTER TABLE public.sales_orders ADD COLUMN IF NOT EXISTS delivery_country text;
ALTER TABLE public.sales_orders ADD COLUMN IF NOT EXISTS delivery_postal_code text;