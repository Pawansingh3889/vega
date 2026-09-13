-- ============================================================================
-- COMPREHENSIVE SECURITY HARDENING - CORE ISSUES ONLY
-- ============================================================================

-- ====================
-- 1. SAFE VIEWS FOR CUSTOMER/SUPPLIER DATA
-- ====================

DROP VIEW IF EXISTS public.customers_safe CASCADE;
CREATE VIEW public.customers_safe WITH (security_invoker = true) AS
SELECT 
  id, company_id, name, customer_ref, customer_type, is_active,
  city, state, country, pin_code, gstin, pan_number, gst_tax_location,
  credit_limit, credit_limit_days, payment_terms, preferred_currency,
  created_at, updated_at
FROM public.customers;
GRANT SELECT ON public.customers_safe TO authenticated;
COMMENT ON VIEW public.customers_safe IS 'Safe view excluding email, phone, addresses, bank details.';

DROP VIEW IF EXISTS public.suppliers_safe CASCADE;
CREATE VIEW public.suppliers_safe WITH (security_invoker = true) AS
SELECT 
  id, company_id, name, supplier_ref, supplier_type, is_active,
  city, state, country, pin_code, gst_number, pan_number, place_of_supply,
  credit_time, payment_terms, preferred_currency, created_at, updated_at
FROM public.suppliers;
GRANT SELECT ON public.suppliers_safe TO authenticated;
COMMENT ON VIEW public.suppliers_safe IS 'Safe view excluding email, phone, bank details, tax IDs.';

-- ====================
-- 2. AUDIT LOG RESTRICTIONS
-- ====================

DROP POLICY IF EXISTS "Admins can view audit logs" ON public.security_audit_log;
DROP POLICY IF EXISTS "System can insert audit logs" ON public.security_audit_log;
DROP POLICY IF EXISTS "Only admins can view security audit logs" ON public.security_audit_log;
DROP POLICY IF EXISTS "System can insert security audit logs" ON public.security_audit_log;

CREATE POLICY "Only admins can view security audit logs"
ON public.security_audit_log FOR SELECT TO authenticated
USING (is_user_admin_v2(auth.uid()) OR is_super_admin() OR user_id = auth.uid());

CREATE POLICY "System can insert security audit logs"
ON public.security_audit_log FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "Admins can view audit logs" ON public.transaction_audit_log;
DROP POLICY IF EXISTS "System can insert audit logs" ON public.transaction_audit_log;
DROP POLICY IF EXISTS "Only admins can view transaction audit logs" ON public.transaction_audit_log;
DROP POLICY IF EXISTS "System can insert transaction audit logs" ON public.transaction_audit_log;

CREATE POLICY "Only admins can view transaction audit logs"
ON public.transaction_audit_log FOR SELECT TO authenticated
USING ((company_id = user_company_id() AND is_user_admin_v2(auth.uid())) OR is_super_admin());

CREATE POLICY "System can insert transaction audit logs"
ON public.transaction_audit_log FOR INSERT TO authenticated WITH CHECK (true);

-- ====================
-- 3. RLS FOR CORE TABLES
-- ====================

DROP POLICY IF EXISTS "Company isolation for bom_headers" ON public.bom_headers;
CREATE POLICY "Company isolation for bom_headers" ON public.bom_headers FOR ALL TO authenticated
USING (company_id = user_company_id()) WITH CHECK (company_id = user_company_id());

DROP POLICY IF EXISTS "Company isolation for warehouse_bins" ON public.warehouse_bins;
CREATE POLICY "Company isolation for warehouse_bins" ON public.warehouse_bins FOR ALL TO authenticated
USING (company_id = user_company_id()) WITH CHECK (company_id = user_company_id());

DROP POLICY IF EXISTS "Company isolation for inventory_transactions" ON public.inventory_transactions;
CREATE POLICY "Company isolation for inventory_transactions" ON public.inventory_transactions FOR ALL TO authenticated
USING (company_id = user_company_id()) WITH CHECK (company_id = user_company_id());

DROP POLICY IF EXISTS "Company isolation for inventory_adjustments" ON public.inventory_adjustments;
CREATE POLICY "Company isolation for inventory_adjustments" ON public.inventory_adjustments FOR ALL TO authenticated
USING (company_id = user_company_id()) WITH CHECK (company_id = user_company_id());

DROP POLICY IF EXISTS "Company isolation for debit_notes" ON public.debit_notes;
CREATE POLICY "Company isolation for debit_notes" ON public.debit_notes FOR ALL TO authenticated
USING (company_id = user_company_id()) WITH CHECK (company_id = user_company_id());

DROP POLICY IF EXISTS "Company isolation for supplier_credit_notes" ON public.supplier_credit_notes;
CREATE POLICY "Company isolation for supplier_credit_notes" ON public.supplier_credit_notes FOR ALL TO authenticated
USING (company_id = user_company_id()) WITH CHECK (company_id = user_company_id());

DROP POLICY IF EXISTS "Company isolation for performa_invoices" ON public.performa_invoices;
CREATE POLICY "Company isolation for performa_invoices" ON public.performa_invoices FOR ALL TO authenticated
USING (company_id = user_company_id()) WITH CHECK (company_id = user_company_id());

-- ====================
-- 4. PAYMENT TRANSACTIONS
-- ====================

DROP POLICY IF EXISTS "Block anonymous access to payment_transactions" ON public.payment_transactions;
DROP POLICY IF EXISTS "Companies can view own payments" ON public.payment_transactions;
DROP POLICY IF EXISTS "Company can view own payments" ON public.payment_transactions;
DROP POLICY IF EXISTS "Super admin can manage payments" ON public.payment_transactions;
DROP POLICY IF EXISTS "Super admin can view all payments" ON public.payment_transactions;
DROP POLICY IF EXISTS "Super admin full access to payment_transactions" ON public.payment_transactions;
DROP POLICY IF EXISTS "Company admins can view own company payments" ON public.payment_transactions;
DROP POLICY IF EXISTS "Company admins can manage own company payments" ON public.payment_transactions;
DROP POLICY IF EXISTS "Company admins can update own company payments" ON public.payment_transactions;
DROP POLICY IF EXISTS "Company admins view own payments" ON public.payment_transactions;
DROP POLICY IF EXISTS "Company admins insert own payments" ON public.payment_transactions;
DROP POLICY IF EXISTS "Company admins update own payments" ON public.payment_transactions;

CREATE POLICY "Super admin full access" ON public.payment_transactions FOR ALL TO authenticated
USING (is_super_admin()) WITH CHECK (is_super_admin());

CREATE POLICY "Admins view payments" ON public.payment_transactions FOR SELECT TO authenticated
USING (company_id = user_company_id() AND is_user_admin_v2(auth.uid()));

CREATE POLICY "Admins insert payments" ON public.payment_transactions FOR INSERT TO authenticated
WITH CHECK (company_id = user_company_id() AND is_user_admin_v2(auth.uid()));

CREATE POLICY "Admins update payments" ON public.payment_transactions FOR UPDATE TO authenticated
USING (company_id = user_company_id() AND is_user_admin_v2(auth.uid()))
WITH CHECK (company_id = user_company_id() AND is_user_admin_v2(auth.uid()));