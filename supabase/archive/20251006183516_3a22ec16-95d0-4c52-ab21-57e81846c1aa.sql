-- ===========================================================================
-- FIX: Security linter issues and complete the security hardening
-- ===========================================================================

-- 1. RECREATE THE SAFE VIEW (views can't have RLS, they inherit from tables)
DROP VIEW IF EXISTS public.company_users_safe CASCADE;

CREATE VIEW public.company_users_safe AS
SELECT 
  id, company_id, user_id, username, email, access_type, status,
  full_name, designation, created_by, created_at, updated_at
FROM public.company_users;

-- Grant SELECT to authenticated users
GRANT SELECT ON public.company_users_safe TO authenticated;

-- 2. UPDATE company_users RLS POLICIES to use new role system
-- Drop old policies that reference outdated functions
DROP POLICY IF EXISTS "Only admins can view all user fields" ON public.company_users;
DROP POLICY IF EXISTS "Only admins can create team members" ON public.company_users;
DROP POLICY IF EXISTS "Only admins can update team members" ON public.company_users;
DROP POLICY IF EXISTS "Only admins can delete team members" ON public.company_users;

-- Create new policies using the user_roles table
CREATE POLICY "Admins can view company users (no password hash via view)"
ON public.company_users
FOR SELECT TO authenticated
USING (
  company_id IN (
    SELECT company_id FROM public.user_roles 
    WHERE user_id = auth.uid() AND role IN ('owner', 'admin')
  )
);

CREATE POLICY "Admins can create company users"
ON public.company_users
FOR INSERT TO authenticated
WITH CHECK (
  company_id IN (
    SELECT company_id FROM public.user_roles 
    WHERE user_id = auth.uid() AND role IN ('owner', 'admin')
  )
);

CREATE POLICY "Admins can update company users"
ON public.company_users
FOR UPDATE TO authenticated
USING (
  company_id IN (
    SELECT company_id FROM public.user_roles 
    WHERE user_id = auth.uid() AND role IN ('owner', 'admin')
  )
);

CREATE POLICY "Admins can delete company users"
ON public.company_users
FOR DELETE TO authenticated
USING (
  company_id IN (
    SELECT company_id FROM public.user_roles 
    WHERE user_id = auth.uid() AND role IN ('owner', 'admin')
  )
);

-- 3. DOCUMENT THAT PASSWORD HASHES SHOULD ONLY BE ACCESSED VIA BACKEND
COMMENT ON VIEW public.company_users_safe IS 
'Safe view of company_users that excludes password_hash. Always use this view in application code, never query company_users directly.';