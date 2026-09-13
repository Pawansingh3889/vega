-- Enable RLS on new tables
ALTER TABLE business_registration_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_transactions ENABLE ROW LEVEL SECURITY;

-- RLS Policies for business_registration_requests
CREATE POLICY "Super admin can view all registration requests"
  ON business_registration_requests FOR SELECT
  USING (public.is_super_admin());

CREATE POLICY "Super admin can update registration requests"
  ON business_registration_requests FOR UPDATE
  USING (public.is_super_admin());

CREATE POLICY "Super admin can insert registration requests"
  ON business_registration_requests FOR INSERT
  WITH CHECK (public.is_super_admin());

CREATE POLICY "Super admin can delete registration requests"
  ON business_registration_requests FOR DELETE
  USING (public.is_super_admin());

-- RLS Policies for payment_transactions
CREATE POLICY "Super admin can view all payments"
  ON payment_transactions FOR SELECT
  USING (public.is_super_admin());

CREATE POLICY "Super admin can manage payments"
  ON payment_transactions FOR ALL
  USING (public.is_super_admin())
  WITH CHECK (public.is_super_admin());

-- Allow companies to view their own payment transactions
CREATE POLICY "Companies can view own payments"
  ON payment_transactions FOR SELECT
  USING (
    company_id IS NOT NULL AND 
    company_id IN (
      SELECT company_id FROM profiles WHERE user_id = auth.uid()
    )
  );