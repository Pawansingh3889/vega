-- Add missing severity column to security_audit_log if it doesn't exist
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'security_audit_log' 
    AND column_name = 'severity'
  ) THEN
    ALTER TABLE public.security_audit_log 
    ADD COLUMN severity text DEFAULT 'info';
  END IF;
END $$;

-- Enable pgcrypto extension if not already enabled
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Update the password for rigelenterpriseinfo@gmail.com with bcrypt hash
-- Password: Apmt@1234
UPDATE public.company_users
SET password_hash = crypt('Apmt@1234', gen_salt('bf', 12)),
    updated_at = now()
WHERE username = 'rigelenterpriseinfo@gmail.com'
  AND email = 'rigelenterpriseinfo@gmail.com'
  AND company_id IN (
    SELECT id FROM public.companies 
    WHERE business_ref_no = 'Rigel-RIGE-10-2025'
  );

-- Log the password reset for security audit
INSERT INTO public.security_audit_log (action, details, ip_address, severity)
VALUES (
  'password_reset_admin',
  jsonb_build_object(
    'username', 'rigelenterpriseinfo@gmail.com',
    'business_ref', 'Rigel-RIGE-10-2025',
    'reset_by', 'system_admin',
    'timestamp', now()
  ),
  '127.0.0.1',
  'medium'
);