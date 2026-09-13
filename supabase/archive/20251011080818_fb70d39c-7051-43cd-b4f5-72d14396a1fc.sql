-- Add optional product lifecycle fields to products table
ALTER TABLE public.products 
  ADD COLUMN mfg_date DATE,
  ADD COLUMN expiry_date DATE,
  ADD COLUMN shelf_life_days INTEGER;

-- Add documentation comments
COMMENT ON COLUMN public.products.mfg_date IS 'Manufacturing date of the product (optional)';
COMMENT ON COLUMN public.products.expiry_date IS 'Expiry date of the product (optional)';
COMMENT ON COLUMN public.products.shelf_life_days IS 'Shelf life in days (optional)';