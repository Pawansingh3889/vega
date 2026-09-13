-- Add owner role for all users who have profiles but no roles
-- This ensures existing users get proper role assignments
INSERT INTO public.user_roles (user_id, company_id, role)
SELECT DISTINCT
  p.user_id,
  p.company_id,
  'owner'::app_role
FROM public.profiles p
WHERE NOT EXISTS (
  SELECT 1 FROM public.user_roles ur
  WHERE ur.user_id = p.user_id
  AND ur.company_id = p.company_id
)
ON CONFLICT DO NOTHING;