-- Create backorder_items table
CREATE TABLE public.backorder_items (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  company_id UUID NOT NULL,
  customer_id UUID NOT NULL,
  product_id UUID NOT NULL,
  quantity_backordered INTEGER NOT NULL DEFAULT 0,
  original_sales_order_id UUID,
  original_order_item_id UUID,
  warehouse_id UUID,
  bin_id UUID,
  unit_price NUMERIC NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'pending',
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  created_by UUID NOT NULL DEFAULT auth.uid()
);

-- Enable RLS
ALTER TABLE public.backorder_items ENABLE ROW LEVEL SECURITY;

-- Create RLS policy
CREATE POLICY "Company isolation for backorder_items" 
ON public.backorder_items 
FOR ALL 
USING (company_id = user_company_id())
WITH CHECK (company_id = user_company_id());

-- Add updated_at trigger
CREATE TRIGGER update_backorder_items_updated_at
BEFORE UPDATE ON public.backorder_items
FOR EACH ROW
EXECUTE FUNCTION public.set_current_timestamp_updated_at();

-- Function to get backorder summary with available stock
CREATE OR REPLACE FUNCTION public.get_backorder_summary(p_company_id UUID)
RETURNS TABLE(
  customer_id UUID,
  customer_name TEXT,
  product_id UUID,
  product_name TEXT,
  product_sku TEXT,
  total_backordered INTEGER,
  current_stock INTEGER,
  ready_to_deliver INTEGER,
  available_to_process INTEGER,
  avg_unit_price NUMERIC,
  oldest_backorder_date TIMESTAMP WITH TIME ZONE
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    bi.customer_id,
    c.name as customer_name,
    bi.product_id,
    p.name as product_name,
    p.sku as product_sku,
    SUM(bi.quantity_backordered)::INTEGER as total_backordered,
    p.stock_quantity as current_stock,
    COALESCE(rtd.ready_to_deliver, 0)::INTEGER as ready_to_deliver,
    GREATEST(0, p.stock_quantity - COALESCE(rtd.ready_to_deliver, 0))::INTEGER as available_to_process,
    AVG(bi.unit_price) as avg_unit_price,
    MIN(bi.created_at) as oldest_backorder_date
  FROM public.backorder_items bi
  JOIN public.customers c ON bi.customer_id = c.id
  JOIN public.products p ON bi.product_id = p.id
  LEFT JOIN (
    SELECT 
      soi.product_id,
      SUM(COALESCE(soi.ordered_quantity, soi.quantity) - COALESCE(soi.back_order_quantity, 0)) as ready_to_deliver
    FROM public.sales_order_items soi
    JOIN public.sales_orders so ON soi.sales_order_id = so.id
    WHERE so.company_id = p_company_id 
      AND so.status IN ('confirmed', 'partially_delivered')
    GROUP BY soi.product_id
  ) rtd ON bi.product_id = rtd.product_id
  WHERE bi.company_id = p_company_id 
    AND bi.status = 'pending'
  GROUP BY 
    bi.customer_id, c.name, bi.product_id, p.name, p.sku, 
    p.stock_quantity, rtd.ready_to_deliver
  ORDER BY oldest_backorder_date ASC;
END;
$$;

-- Function to process backorder fulfillment
CREATE OR REPLACE FUNCTION public.process_backorder_fulfillment(
  p_backorder_ids UUID[],
  p_company_id UUID,
  p_created_by UUID DEFAULT auth.uid()
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_result JSON;
  v_customer_orders RECORD;
  v_new_order_id UUID;
  v_processed_count INTEGER := 0;
  v_total_value NUMERIC := 0;
BEGIN
  -- Group backorders by customer and create sales orders
  FOR v_customer_orders IN
    SELECT 
      bi.customer_id,
      c.name as customer_name,
      c.email as customer_email,
      c.phone as customer_phone,
      c.address as customer_address,
      array_agg(bi.id) as backorder_item_ids,
      array_agg(bi.product_id) as product_ids,
      array_agg(bi.quantity_backordered) as quantities,
      array_agg(bi.unit_price) as unit_prices,
      SUM(bi.quantity_backordered * bi.unit_price) as order_total
    FROM public.backorder_items bi
    JOIN public.customers c ON bi.customer_id = c.id
    WHERE bi.id = ANY(p_backorder_ids)
      AND bi.company_id = p_company_id
      AND bi.status = 'pending'
    GROUP BY bi.customer_id, c.name, c.email, c.phone, c.address
  LOOP
    -- Create new sales order
    INSERT INTO public.sales_orders (
      company_id,
      customer_id,
      customer_name,
      customer_email,
      customer_phone,
      shipping_address,
      order_date,
      status,
      total_amount,
      subtotal_amount,
      created_by
    ) VALUES (
      p_company_id,
      v_customer_orders.customer_id,
      v_customer_orders.customer_name,
      v_customer_orders.customer_email,
      v_customer_orders.customer_phone,
      v_customer_orders.customer_address,
      CURRENT_DATE,
      'confirmed',
      v_customer_orders.order_total,
      v_customer_orders.order_total,
      p_created_by
    ) RETURNING id INTO v_new_order_id;

    -- Create sales order items
    FOR i IN 1..array_length(v_customer_orders.product_ids, 1) LOOP
      INSERT INTO public.sales_order_items (
        sales_order_id,
        product_id,
        quantity,
        ordered_quantity,
        unit_price,
        total_price
      ) 
      SELECT 
        v_new_order_id,
        v_customer_orders.product_ids[i],
        v_customer_orders.quantities[i],
        v_customer_orders.quantities[i],
        v_customer_orders.unit_prices[i],
        v_customer_orders.quantities[i] * v_customer_orders.unit_prices[i];
    END LOOP;

    -- Update backorder items to fulfilled
    UPDATE public.backorder_items 
    SET status = 'fulfilled', updated_at = now()
    WHERE id = ANY(v_customer_orders.backorder_item_ids);

    v_processed_count := v_processed_count + array_length(v_customer_orders.backorder_item_ids, 1);
    v_total_value := v_total_value + v_customer_orders.order_total;
  END LOOP;

  v_result := json_build_object(
    'success', true,
    'processed_count', v_processed_count,
    'total_value', v_total_value,
    'orders_created', (SELECT COUNT(*) FROM unnest(p_backorder_ids))
  );

  RETURN v_result;
END;
$$;