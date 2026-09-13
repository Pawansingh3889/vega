
-- Insert full access permissions for owner user
INSERT INTO public.company_user_section_permissions (
  company_id,
  user_email,
  access_sections
)
VALUES (
  '5e1edf56-c589-4312-b658-e66ff1ec1c72',
  'rigelenterpriseinfo@gmail.com',
  '{
    "inventory": "edit",
    "purchases": "edit",
    "sales": "edit",
    "returns": "edit",
    "payments": "edit",
    "reports": "edit",
    "tracking": "edit",
    "ai": "edit",
    "company_profile": "edit",
    "settings": "edit"
  }'::jsonb
)
ON CONFLICT (company_id, user_email) 
DO UPDATE SET 
  access_sections = EXCLUDED.access_sections,
  updated_at = now();
