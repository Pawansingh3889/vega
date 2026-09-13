-- ============================================================================
-- PART 1: SAFE VIEWS AND AUDIT LOG RESTRICTIONS
-- ============================================================================

-- Create safe views for customers and suppliers
DROP VIEW IF EXISTS public.customers_safe CASCADE;
CREATE VIEW public.customers_safe 
WITH (security_invoker = true)
AS
SELECT 
  id, company_id, name, customer_ref, customer_type, is_active,
  city, state, country, pin_code,
  gstin, pan_number, gst_tax_location,
  credit_limit, credit_limit_days,
  created_at, updated_at
FROM public.customers;

GRANT SELECT ON public.customers_safe TO authenticated;
COMMENT ON VIEW public.customers_safe IS 
'Safe view of customers excluding sensitive fields (email, phone, address, bank details, MSME/business registration). Use for general staff access.';

DROP VIEW IF EXISTS public.suppliers_safe CASCADE;
CREATE VIEW public.suppliers_safe 
WITH (security_invoker = true)
AS
SELECT 
  id, company_id, name, supplier_ref, supplier_type, is_active,
  city, state, country, pin_code,
  gst_number, pan_number, place_of_supply,
  credit_time, created_at, updated_at
FROM public.suppliers;

GRANT SELECT ON public.suppliers_safe TO authenticated;
COMMENT ON VIEW public.suppliers_safe IS 
'Safe view of suppliers excluding sensitive fields (email, phone, contact person, bank details, tax IDs). Use for general staff access.';

-- Restrict audit log access to admins only
DROP POLICY IF EXISTS "Admins can view audit logs" ON public.security_audit_log;
DROP POLICY IF EXISTS "System can insert audit logs" ON public.security_audit_log;
DROP POLICY IF EXISTS "Only admins can view security audit logs" ON public.security_audit_log;
DROP POLICY IF EXISTS "System can insert security audit logs" ON public.security_audit_log;

CREATE POLICY "Only admins can view security audit logs"
ON public.security_audit_log
FOR SELECT TO authenticated
USING (is_super_admin() OR (user_id = auth.uid() AND is_user_admin_v2(auth.uid())));

CREATE POLICY "System can insert security audit logs"
ON public.security_audit_log
FOR INSERT TO authenticated
WITH CHECK (true);

DROP POLICY IF EXISTS "Admins can view audit logs" ON public.transaction_audit_log;
DROP POLICY IF EXISTS "System can insert audit logs" ON public.transaction_audit_log;
DROP POLICY IF EXISTS "Only admins can view transaction audit logs" ON public.transaction_audit_log;
DROP POLICY IF EXISTS "System can insert transaction audit logs" ON public.transaction_audit_log;

CREATE POLICY "Only admins can view transaction audit logs"
ON public.transaction_audit_log
FOR SELECT TO authenticated
USING (
  (company_id = user_company_id() AND is_user_admin_v2(auth.uid()))
  OR is_super_admin()
);

CREATE POLICY "System can insert transaction audit logs"
ON public.transaction_audit_log
FOR INSERT TO authenticated
WITH CHECK (true);