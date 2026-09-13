-- =====================================================
-- CRITICAL SECURITY FIXES MIGRATION
-- This migration addresses multiple security vulnerabilities
-- =====================================================

-- =====================================================
-- FIX 1: Purchase Orders RLS Policy
-- Issue: Debug policy allows all authenticated users to view all purchase orders
-- Fix: Implement proper company isolation
-- =====================================================

-- Drop the dangerous debug policy
DROP POLICY IF EXISTS "Debug - Allow authenticated users to view purchase orders" ON public.purchase_orders;

-- Create proper company isolation policy
CREATE POLICY "Company isolation for purchase_orders"
ON public.purchase_orders
FOR ALL
USING (company_id = user_company_id())
WITH CHECK (company_id = user_company_id());

-- =====================================================
-- FIX 2: Auth Rate Limits Security
-- Issue: Table is publicly accessible, exposing email addresses
-- Fix: Restrict to service role only and remove email exposure
-- =====================================================

-- Drop public access policy
DROP POLICY IF EXISTS "System can manage rate limits" ON public.auth_rate_limits;

-- Create service role only policy
CREATE POLICY "Service role can manage rate limits"
ON public.auth_rate_limits
FOR ALL
TO service_role
USING (true)
WITH CHECK (true);

-- Add hashed email column for secure lookups
ALTER TABLE public.auth_rate_limits 
ADD COLUMN IF NOT EXISTS hashed_email TEXT;

-- Create index on hashed_email for performance
CREATE INDEX IF NOT EXISTS idx_auth_rate_limits_hashed_email 
ON public.auth_rate_limits(hashed_email);

-- Remove plaintext email column to prevent exposure
ALTER TABLE public.auth_rate_limits 
DROP COLUMN IF EXISTS email;

-- =====================================================
-- FIX 3: Secure Database Views
-- Issue: Views have no RLS, allowing cross-company data access
-- Fix: Recreate views with security barriers and company filtering
-- =====================================================

-- Secure current_stock_levels view
DROP VIEW IF EXISTS public.current_stock_levels CASCADE;

CREATE VIEW public.current_stock_levels 
WITH (security_barrier = true)
AS
SELECT 
    it.company_id,
    it.product_id,
    it.warehouse_id,
    it.bin_id,
    SUM(it.quantity_change) as current_stock,
    COUNT(*) as transaction_count,
    MAX(it.transaction_date) as last_transaction_date
FROM public.inventory_transactions it
WHERE it.company_id = user_company_id()
GROUP BY it.company_id, it.product_id, it.warehouse_id, it.bin_id;

-- Recreate current_stock_with_aging with security
DROP VIEW IF EXISTS public.current_stock_with_aging CASCADE;

CREATE VIEW public.current_stock_with_aging
WITH (security_barrier = true)
AS
SELECT 
    csl.company_id,
    csl.product_id,
    csl.warehouse_id,
    csl.bin_id,
    csl.current_stock,
    csl.transaction_count,
    csl.last_transaction_date,
    aging.*
FROM current_stock_levels csl
CROSS JOIN LATERAL calculate_fifo_aging(csl.product_id, csl.warehouse_id, csl.bin_id) aging
WHERE csl.current_stock > 0
AND csl.company_id = user_company_id();

-- Secure credit_note_stats view
DROP VIEW IF EXISTS public.credit_note_stats CASCADE;

CREATE VIEW public.credit_note_stats
WITH (security_barrier = true)
AS
SELECT 
    company_id,
    COUNT(CASE WHEN status = 'Draft' THEN 1 END) as draft_count,
    COALESCE(SUM(CASE WHEN status = 'Draft' THEN total_amount ELSE 0 END), 0) as draft_amount,
    COUNT(CASE WHEN status = 'Confirmed' THEN 1 END) as confirmed_count,
    COALESCE(SUM(CASE WHEN status = 'Confirmed' THEN total_amount ELSE 0 END), 0) as confirmed_amount
FROM public.credit_notes
WHERE company_id = user_company_id()
GROUP BY company_id;

-- =====================================================
-- VERIFICATION NOTES
-- After applying this migration:
-- 1. Users can only see their own company's purchase orders
-- 2. auth_rate_limits is only accessible to service role
-- 3. All views properly filter by company_id
-- 4. Email addresses are no longer exposed in auth_rate_limits
-- 
-- Manual Step Required:
-- Enable "Leaked Password Protection" in Supabase Dashboard:
-- Authentication → Providers → Email → Password Security
-- =====================================================