-- Fix RLS policies that still reference user_roles table
-- Drop old policies that use has_role() function
DROP POLICY IF EXISTS "Company owners can update their company" ON public.companies;
DROP POLICY IF EXISTS "Business owners can manage their subscriptions" ON public.subscriptions;

-- Create new policy for companies table using company_users.access_type
CREATE POLICY "Owners and Admins can update their company"
ON public.companies
FOR UPDATE
TO authenticated
USING (
  id IN (
    SELECT company_id
    FROM public.company_users
    WHERE user_id = auth.uid()
      AND access_type IN ('OWNER', 'ADMIN')
  )
);

-- Create new policy for subscriptions table using company_users.access_type
CREATE POLICY "Owners and Admins can manage subscriptions"
ON public.subscriptions
FOR ALL
TO authenticated
USING (
  business_id IN (
    SELECT company_id
    FROM public.company_users
    WHERE user_id = auth.uid()
      AND access_type IN ('OWNER', 'ADMIN')
  )
);

-- Also update user_roles policies to use company_users instead (in case they're still queried)
DROP POLICY IF EXISTS "Admins can view company roles" ON public.user_roles;
DROP POLICY IF EXISTS "Only owners can manage roles" ON public.user_roles;

-- New policy: Only owners can manage user_roles (if this table is still being used)
CREATE POLICY "Only owners can manage user roles"
ON public.user_roles
FOR ALL
TO authenticated
USING (
  company_id IN (
    SELECT company_id
    FROM public.company_users
    WHERE user_id = auth.uid()
      AND access_type = 'OWNER'
  )
);