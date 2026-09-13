-- Fix security_definer view warning by making it security_invoker
DROP VIEW IF EXISTS public.company_users_safe CASCADE;

CREATE VIEW public.company_users_safe 
WITH (security_invoker = true)
AS
SELECT 
  id, company_id, user_id, username, email, access_type, status,
  full_name, designation, created_by, created_at, updated_at
FROM public.company_users;

GRANT SELECT ON public.company_users_safe TO authenticated;

COMMENT ON VIEW public.company_users_safe IS 
'Safe view of company_users that excludes password_hash. Uses security_invoker=true to respect RLS policies of querying user. Always use this view in application code.';