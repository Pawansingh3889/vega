-- Add missing severity column to security_audit_log table
ALTER TABLE public.security_audit_log 
ADD COLUMN IF NOT EXISTS severity text DEFAULT 'info';

-- Now update the password with bcrypt hash
UPDATE public.company_users
SET password_hash = crypt('Apmt@1234', gen_salt('bf', 12))
WHERE username = 'rigelenterpriseinfo@gmail.com'
  AND email = 'rigelenterpriseinfo@gmail.com'
  AND company_id IN (
    SELECT id FROM public.companies 
    WHERE business_ref_no = 'Rigel-RIGE-10-2025'
  );