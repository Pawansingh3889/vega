-- Fix Critical Security Issues from Supabase Dashboard

-- ============================================================================
-- Fix 1: Password Hash Exposure in company_users table
-- ============================================================================

-- The company_users_safe view already exists and is correct (excludes password_hash)
-- We just need to ensure it uses security_invoker
ALTER VIEW public.company_users_safe SET (security_invoker = on);

-- Update company_users SELECT policies
DROP POLICY IF EXISTS "Team members can view company members" ON public.company_users;
DROP POLICY IF EXISTS "Admins can view all company user fields" ON public.company_users;
DROP POLICY IF EXISTS "Team members can view company data" ON public.company_users;

-- Allow company members to view, but application should use company_users_safe 
-- to avoid exposing password_hash
CREATE POLICY "Team members can view company members"
ON public.company_users
FOR SELECT
USING (company_id = get_user_company_id());

-- ============================================================================
-- Fix 2: Add security_invoker to views to respect RLS
-- ============================================================================

-- Drop and recreate current_stock_levels with security_invoker
DROP VIEW IF EXISTS public.current_stock_with_aging CASCADE;
DROP VIEW IF EXISTS public.current_stock_levels CASCADE;

-- Recreate current_stock_levels (original definition)
CREATE VIEW public.current_stock_levels AS
SELECT 
  company_id,
  product_id,
  warehouse_id,
  bin_id,
  sum(quantity_change) AS current_stock,
  count(*) AS transaction_count,
  max(transaction_date) AS last_transaction_date
FROM inventory_transactions it
WHERE (company_id = user_company_id())
GROUP BY company_id, product_id, warehouse_id, bin_id;

ALTER VIEW public.current_stock_levels SET (security_invoker = on);

-- Recreate current_stock_with_aging (original definition)
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
FROM current_stock_levels csl
CROSS JOIN LATERAL calculate_fifo_aging(csl.product_id, csl.warehouse_id, csl.bin_id) aging(
  aging_0_30_qty,
  aging_0_30_value,
  aging_31_90_qty,
  aging_31_90_value,
  aging_91_180_qty,
  aging_91_180_value,
  aging_181_365_qty,
  aging_181_365_value,
  aging_365_plus_qty,
  aging_365_plus_value,
  weighted_avg_age_days,
  total_current_qty,
  total_current_value
);

ALTER VIEW public.current_stock_with_aging SET (security_invoker = on);

-- Update credit_note_stats
DROP VIEW IF EXISTS public.credit_note_stats CASCADE;

CREATE VIEW public.credit_note_stats AS
SELECT 
  company_id,
  COUNT(*) FILTER (WHERE status = 'Draft') as draft_count,
  COALESCE(SUM(total_amount) FILTER (WHERE status = 'Draft'), 0) as draft_amount,
  COUNT(*) FILTER (WHERE status = 'Confirmed') as confirmed_count,
  COALESCE(SUM(total_amount) FILTER (WHERE status = 'Confirmed'), 0) as confirmed_amount
FROM credit_notes
GROUP BY company_id;

ALTER VIEW public.credit_note_stats SET (security_invoker = on);

-- Grant permissions
GRANT SELECT ON public.company_users_safe TO authenticated;
GRANT SELECT ON public.current_stock_levels TO authenticated;
GRANT SELECT ON public.current_stock_with_aging TO authenticated;
GRANT SELECT ON public.credit_note_stats TO authenticated;