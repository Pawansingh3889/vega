-- Add credit note quantity tracking fields to supplier_credit_note_items
ALTER TABLE public.supplier_credit_note_items 
ADD COLUMN credit_note_quantity integer NOT NULL DEFAULT 0,
ADD COLUMN pending_quantity integer NOT NULL DEFAULT 0;

-- Add check constraints for data integrity
ALTER TABLE public.supplier_credit_note_items 
ADD CONSTRAINT chk_credit_note_quantity_positive 
CHECK (credit_note_quantity >= 0);

ALTER TABLE public.supplier_credit_note_items 
ADD CONSTRAINT chk_credit_note_quantity_valid 
CHECK (credit_note_quantity <= quantity);

ALTER TABLE public.supplier_credit_note_items 
ADD CONSTRAINT chk_pending_quantity_valid 
CHECK (pending_quantity = (quantity - credit_note_quantity));