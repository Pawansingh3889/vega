-- Update existing purchase orders with correct totals calculated from their items
UPDATE public.purchase_orders 
SET 
  subtotal_amount = COALESCE(item_totals.subtotal, 0),
  total_discount_amount = COALESCE(item_totals.discount, 0), 
  total_tax_amount = COALESCE(item_totals.tax, 0),
  total_amount = COALESCE(item_totals.total, 0),
  updated_at = now()
FROM (
  SELECT 
    poi.purchase_order_id,
    SUM(COALESCE(poi.taxable_value, poi.quantity * poi.unit_price - COALESCE(poi.discount_amount, 0))) as subtotal,
    SUM(COALESCE(poi.discount_amount, 0)) as discount,
    SUM(COALESCE(poi.cgst_amount, 0) + COALESCE(poi.sgst_amount, 0) + COALESCE(poi.igst_amount, 0)) as tax,
    SUM(COALESCE(poi.total_price, poi.quantity * poi.unit_price)) as total
  FROM public.purchase_order_items poi
  GROUP BY poi.purchase_order_id
) as item_totals
WHERE public.purchase_orders.id = item_totals.purchase_order_id;