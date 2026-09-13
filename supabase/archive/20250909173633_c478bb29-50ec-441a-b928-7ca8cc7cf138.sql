-- Fix PO status: should be 'closed' when fully received, not 'received'
CREATE OR REPLACE FUNCTION public.update_purchase_order_quantities_from_grn(p_grn_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
    grn_record RECORD;
    item_record RECORD;
    cumulative_received integer;
    new_pending_qty integer;
    total_pending_qty integer := 0;
    po_status text;
BEGIN
    -- Get GRN header information
    SELECT * INTO grn_record
    FROM public.grn_header
    WHERE id = p_grn_id;

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'GRN not found');
    END IF;

    -- Only process if GRN is in accepted/received status
    IF grn_record.status NOT IN ('accepted', 'partially_received', 'received') THEN
        RETURN json_build_object('success', false, 'error', 'GRN not in processable status');
    END IF;

    -- Update purchase order items based on GRN line items
    FOR item_record IN
        SELECT gli.*, poi.quantity as ordered_quantity
        FROM public.grn_line_items gli
        JOIN public.purchase_order_items poi ON poi.purchase_order_id = grn_record.purchase_order_id 
                                             AND poi.product_id = gli.product_id
        WHERE gli.grn_header_id = p_grn_id
    LOOP
        -- Get cumulative received quantity for this product across all GRNs
        SELECT public.get_cumulative_received_quantity(grn_record.purchase_order_id, item_record.product_id)
        INTO cumulative_received;

        -- Calculate new pending quantity
        new_pending_qty := GREATEST(0, item_record.ordered_quantity - cumulative_received);

        -- Update purchase order item
        UPDATE public.purchase_order_items
        SET 
            received_quantity = cumulative_received,
            pending_quantity = new_pending_qty
        WHERE purchase_order_id = grn_record.purchase_order_id
          AND product_id = item_record.product_id;
    END LOOP;

    -- Calculate total pending quantity for the entire PO to determine status
    SELECT COALESCE(SUM(pending_quantity), 0)
    INTO total_pending_qty
    FROM public.purchase_order_items
    WHERE purchase_order_id = grn_record.purchase_order_id;

    -- Determine new PO status - FIXED: should be 'closed' when fully received
    IF total_pending_qty = 0 THEN
        po_status := 'closed';
    ELSE
        -- Check if any items have been received
        IF EXISTS (
            SELECT 1 FROM public.purchase_order_items 
            WHERE purchase_order_id = grn_record.purchase_order_id 
              AND received_quantity > 0
        ) THEN
            po_status := 'partially_received';
        ELSE
            po_status := 'approved';
        END IF;
    END IF;

    -- Update purchase order status
    UPDATE public.purchase_orders
    SET 
        status = po_status,
        updated_at = now()
    WHERE id = grn_record.purchase_order_id;

    RETURN json_build_object(
        'success', true, 
        'po_status', po_status,
        'total_pending_qty', total_pending_qty
    );
END;
$$;