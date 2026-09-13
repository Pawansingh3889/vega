-- Drop existing RLS policies on company_users that reference user_roles
DROP POLICY IF EXISTS "Admins can view company users (no password hash via view)" ON public.company_users;
DROP POLICY IF EXISTS "Admins can create company users" ON public.company_users;
DROP POLICY IF EXISTS "Admins can update company users" ON public.company_users;
DROP POLICY IF EXISTS "Admins can delete company users" ON public.company_users;

-- Create security definer function to check if user has OWNER or ADMIN access
CREATE OR REPLACE FUNCTION public.is_company_owner_or_admin(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.company_users
    WHERE user_id = p_user_id
      AND access_type IN ('OWNER', 'ADMIN')
  );
$$;

-- Policy: Users can view their own company_users record
CREATE POLICY "Users can view their own company user record"
ON public.company_users
FOR SELECT
TO authenticated
USING (
  user_id = auth.uid()
  OR email = (SELECT email FROM auth.users WHERE id = auth.uid())
);

-- Policy: Owners and Admins can view all company users in their company
CREATE POLICY "Owners and Admins can view all company users"
ON public.company_users
FOR SELECT
TO authenticated
USING (
  company_id IN (
    SELECT company_id 
    FROM public.company_users 
    WHERE user_id = auth.uid()
      AND access_type IN ('OWNER', 'ADMIN')
  )
);

-- Policy: Owners and Admins can create company users
CREATE POLICY "Owners and Admins can create company users"
ON public.company_users
FOR INSERT
TO authenticated
WITH CHECK (
  public.is_company_owner_or_admin(auth.uid())
  AND company_id IN (
    SELECT company_id 
    FROM public.company_users 
    WHERE user_id = auth.uid()
  )
);

-- Policy: Owners and Admins can update company users in their company
CREATE POLICY "Owners and Admins can update company users"
ON public.company_users
FOR UPDATE
TO authenticated
USING (
  company_id IN (
    SELECT company_id 
    FROM public.company_users 
    WHERE user_id = auth.uid()
      AND access_type IN ('OWNER', 'ADMIN')
  )
);

-- Policy: Owners and Admins can delete company users in their company
CREATE POLICY "Owners and Admins can delete company users"
ON public.company_users
FOR DELETE
TO authenticated
USING (
  company_id IN (
    SELECT company_id 
    FROM public.company_users 
    WHERE user_id = auth.uid()
      AND access_type IN ('OWNER', 'ADMIN')
  )
  AND user_id != auth.uid()  -- Prevent self-deletion
);