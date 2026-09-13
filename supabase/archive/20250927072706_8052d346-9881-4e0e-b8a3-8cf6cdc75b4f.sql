-- Add warehouse and bin fields to purchase_orders table
ALTER TABLE public.purchase_orders 
ADD COLUMN warehouse_id uuid,
ADD COLUMN bin_id uuid;

-- Add foreign key constraints to warehouse_bins table (assuming warehouse and bin info is in warehouse_bins)
ALTER TABLE public.purchase_orders 
ADD CONSTRAINT fk_purchase_orders_warehouse_id 
FOREIGN KEY (warehouse_id) REFERENCES public.warehouse_bins(id);

ALTER TABLE public.purchase_orders 
ADD CONSTRAINT fk_purchase_orders_bin_id 
FOREIGN KEY (bin_id) REFERENCES public.warehouse_bins(id);

-- Add comments for clarity
COMMENT ON COLUMN public.purchase_orders.warehouse_id IS 'Default warehouse for this purchase order';
COMMENT ON COLUMN public.purchase_orders.bin_id IS 'Default bin for this purchase order';