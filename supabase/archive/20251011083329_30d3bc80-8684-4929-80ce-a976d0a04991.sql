-- Add bank detail columns to companies table
ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS bank_name TEXT,
  ADD COLUMN IF NOT EXISTS branch_name TEXT,
  ADD COLUMN IF NOT EXISTS account_number TEXT,
  ADD COLUMN IF NOT EXISTS account_type TEXT,
  ADD COLUMN IF NOT EXISTS ifsc_code TEXT,
  ADD COLUMN IF NOT EXISTS swift_code TEXT,
  ADD COLUMN IF NOT EXISTS account_holder_name TEXT,
  ADD COLUMN IF NOT EXISTS upi_id TEXT;

-- Add comments for documentation
COMMENT ON COLUMN public.companies.bank_name IS 'Name of the bank where company account is held';
COMMENT ON COLUMN public.companies.branch_name IS 'Branch name of the bank';
COMMENT ON COLUMN public.companies.account_number IS 'Bank account number (sensitive data)';
COMMENT ON COLUMN public.companies.account_type IS 'Type of account: Savings, Current, Other';
COMMENT ON COLUMN public.companies.ifsc_code IS 'Indian Financial System Code';
COMMENT ON COLUMN public.companies.swift_code IS 'SWIFT/BIC code for international transfers (optional)';
COMMENT ON COLUMN public.companies.account_holder_name IS 'Name of the account holder';
COMMENT ON COLUMN public.companies.upi_id IS 'Unified Payments Interface ID (optional)';