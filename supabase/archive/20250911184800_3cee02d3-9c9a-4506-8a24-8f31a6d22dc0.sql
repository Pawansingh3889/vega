-- Add place_of_supply field to sales_orders table
ALTER TABLE public.sales_orders ADD COLUMN IF NOT EXISTS place_of_supply text;