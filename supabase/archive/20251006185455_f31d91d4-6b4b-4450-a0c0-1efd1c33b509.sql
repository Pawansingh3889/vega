-- Create profiles_safe view to restrict phone number access
CREATE OR REPLACE VIEW public.profiles_safe
WITH (security_invoker=true) AS
SELECT
  p.id,
  p.user_id,
  p.company_id,
  p.first_name,
  p.last_name,
  p.avatar_url,
  p.role,
  p.is_active,
  p.created_at,
  p.updated_at,
  p.city,
  p.state,
  p.country,
  p.phone_verified
FROM public.profiles p;

COMMENT ON VIEW public.profiles_safe IS 'Safe view of profiles excluding phone numbers for general staff access';

GRANT SELECT ON public.profiles_safe TO authenticated;