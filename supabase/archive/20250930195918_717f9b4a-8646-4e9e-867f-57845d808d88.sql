-- Add warehouse and bin fields to debit_notes table
ALTER TABLE public.debit_notes 
ADD COLUMN IF NOT EXISTS default_warehouse_id UUID,
ADD COLUMN IF NOT EXISTS default_bin_id UUID;

-- Add foreign key constraint for bin (warehouse_bins table exists)
ALTER TABLE public.debit_notes 
ADD CONSTRAINT fk_debit_notes_bin 
FOREIGN KEY (default_bin_id) REFERENCES public.warehouse_bins(id) ON DELETE SET NULL;