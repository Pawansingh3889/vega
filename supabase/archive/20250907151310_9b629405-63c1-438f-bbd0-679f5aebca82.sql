-- Add received_quantity and pending_quantity columns to debit_note_items table
ALTER TABLE public.debit_note_items 
ADD COLUMN received_quantity integer NOT NULL DEFAULT 0,
ADD COLUMN pending_quantity integer NOT NULL DEFAULT 0;