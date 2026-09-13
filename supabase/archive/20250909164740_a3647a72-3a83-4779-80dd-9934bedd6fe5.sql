-- Update existing GRN records with 'accepted' status to 'received'
UPDATE grn_header 
SET status = 'received', updated_at = now()
WHERE status = 'accepted';

-- Update any other references that might exist
-- Check if there are any enum constraints or other tables that reference this status
-- This ensures consistency across the database