-- Step 1: Drop unused user_company_access table
DROP TABLE IF EXISTS public.user_company_access CASCADE;

-- Step 2: Sync data - ensure all users in user_roles also exist in company_users
-- Use ON CONFLICT with the actual unique constraint (company_id, username)
INSERT INTO public.company_users (
  company_id,
  user_id,
  username,
  email,
  password_hash,
  access_type,
  status,
  created_at
)
SELECT DISTINCT
  ur.company_id,
  ur.user_id,
  au.email, -- Using email as username
  au.email,
  '', -- Empty password hash (user already authenticated via Supabase Auth)
  UPPER(ur.role::text), -- Convert 'owner' to 'OWNER'
  'ACTIVE',
  now()
FROM public.user_roles ur
JOIN auth.users au ON au.id = ur.user_id
WHERE NOT EXISTS (
  SELECT 1 FROM public.company_users cu
  WHERE cu.user_id = ur.user_id
  AND cu.company_id = ur.company_id
)
ON CONFLICT (company_id, username) DO UPDATE
SET user_id = EXCLUDED.user_id,
    access_type = EXCLUDED.access_type
WHERE company_users.user_id IS NULL; -- Only update if user_id wasn't set

-- Step 3: Sync data - ensure all users in company_users also exist in user_roles
INSERT INTO public.user_roles (
  user_id,
  company_id,
  role
)
SELECT DISTINCT
  cu.user_id,
  cu.company_id,
  LOWER(cu.access_type)::app_role -- Convert 'OWNER' to 'owner'
FROM public.company_users cu
WHERE cu.user_id IS NOT NULL
AND NOT EXISTS (
  SELECT 1 FROM public.user_roles ur
  WHERE ur.user_id = cu.user_id
  AND ur.company_id = cu.company_id
)
AND LOWER(cu.access_type) IN ('owner', 'admin', 'manager', 'staff');