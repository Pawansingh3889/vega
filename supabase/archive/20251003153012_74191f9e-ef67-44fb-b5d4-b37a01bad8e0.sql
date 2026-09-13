-- Fix Critical Security Issues from Supabase Dashboard

-- ============================================================================
-- Fix 1: Password Hash Exposure in company_users table
-- ============================================================================

-- Drop existing policies on company_users
DROP POLICY IF EXISTS "Team members can view company members" ON public.company_users;
DROP POLICY IF EXISTS "Admins can view all company user fields" ON public.company_users;
DROP POLICY IF EXISTS "Team members can view company data" ON public.company_users;

-- Restrict direct access to company_users to admins only
-- This prevents password_hash exposure to regular users
CREATE POLICY "Only admins can view all user fields"
ON public.company_users
FOR SELECT
USING ((company_id = get_user_company_id()) AND is_user_admin());

-- Drop and recreate the safe view without SECURITY DEFINER
DROP VIEW IF EXISTS public.company_users_safe CASCADE;

CREATE VIEW public.company_users_safe AS
SELECT 
  id,
  company_id,
  user_id,
  created_by,
  username,
  email,
  access_type,
  status,
  full_name,
  designation,
  created_at,
  updated_at
FROM public.company_users;

-- Set security_invoker to respect RLS from underlying table
ALTER VIEW public.company_users_safe SET (security_invoker = on);

-- Grant access to the safe view for all authenticated users
GRANT SELECT ON public.company_users_safe TO authenticated;

-- ============================================================================
-- Fix 2: Remove SECURITY DEFINER from views
-- ============================================================================

-- Fix current_stock_levels view
DROP VIEW IF EXISTS public.current_stock_with_aging CASCADE;
DROP VIEW IF EXISTS public.current_stock_levels CASCADE;

CREATE VIEW public.current_stock_levels AS
SELECT 
  company_id,
  product_id,
  warehouse_id,
  bin_id,
  SUM(quantity_change) AS current_stock,
  COUNT(*) AS transaction_count,
  MAX(transaction_date) AS last_transaction_date
FROM inventory_transactions it
WHERE company_id = user_company_id()
GROUP BY company_id, product_id, warehouse_id, bin_id;

ALTER VIEW public.current_stock_levels SET (security_invoker = on);
GRANT SELECT ON public.current_stock_levels TO authenticated;

-- Recreate current_stock_with_aging
CREATE VIEW public.current_stock_with_aging AS
SELECT 
  csl.company_id,
  csl.product_id,
  csl.warehouse_id,
  csl.bin_id,
  csl.current_stock,
  csl.transaction_count,
  csl.last_transaction_date,
  aging.aging_0_30_qty,
  aging.aging_0_30_value,
  aging.aging_31_90_qty,
  aging.aging_31_90_value,
  aging.aging_91_180_qty,
  aging.aging_91_180_value,
  aging.aging_181_365_qty,
  aging.aging_181_365_value,
  aging.aging_365_plus_qty,
  aging.aging_365_plus_value,
  aging.weighted_avg_age_days,
  aging.total_current_qty,
  aging.total_current_value
FROM public.current_stock_levels csl
CROSS JOIN LATERAL calculate_fifo_aging(csl.product_id, csl.warehouse_id, csl.bin_id) aging;

ALTER VIEW public.current_stock_with_aging SET (security_invoker = on);
GRANT SELECT ON public.current_stock_with_aging TO authenticated;

-- Fix credit_note_stats view
DROP VIEW IF EXISTS public.credit_note_stats CASCADE;

CREATE VIEW public.credit_note_stats AS
SELECT 
  company_id,
  COUNT(*) FILTER (WHERE status = 'Draft') as draft_count,
  COALESCE(SUM(total_amount) FILTER (WHERE status = 'Draft'), 0) as draft_amount,
  COUNT(*) FILTER (WHERE status = 'Confirmed') as confirmed_count,
  COALESCE(SUM(total_amount) FILTER (WHERE status = 'Confirmed'), 0) as confirmed_amount
FROM public.credit_notes
GROUP BY company_id;

ALTER VIEW public.credit_note_stats SET (security_invoker = on);
GRANT SELECT ON public.credit_note_stats TO authenticated;