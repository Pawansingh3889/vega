-- Drop and recreate company_users_safe view with security_invoker = false to bypass RLS
DROP VIEW IF EXISTS company_users_safe;

CREATE VIEW company_users_safe 
WITH (security_invoker = false)
AS
SELECT 
  id,
  company_id,
  user_id,
  username,
  email,
  access_type,
  status,
  full_name,
  designation,
  created_by,
  created_at,
  updated_at
FROM company_users;

-- Grant select permission on the view
GRANT SELECT ON company_users_safe TO authenticated;