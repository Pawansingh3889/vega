-- Sync user_roles with company_users for rigelenterpriseinfo@gmail.com
DO $$
DECLARE
  v_user_id UUID;
  v_role TEXT;
  v_company_id UUID := '5e1edf56-c589-4312-b658-e66ff1ec1c72';
  v_email TEXT := 'rigelenterpriseinfo@gmail.com';
BEGIN
  -- Get user_id from auth.users
  SELECT id INTO v_user_id 
  FROM auth.users 
  WHERE email = v_email;
  
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'User % not found in auth.users', v_email;
  END IF;
  
  -- Get role from user_roles
  SELECT role INTO v_role 
  FROM public.user_roles 
  WHERE user_id = v_user_id;
  
  IF v_role IS NULL THEN
    RAISE EXCEPTION 'User % has no role in user_roles table', v_email;
  END IF;
  
  -- Insert or update company_users
  INSERT INTO public.company_users (
    company_id,
    user_id,
    email,
    username,
    password_hash,
    access_type,
    status,
    created_at,
    updated_at
  )
  VALUES (
    v_company_id,
    v_user_id,
    v_email,
    v_email,
    'auth_handled', -- Placeholder since auth is via auth.users
    CASE 
      WHEN v_role = 'owner' THEN 'OWNER'
      WHEN v_role = 'admin' THEN 'ADMIN'
      WHEN v_role = 'manager' THEN 'MANAGER'
      ELSE 'USER'
    END,
    'ACTIVE',
    now(),
    now()
  )
  ON CONFLICT (company_id, email) 
  DO UPDATE SET
    access_type = CASE 
      WHEN v_role = 'owner' THEN 'OWNER'
      WHEN v_role = 'admin' THEN 'ADMIN'
      WHEN v_role = 'manager' THEN 'MANAGER'
      ELSE 'USER'
    END,
    status = 'ACTIVE',
    updated_at = now();
    
  RAISE NOTICE 'Successfully synced user % to company_users with access_type %', v_email, v_role;
END $$;