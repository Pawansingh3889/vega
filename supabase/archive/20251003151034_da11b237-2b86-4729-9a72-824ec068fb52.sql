-- Create business_registration_requests table
CREATE TABLE IF NOT EXISTS business_registration_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- Business Details
  business_name TEXT NOT NULL,
  business_type TEXT,
  industry TEXT,
  email TEXT NOT NULL,
  phone TEXT NOT NULL,
  gstin TEXT,
  address_line1 TEXT,
  address_line2 TEXT,
  city TEXT,
  state TEXT,
  country TEXT,
  postal_code TEXT,
  
  -- Admin User Details (encrypted in JSONB for security)
  admin_details JSONB NOT NULL, -- Contains: username, email, full_name, designation, password_hash
  
  -- Payment Details
  payment_transaction_id UUID REFERENCES payment_transactions(id),
  selected_plan TEXT CHECK (selected_plan IN ('trial', 'monthly', 'yearly')),
  
  -- Approval Status
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  reviewed_by UUID REFERENCES auth.users(id),
  reviewed_at TIMESTAMP WITH TIME ZONE,
  rejection_reason TEXT,
  admin_notes TEXT,
  
  -- Created Company Reference (after approval)
  created_company_id UUID REFERENCES companies(id),
  business_ref_no TEXT, -- Generated upon approval
  
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Add foreign key from payment_transactions to business_registration_requests
ALTER TABLE payment_transactions 
ADD CONSTRAINT fk_payment_transaction_registration 
FOREIGN KEY (business_registration_request_id) 
REFERENCES business_registration_requests(id) 
ON DELETE SET NULL;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_registration_requests_status ON business_registration_requests(status);
CREATE INDEX IF NOT EXISTS idx_registration_requests_email ON business_registration_requests(email);
CREATE INDEX IF NOT EXISTS idx_registration_requests_payment ON business_registration_requests(payment_transaction_id);