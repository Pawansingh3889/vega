-- Create security definer function to get user's company_id without triggering RLS
CREATE OR REPLACE FUNCTION get_user_company_id_safe()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT company_id 
  FROM company_users 
  WHERE user_id = auth.uid() 
  LIMIT 1;
$$;

-- Create security definer function to check if user is owner/admin without triggering RLS
CREATE OR REPLACE FUNCTION is_user_owner_or_admin_safe()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 
    FROM company_users 
    WHERE user_id = auth.uid() 
    AND access_type IN ('OWNER', 'ADMIN')
  );
$$;

-- Drop all existing recursive policies on company_users
DROP POLICY IF EXISTS "Owners and Admins can create users" ON company_users;
DROP POLICY IF EXISTS "Owners and Admins can view company users" ON company_users;
DROP POLICY IF EXISTS "Owners and Admins can update users" ON company_users;
DROP POLICY IF EXISTS "Owners and Admins can delete company users" ON company_users;
DROP POLICY IF EXISTS "Users can view own record" ON company_users;
DROP POLICY IF EXISTS "Users can view their own company user record" ON company_users;

-- Create new non-recursive policies using security definer functions
CREATE POLICY "Users can view company users"
  ON company_users FOR SELECT
  USING (company_id = get_user_company_id_safe());

CREATE POLICY "Users can create users in their company"
  ON company_users FOR INSERT
  WITH CHECK (company_id = get_user_company_id_safe());

CREATE POLICY "Users can update users in their company"
  ON company_users FOR UPDATE
  USING (company_id = get_user_company_id_safe())
  WITH CHECK (company_id = get_user_company_id_safe());

CREATE POLICY "Users can delete users in their company (except self)"
  ON company_users FOR DELETE
  USING (company_id = get_user_company_id_safe() AND user_id != auth.uid());