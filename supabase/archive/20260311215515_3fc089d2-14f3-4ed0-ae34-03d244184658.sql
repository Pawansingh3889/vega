-- Fix companies INSERT policy: restrict to service_role (edge functions handle registration)
DROP POLICY IF EXISTS "Allow company registration operations" ON public.companies;
CREATE POLICY "Allow company registration via service role"
ON public.companies FOR INSERT TO service_role
WITH CHECK (true);

-- Fix password_history INSERT policy: restrict to service_role
DROP POLICY IF EXISTS "System can insert password history" ON public.password_history;
CREATE POLICY "Service role can insert password history"
ON public.password_history FOR INSERT TO service_role
WITH CHECK (true);

-- Fix security_audit_log INSERT policy: scope to authenticated user's own entries
DROP POLICY IF EXISTS "System can insert security audit logs" ON public.security_audit_log;
CREATE POLICY "Service role can insert security audit logs"
ON public.security_audit_log FOR INSERT TO service_role
WITH CHECK (true);

-- Fix transaction_audit_log INSERT policy: scope to service_role
DROP POLICY IF EXISTS "System can insert transaction audit logs" ON public.transaction_audit_log;
CREATE POLICY "Service role can insert transaction audit logs"
ON public.transaction_audit_log FOR INSERT TO service_role
WITH CHECK (true);