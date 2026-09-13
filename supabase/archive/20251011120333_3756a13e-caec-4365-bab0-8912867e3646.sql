-- Add search_path to all SECURITY DEFINER functions that are missing it
-- This prevents search path manipulation attacks

-- Fix generate_customer_ref function
CREATE OR REPLACE FUNCTION public.generate_customer_ref(customer_name text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    config_record RECORD;
    supplier_ref TEXT;
    comp_id UUID;
    first_four_letters TEXT;
    date_part TEXT;
    ref_no TEXT;
    counter INTEGER := 1;
    final_ref TEXT;
BEGIN
    SELECT user_company_id() INTO comp_id;
    
    SELECT * INTO config_record
    FROM public.document_format_configs 
    WHERE company_id = comp_id 
      AND document_type = 'customer_id' 
      AND is_active = true
    LIMIT 1;
    
    IF FOUND THEN
        supplier_ref := config_record.prefix || config_record.current_counter;
        
        UPDATE public.document_format_configs 
        SET current_counter = current_counter + 1,
            updated_at = now()
        WHERE id = config_record.id;
        
        RETURN supplier_ref;
    END IF;
    
    first_four_letters := UPPER(SUBSTRING(REGEXP_REPLACE(customer_name, '[^A-Za-z]', '', 'g') FROM 1 FOR 4));
    
    WHILE LENGTH(first_four_letters) < 4 LOOP
        first_four_letters := first_four_letters || 'X';
    END LOOP;
    
    date_part := LPAD(EXTRACT(MONTH FROM NOW())::TEXT, 2, '0') || EXTRACT(YEAR FROM NOW())::TEXT;
    ref_no := first_four_letters || '-' || date_part;
    final_ref := ref_no;
    
    WHILE EXISTS (SELECT 1 FROM public.customers WHERE customer_ref = final_ref) LOOP
        final_ref := ref_no || '-' || LPAD(counter::TEXT, 3, '0');
        counter := counter + 1;
    END LOOP;
    
    RETURN final_ref;
END;
$function$;

-- Fix generate_supplier_ref function
CREATE OR REPLACE FUNCTION public.generate_supplier_ref(supplier_name text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    config_record RECORD;
    supplier_ref TEXT;
    comp_id UUID;
    first_four_letters TEXT;
    date_part TEXT;
    ref_no TEXT;
    counter INTEGER := 1;
    final_ref TEXT;
BEGIN
    SELECT user_company_id() INTO comp_id;
    
    SELECT * INTO config_record
    FROM public.document_format_configs 
    WHERE company_id = comp_id 
      AND document_type = 'supplier_id' 
      AND is_active = true
    LIMIT 1;
    
    IF FOUND THEN
        supplier_ref := config_record.prefix || config_record.current_counter;
        
        UPDATE public.document_format_configs 
        SET current_counter = current_counter + 1,
            updated_at = now()
        WHERE id = config_record.id;
        
        RETURN supplier_ref;
    END IF;
    
    first_four_letters := UPPER(SUBSTRING(REGEXP_REPLACE(supplier_name, '[^A-Za-z]', '', 'g') FROM 1 FOR 4));
    
    WHILE LENGTH(first_four_letters) < 4 LOOP
        first_four_letters := first_four_letters || 'X';
    END LOOP;
    
    date_part := to_char(NOW(), 'DDMMYYYY');
    ref_no := first_four_letters || date_part;
    final_ref := ref_no;
    
    WHILE EXISTS (SELECT 1 FROM public.suppliers WHERE supplier_ref = final_ref) LOOP
        final_ref := ref_no || '-' || LPAD(counter::TEXT, 2, '0');
        counter := counter + 1;
    END LOOP;
    
    RETURN final_ref;
END;
$function$;

-- Fix generate_customer_id function
CREATE OR REPLACE FUNCTION public.generate_customer_id(customer_name text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    first_four_letters TEXT;
    counter INTEGER;
    customer_id TEXT;
BEGIN
    first_four_letters := UPPER(SUBSTRING(REGEXP_REPLACE(customer_name, '[^A-Za-z]', '', 'g') FROM 1 FOR 4));
    
    WHILE LENGTH(first_four_letters) < 4 LOOP
        first_four_letters := first_four_letters || 'X';
    END LOOP;
    
    SELECT COALESCE(MAX(
        CASE 
            WHEN c.customer_ref LIKE first_four_letters || '%' AND 
                 SUBSTRING(c.customer_ref FROM LENGTH(first_four_letters) + 1) ~ '^[0-9]+$' THEN
                CAST(SUBSTRING(c.customer_ref FROM LENGTH(first_four_letters) + 1) AS INTEGER)
            ELSE 1000
        END
    ), 1000) + 1
    INTO counter
    FROM public.customers c;
    
    IF counter < 1001 THEN
        counter := 1001;
    END IF;
    
    customer_id := first_four_letters || counter::TEXT;
    
    RETURN customer_id;
END;
$function$;

-- Fix generate_business_ref function
CREATE OR REPLACE FUNCTION public.generate_business_ref()
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    new_ref TEXT;
    counter INTEGER;
BEGIN
    SELECT COALESCE(MAX(CAST(SUBSTRING(business_ref FROM 5) AS INTEGER)), 0) + 1
    INTO counter
    FROM public.businesses;
    
    new_ref := 'BUS-' || LPAD(counter::TEXT, 6, '0');
    RETURN new_ref;
END;
$function$;

-- Fix generate_business_ref_no function
CREATE OR REPLACE FUNCTION public.generate_business_ref_no(company_name text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    first_four_letters TEXT;
    current_month TEXT;
    current_year TEXT;
    ref_no TEXT;
BEGIN
    first_four_letters := UPPER(SUBSTRING(REGEXP_REPLACE(company_name, '[^A-Za-z]', '', 'g') FROM 1 FOR 4));
    
    current_month := LPAD(EXTRACT(MONTH FROM NOW())::TEXT, 2, '0');
    current_year := EXTRACT(YEAR FROM NOW())::TEXT;
    
    ref_no := 'Rigel-' || first_four_letters || '-' || current_month || '-' || current_year;
    
    RETURN ref_no;
END;
$function$;

-- Fix check_email_exists function
CREATE OR REPLACE FUNCTION public.check_email_exists(email_to_check text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  user_exists boolean := false;
BEGIN
  SELECT EXISTS(
    SELECT 1 FROM auth.users 
    WHERE email = email_to_check
  ) INTO user_exists;
  
  RETURN user_exists;
EXCEPTION
  WHEN OTHERS THEN
    RETURN false;
END;
$function$;

-- Fix is_company_owner_or_admin function
CREATE OR REPLACE FUNCTION public.is_company_owner_or_admin(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.company_users
    WHERE user_id = p_user_id
      AND access_type IN ('OWNER', 'ADMIN')
  );
$function$;

-- Fix cleanup functions
CREATE OR REPLACE FUNCTION public.cleanup_expired_otps()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
BEGIN
  DELETE FROM public.email_otps 
  WHERE expires_at < now() - interval '24 hours';
  
  INSERT INTO public.security_audit_log (action, details, ip_address) 
  VALUES ('otp_cleanup', jsonb_build_object('deleted_count', ROW_COUNT), '127.0.0.1');
END;
$function$;

CREATE OR REPLACE FUNCTION public.cleanup_expired_tokens()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
BEGIN
  DELETE FROM public.email_otps WHERE expires_at < now() - interval '1 day';
  DELETE FROM public.email_confirmations WHERE expires_at < now() - interval '7 days';
  DELETE FROM public.password_resets WHERE used_at IS NOT NULL AND used_at < now() - interval '7 days';
  DELETE FROM public.auth_rate_limits WHERE last_attempt < now() - interval '7 days';
END;
$function$;

CREATE OR REPLACE FUNCTION public.cleanup_old_audit_logs()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
BEGIN
  DELETE FROM public.security_audit_log 
  WHERE created_at < now() - interval '90 days';
END;
$function$;

CREATE OR REPLACE FUNCTION public.cleanup_old_rate_limits()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
BEGIN
  DELETE FROM public.auth_rate_limits 
  WHERE last_attempt < now() - interval '24 hours';
END;
$function$;