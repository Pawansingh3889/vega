-- Remove 'draft' status option from sales_invoices table
-- Update default status to 'finalized'

-- First, update any existing 'draft' invoices to 'finalized'
UPDATE sales_invoices 
SET status = 'finalized' 
WHERE status = 'draft';

-- Drop the existing check constraint if it exists
ALTER TABLE sales_invoices 
DROP CONSTRAINT IF EXISTS sales_invoices_status_check;

-- Add new check constraint that only allows 'finalized' status
ALTER TABLE sales_invoices 
ADD CONSTRAINT sales_invoices_status_check 
CHECK (status IN ('finalized'));

-- Update the default value for status column
ALTER TABLE sales_invoices 
ALTER COLUMN status SET DEFAULT 'finalized';