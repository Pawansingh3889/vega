-- Add delivery_place_of_supply field to purchase_orders table
ALTER TABLE public.purchase_orders 
ADD COLUMN delivery_place_of_supply TEXT;