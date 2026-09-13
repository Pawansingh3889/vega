-- Add aging_status column to current_stock_with_aging view
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
    aging.total_current_value,
    -- Calculate aging status based on weighted average age
    CASE 
        WHEN aging.weighted_avg_age_days <= 30 THEN 'Fresh'
        WHEN aging.weighted_avg_age_days <= 90 THEN 'Good'
        WHEN aging.weighted_avg_age_days <= 180 THEN 'Aging'
        WHEN aging.weighted_avg_age_days <= 365 THEN 'Slow'
        ELSE 'Dead'
    END as aging_status
FROM current_stock_levels csl
CROSS JOIN LATERAL calculate_fifo_aging(csl.product_id, csl.warehouse_id, csl.bin_id) aging
WHERE csl.current_stock > 0
AND csl.company_id = user_company_id();