-- Add place_of_supply field to return_order_header table
ALTER TABLE return_order_header 
ADD COLUMN IF NOT EXISTS place_of_supply text;