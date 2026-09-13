-- Create function to get warehouse and bin-wise aging summary
CREATE OR REPLACE FUNCTION public.get_warehouse_bin_aging_summary(p_company_id uuid)
RETURNS TABLE(
  warehouse_name TEXT,
  bin_name TEXT,
  location_display TEXT,
  aging_0_30_value NUMERIC,
  aging_31_90_value NUMERIC,
  aging_91_180_value NUMERIC,
  aging_181_365_value NUMERIC,
  aging_365_plus_value NUMERIC,
  total_value NUMERIC,
  total_qty INTEGER
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = 'public'
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    COALESCE(w.name, 'Unknown') as warehouse_name,
    COALESCE(wb.bin_name, 'No Bin') as bin_name,
    CONCAT(COALESCE(w.name, 'Unknown'), ' - ', COALESCE(wb.bin_name, 'No Bin')) as location_display,
    COALESCE(SUM(csa.aging_0_30_value), 0) as aging_0_30_value,
    COALESCE(SUM(csa.aging_31_90_value), 0) as aging_31_90_value,
    COALESCE(SUM(csa.aging_91_180_value), 0) as aging_91_180_value,
    COALESCE(SUM(csa.aging_181_365_value), 0) as aging_181_365_value,
    COALESCE(SUM(csa.aging_365_plus_value), 0) as aging_365_plus_value,
    COALESCE(SUM(
      COALESCE(csa.aging_0_30_value, 0) + 
      COALESCE(csa.aging_31_90_value, 0) + 
      COALESCE(csa.aging_91_180_value, 0) + 
      COALESCE(csa.aging_181_365_value, 0) + 
      COALESCE(csa.aging_365_plus_value, 0)
    ), 0) as total_value,
    COALESCE(SUM(csa.current_stock)::INTEGER, 0) as total_qty
  FROM public.current_stock_with_aging csa
  LEFT JOIN public.warehouses w ON w.id = csa.warehouse_id
  LEFT JOIN public.warehouse_bins wb ON wb.id = csa.bin_id
  WHERE csa.company_id = p_company_id
    AND csa.current_stock > 0
  GROUP BY w.name, wb.bin_name
  ORDER BY warehouse_name, bin_name;
END;
$$;