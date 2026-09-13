-- Fix: Add VOLATILE to get_cumulative_received_quantity function to allow UPDATE operations
CREATE OR REPLACE FUNCTION get_cumulative_received_quantity(p_purchase_order_id uuid, p_product_id uuid)
RETURNS integer
LANGUAGE plpgsql
VOLATILE  -- Mark as VOLATILE to allow UPDATE operations when called from other functions
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
    total_received integer := 0;
BEGIN
    -- Get total received quantity from all accepted GRNs for this PO and product
    SELECT COALESCE(SUM(gli.accepted_quantity), 0)
    INTO total_received
    FROM public.grn_line_items gli
    JOIN public.grn_header gh ON gli.grn_header_id = gh.id
    WHERE gh.purchase_order_id = p_purchase_order_id
      AND gli.product_id = p_product_id
      AND gh.status IN ('accepted', 'partially_received', 'received');
    
    RETURN total_received;
END;
$$;