-- Enable RLS on payment_transactions table
ALTER TABLE payment_transactions ENABLE ROW LEVEL SECURITY;

-- Enable RLS on business_registration_requests table
ALTER TABLE business_registration_requests ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist (to avoid conflicts)
DROP POLICY IF EXISTS "Super admin can view all payments" ON payment_transactions;
DROP POLICY IF EXISTS "Super admin can manage payments" ON payment_transactions;
DROP POLICY IF EXISTS "Company can view own payments" ON payment_transactions;
DROP POLICY IF EXISTS "Super admin can view all requests" ON business_registration_requests;
DROP POLICY IF EXISTS "Super admin can update requests" ON business_registration_requests;
DROP POLICY IF EXISTS "Super admin can insert requests" ON business_registration_requests;
DROP POLICY IF EXISTS "Super admin can delete requests" ON business_registration_requests;

-- RLS Policies for payment_transactions
CREATE POLICY "Super admin can view all payments"
  ON payment_transactions FOR SELECT
  USING (public.is_super_admin());

CREATE POLICY "Super admin can manage payments"
  ON payment_transactions FOR ALL
  USING (public.is_super_admin());

CREATE POLICY "Company can view own payments"
  ON payment_transactions FOR SELECT
  USING (company_id IN (
    SELECT id FROM companies WHERE id = user_company_id()
  ));

-- RLS Policies for business_registration_requests
CREATE POLICY "Super admin can view all requests"
  ON business_registration_requests FOR SELECT
  USING (public.is_super_admin());

CREATE POLICY "Super admin can update requests"
  ON business_registration_requests FOR UPDATE
  USING (public.is_super_admin());

CREATE POLICY "Super admin can insert requests"
  ON business_registration_requests FOR INSERT
  WITH CHECK (public.is_super_admin());

CREATE POLICY "Super admin can delete requests"
  ON business_registration_requests FOR DELETE
  USING (public.is_super_admin());