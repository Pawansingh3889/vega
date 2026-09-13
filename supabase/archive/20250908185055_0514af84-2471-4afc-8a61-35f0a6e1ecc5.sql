-- Create FIFO aging calculation function
CREATE OR REPLACE FUNCTION public.calculate_fifo_aging(
  p_product_id UUID,
  p_warehouse_id UUID,
  p_bin_id UUID DEFAULT NULL
) RETURNS TABLE(
  aging_0_30_qty INTEGER,
  aging_0_30_value NUMERIC,
  aging_31_90_qty INTEGER,
  aging_31_90_value NUMERIC,
  aging_91_180_qty INTEGER,
  aging_91_180_value NUMERIC,
  aging_181_365_qty INTEGER,
  aging_181_365_value NUMERIC,
  aging_365_plus_qty INTEGER,
  aging_365_plus_value NUMERIC,
  weighted_avg_age_days INTEGER,
  total_current_qty INTEGER,
  total_current_value NUMERIC
) LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  rec RECORD;
  remaining_qty INTEGER := 0;
  current_batch_qty INTEGER;
  days_old INTEGER;
  batch_value NUMERIC;
  allocated_qty INTEGER;
  allocated_value NUMERIC;
  total_age_weighted NUMERIC := 0;
  total_qty_for_avg INTEGER := 0;
BEGIN
  -- Initialize return values
  aging_0_30_qty := 0;
  aging_0_30_value := 0;
  aging_31_90_qty := 0;
  aging_31_90_value := 0;
  aging_91_180_qty := 0;
  aging_91_180_value := 0;
  aging_181_365_qty := 0;
  aging_181_365_value := 0;
  aging_365_plus_qty := 0;
  aging_365_plus_value := 0;
  weighted_avg_age_days := 0;
  total_current_qty := 0;
  total_current_value := 0;

  -- Get current stock level
  SELECT COALESCE(SUM(quantity_change), 0) INTO total_current_qty
  FROM inventory_transactions
  WHERE product_id = p_product_id 
    AND warehouse_id = p_warehouse_id
    AND (p_bin_id IS NULL OR bin_id = p_bin_id);

  -- If no current stock, return zeros
  IF total_current_qty <= 0 THEN
    RETURN QUERY SELECT aging_0_30_qty, aging_0_30_value, aging_31_90_qty, aging_31_90_value,
                        aging_91_180_qty, aging_91_180_value, aging_181_365_qty, aging_181_365_value,
                        aging_365_plus_qty, aging_365_plus_value, weighted_avg_age_days, 
                        total_current_qty, total_current_value;
    RETURN;
  END IF;

  -- Process transactions in FIFO order (oldest first)
  remaining_qty := total_current_qty;
  
  FOR rec IN
    SELECT 
      transaction_date,
      quantity_change,
      unit_cost,
      transaction_type
    FROM inventory_transactions
    WHERE product_id = p_product_id 
      AND warehouse_id = p_warehouse_id
      AND (p_bin_id IS NULL OR bin_id = p_bin_id)
      AND quantity_change > 0  -- Only positive transactions (receipts)
    ORDER BY transaction_date ASC
  LOOP
    -- Calculate days old
    days_old := EXTRACT(DAY FROM (now() - rec.transaction_date))::INTEGER;
    
    -- Determine how much of this batch is still in current stock
    current_batch_qty := LEAST(remaining_qty, rec.quantity_change);
    batch_value := current_batch_qty * COALESCE(rec.unit_cost, 0);
    
    IF current_batch_qty > 0 THEN
      -- Add to appropriate aging bucket
      IF days_old <= 30 THEN
        aging_0_30_qty := aging_0_30_qty + current_batch_qty;
        aging_0_30_value := aging_0_30_value + batch_value;
      ELSIF days_old <= 90 THEN
        aging_31_90_qty := aging_31_90_qty + current_batch_qty;
        aging_31_90_value := aging_31_90_value + batch_value;
      ELSIF days_old <= 180 THEN
        aging_91_180_qty := aging_91_180_qty + current_batch_qty;
        aging_91_180_value := aging_91_180_value + batch_value;
      ELSIF days_old <= 365 THEN
        aging_181_365_qty := aging_181_365_qty + current_batch_qty;
        aging_181_365_value := aging_181_365_value + batch_value;
      ELSE
        aging_365_plus_qty := aging_365_plus_qty + current_batch_qty;
        aging_365_plus_value := aging_365_plus_value + batch_value;
      END IF;
      
      -- Calculate weighted average age
      total_age_weighted := total_age_weighted + (days_old * current_batch_qty);
      total_qty_for_avg := total_qty_for_avg + current_batch_qty;
      
      remaining_qty := remaining_qty - current_batch_qty;
    END IF;
    
    -- Exit if we've allocated all current stock
    EXIT WHEN remaining_qty <= 0;
  END LOOP;

  -- Calculate totals and weighted average
  total_current_value := aging_0_30_value + aging_31_90_value + aging_91_180_value + aging_181_365_value + aging_365_plus_value;
  
  IF total_qty_for_avg > 0 THEN
    weighted_avg_age_days := (total_age_weighted / total_qty_for_avg)::INTEGER;
  END IF;

  RETURN QUERY SELECT aging_0_30_qty, aging_0_30_value, aging_31_90_qty, aging_31_90_value,
                      aging_91_180_qty, aging_91_180_value, aging_181_365_qty, aging_181_365_value,
                      aging_365_plus_qty, aging_365_plus_value, weighted_avg_age_days, 
                      total_current_qty, total_current_value;
END;
$$;

-- Create enhanced current stock view with aging
CREATE OR REPLACE VIEW public.current_stock_with_aging AS
SELECT 
  csl.*,
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
  CASE 
    WHEN aging.weighted_avg_age_days <= 30 THEN 'Fresh'
    WHEN aging.weighted_avg_age_days <= 90 THEN 'Good'
    WHEN aging.weighted_avg_age_days <= 180 THEN 'Aging'
    WHEN aging.weighted_avg_age_days <= 365 THEN 'Slow'
    ELSE 'Dead'
  END as aging_status
FROM current_stock_levels csl
CROSS JOIN LATERAL public.calculate_fifo_aging(csl.product_id, csl.warehouse_id, csl.bin_id) aging
WHERE csl.current_stock > 0;

-- Create company-level aging summary function
CREATE OR REPLACE FUNCTION public.get_company_aging_summary(p_company_id UUID)
RETURNS TABLE(
  total_skus INTEGER,
  total_qty BIGINT,
  total_value NUMERIC,
  aging_0_30_qty BIGINT,
  aging_0_30_value NUMERIC,
  aging_31_90_qty BIGINT,
  aging_31_90_value NUMERIC,
  aging_91_180_qty BIGINT,
  aging_91_180_value NUMERIC,
  aging_181_365_qty BIGINT,
  aging_181_365_value NUMERIC,
  aging_365_plus_qty BIGINT,
  aging_365_plus_value NUMERIC,
  dead_stock_skus INTEGER,
  dead_stock_value NUMERIC
) LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    COUNT(DISTINCT csa.product_id)::INTEGER as total_skus,
    COALESCE(SUM(csa.current_stock), 0) as total_qty,
    COALESCE(SUM(csa.aging_0_30_value + csa.aging_31_90_value + csa.aging_91_180_value + csa.aging_181_365_value + csa.aging_365_plus_value), 0) as total_value,
    COALESCE(SUM(csa.aging_0_30_qty), 0) as aging_0_30_qty,
    COALESCE(SUM(csa.aging_0_30_value), 0) as aging_0_30_value,
    COALESCE(SUM(csa.aging_31_90_qty), 0) as aging_31_90_qty,
    COALESCE(SUM(csa.aging_31_90_value), 0) as aging_31_90_value,
    COALESCE(SUM(csa.aging_91_180_qty), 0) as aging_91_180_qty,
    COALESCE(SUM(csa.aging_91_180_value), 0) as aging_91_180_value,
    COALESCE(SUM(csa.aging_181_365_qty), 0) as aging_181_365_qty,
    COALESCE(SUM(csa.aging_181_365_value), 0) as aging_181_365_value,
    COALESCE(SUM(csa.aging_365_plus_qty), 0) as aging_365_plus_qty,
    COALESCE(SUM(csa.aging_365_plus_value), 0) as aging_365_plus_value,
    COUNT(CASE WHEN csa.aging_status = 'Dead' THEN 1 END)::INTEGER as dead_stock_skus,
    COALESCE(SUM(CASE WHEN csa.aging_status = 'Dead' THEN csa.aging_365_plus_value ELSE 0 END), 0) as dead_stock_value
  FROM current_stock_with_aging csa
  WHERE csa.company_id = p_company_id;
END;
$$;