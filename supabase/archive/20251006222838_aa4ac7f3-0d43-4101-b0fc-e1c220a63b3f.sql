-- Fix is_user_admin() to use company_users.access_type instead of non-existent profiles.role
-- Use CREATE OR REPLACE to avoid breaking dependent RLS policies

CREATE OR REPLACE FUNCTION public.is_user_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT EXISTS (
    SELECT 1 
    FROM public.company_users 
    WHERE user_id = auth.uid() 
    AND access_type IN ('OWNER', 'ADMIN')
  );
$$;