-- Fix infinite recursion in company_users RLS policies
-- Drop problematic recursive policies
DROP POLICY IF EXISTS "Owners and Admins can view all company users" ON public.company_users;
DROP POLICY IF EXISTS "Owners and Admins can create company users" ON public.company_users;
DROP POLICY IF EXISTS "Owners and Admins can update company users" ON public.company_users;

-- Create non-recursive SELECT policies
-- Policy 1: Users can always view their own record (breaks recursion)
CREATE POLICY "Users can view own record"
ON public.company_users
FOR SELECT
TO authenticated
USING (
  user_id = auth.uid() 
  OR email::text = (SELECT email FROM auth.users WHERE id = auth.uid())::text
);

-- Policy 2: Owners/Admins can view all users (uses security definer function)
CREATE POLICY "Owners and Admins can view company users"
ON public.company_users
FOR SELECT
TO authenticated
USING (
  public.is_company_owner_or_admin(auth.uid()) 
  AND company_id IN (
    SELECT company_id FROM public.company_users WHERE user_id = auth.uid()
  )
);

-- Fix INSERT policy
CREATE POLICY "Owners and Admins can create users"
ON public.company_users
FOR INSERT
TO authenticated
WITH CHECK (
  public.is_company_owner_or_admin(auth.uid())
  AND company_id IN (
    SELECT company_id FROM public.company_users WHERE user_id = auth.uid()
  )
);

-- Fix UPDATE policy
CREATE POLICY "Owners and Admins can update users"
ON public.company_users
FOR UPDATE
TO authenticated
USING (
  public.is_company_owner_or_admin(auth.uid())
  AND company_id IN (
    SELECT company_id FROM public.company_users WHERE user_id = auth.uid()
  )
)
WITH CHECK (
  public.is_company_owner_or_admin(auth.uid())
  AND company_id IN (
    SELECT company_id FROM public.company_users WHERE user_id = auth.uid()
  )
);