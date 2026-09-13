-- ============================================
-- PRODUCTION SECURITY HARDENING (Fixed)
-- ============================================

-- 1. First drop the trigger that depends on otp_code
DROP TRIGGER IF EXISTS set_otp_expiry ON public.profiles;
DROP FUNCTION IF EXISTS public.generate_otp_with_expiry();

-- Now safely remove OTP columns from profiles table
ALTER TABLE public.profiles 
DROP COLUMN IF EXISTS otp_code,
DROP COLUMN IF EXISTS otp_expires_at;

-- 2. Create safe view for company_users without password_hash exposure
CREATE OR REPLACE VIEW public.company_users_safe WITH (security_barrier = true) AS
SELECT 
  id,
  company_id,
  user_id,
  username,
  email,
  access_type,
  status,
  full_name,
  designation,
  created_at,
  updated_at,
  created_by
FROM public.company_users
WHERE company_id = user_company_id();

GRANT SELECT ON public.company_users_safe TO authenticated;

-- 3. Create automated cleanup function for expired tokens and old data
CREATE OR REPLACE FUNCTION public.cleanup_expired_security_data()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM public.email_otps WHERE expires_at < now() - interval '24 hours';
  DELETE FROM public.email_confirmations WHERE expires_at < now() - interval '7 days';
  DELETE FROM public.password_resets WHERE used_at IS NOT NULL AND used_at < now() - interval '7 days';
  DELETE FROM public.auth_rate_limits WHERE last_attempt < now() - interval '7 days';
  DELETE FROM public.security_audit_log WHERE created_at < now() - interval '90 days';
  DELETE FROM public.transaction_audit_log WHERE created_at < now() - interval '365 days';
  
  INSERT INTO public.security_audit_log (action, details, ip_address, severity)
  VALUES ('automated_data_cleanup', jsonb_build_object('cleanup_time', now(), 'tables_cleaned', ARRAY['email_otps', 'email_confirmations', 'password_resets', 'auth_rate_limits', 'security_audit_log', 'transaction_audit_log']), '127.0.0.1', 'low');
END;
$$;

-- 4. Add function to detect suspicious activity
CREATE OR REPLACE FUNCTION public.detect_security_anomalies()
RETURNS TABLE(anomaly_type text, severity text, details jsonb, detected_at timestamp with time zone)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  RETURN QUERY SELECT 'high_failed_login_rate'::text, 'critical'::text, jsonb_build_object('blocked_count', COUNT(*), 'emails', array_agg(DISTINCT hashed_email)), now()
  FROM public.auth_rate_limits WHERE attempt_count >= 5 AND last_attempt > now() - interval '1 hour' HAVING COUNT(*) > 0;
  
  RETURN QUERY SELECT 'multiple_password_resets'::text, 'high'::text, jsonb_build_object('user_count', COUNT(DISTINCT user_id), 'total_attempts', COUNT(*)), now()
  FROM public.password_resets WHERE created_at > now() - interval '1 hour' HAVING COUNT(*) > 10;
  
  RETURN QUERY SELECT 'unusual_security_events'::text, 'medium'::text, jsonb_build_object('event_types', array_agg(DISTINCT action), 'event_count', COUNT(*)), now()
  FROM public.security_audit_log WHERE created_at > now() - interval '1 hour' AND severity IN ('high', 'critical') HAVING COUNT(*) > 5;
END;
$$;

-- 5. Password history tracking
CREATE TABLE IF NOT EXISTS public.password_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  password_hash text NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now()
);

ALTER TABLE public.password_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own password history" ON public.password_history FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "System can insert password history" ON public.password_history FOR INSERT WITH CHECK (true);

CREATE INDEX IF NOT EXISTS idx_password_history_user_id ON public.password_history(user_id, created_at DESC);

-- 6. Track password changes
CREATE OR REPLACE FUNCTION public.track_password_change()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NEW.password_hash IS DISTINCT FROM OLD.password_hash THEN
    INSERT INTO public.password_history (user_id, password_hash) VALUES (NEW.user_id, OLD.password_hash);
    DELETE FROM public.password_history WHERE user_id = NEW.user_id AND id NOT IN (SELECT id FROM public.password_history WHERE user_id = NEW.user_id ORDER BY created_at DESC LIMIT 5);
    INSERT INTO public.security_audit_log (user_id, action, details, ip_address, severity) VALUES (NEW.user_id, 'password_changed', jsonb_build_object('user_id', NEW.user_id, 'timestamp', now()), '127.0.0.1', 'medium');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS track_password_change_trigger ON public.company_users;
CREATE TRIGGER track_password_change_trigger AFTER UPDATE OF password_hash ON public.company_users FOR EACH ROW EXECUTE FUNCTION public.track_password_change();

-- 7. Validate password reuse
CREATE OR REPLACE FUNCTION public.is_password_reused(p_user_id uuid, p_new_password_hash text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (SELECT 1 FROM public.password_history WHERE user_id = p_user_id AND password_hash = p_new_password_hash LIMIT 1);
END;
$$;

-- 8. Security settings per company
CREATE TABLE IF NOT EXISTS public.security_settings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE UNIQUE,
  session_timeout_minutes integer NOT NULL DEFAULT 60,
  require_mfa boolean NOT NULL DEFAULT false,
  password_expiry_days integer NOT NULL DEFAULT 90,
  max_failed_attempts integer NOT NULL DEFAULT 5,
  lockout_duration_minutes integer NOT NULL DEFAULT 15,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now()
);

ALTER TABLE public.security_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company users can view security settings" ON public.security_settings FOR SELECT USING (company_id = user_company_id());
CREATE POLICY "Admins can manage security settings" ON public.security_settings FOR ALL USING (company_id = user_company_id() AND is_user_admin());

INSERT INTO public.security_settings (company_id) SELECT id FROM public.companies ON CONFLICT (company_id) DO NOTHING;