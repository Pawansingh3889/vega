-- Create function to get cumulative received quantity for a purchase order item
CREATE OR REPLACE FUNCTION get_cumulative_received_quantity(p_purchase_order_id uuid, p_product_id uuid)
RETURNS integer
LANGUAGE plpgsql
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

-- Create function to update purchase order items when GRN is processed
CREATE OR REPLACE FUNCTION update_purchase_order_quantities_from_grn(p_grn_id uuid)
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
        SELECT get_cumulative_received_quantity(grn_record.purchase_order_id, item_record.product_id)
        INTO cumulative_received;

        -- Calculate new pending quantity
        new_pending_qty := GREATEST(0, item_record.ordered_quantity - cumulative_received);

        -- Update purchase order item
        UPDATE public.purchase_order_items
        SET 
            received_quantity = cumulative_received,
            pending_quantity = new_pending_qty,
            updated_at = now()
        WHERE purchase_order_id = grn_record.purchase_order_id
          AND product_id = item_record.product_id;
    END LOOP;

    -- Calculate total pending quantity for the entire PO to determine status
    SELECT COALESCE(SUM(pending_quantity), 0)
    INTO total_pending_qty
    FROM public.purchase_order_items
    WHERE purchase_order_id = grn_record.purchase_order_id;

    -- Determine new PO status
    IF total_pending_qty = 0 THEN
        po_status := 'received';
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

-- Create trigger function to automatically update PO quantities when GRN status changes
CREATE OR REPLACE FUNCTION trigger_update_po_from_grn()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
BEGIN
    -- Only trigger when GRN status changes to accepted/received states
    IF (TG_OP = 'UPDATE' AND NEW.status IN ('accepted', 'partially_received', 'received') 
        AND (OLD.status IS NULL OR OLD.status != NEW.status)) 
    OR (TG_OP = 'INSERT' AND NEW.status IN ('accepted', 'partially_received', 'received')) THEN
        
        PERFORM update_purchase_order_quantities_from_grn(NEW.id);
    END IF;
    
    RETURN NEW;
END;
$$;

-- Create trigger on grn_header table
DROP TRIGGER IF EXISTS trg_update_po_quantities_on_grn_status ON public.grn_header;
CREATE TRIGGER trg_update_po_quantities_on_grn_status
    AFTER INSERT OR UPDATE ON public.grn_header
    FOR EACH ROW
    EXECUTE FUNCTION trigger_update_po_from_grn();

-- Create trigger on grn_line_items to update when quantities change
CREATE OR REPLACE FUNCTION trigger_update_po_from_grn_items()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
    grn_header_record RECORD;
BEGIN
    -- Get GRN header information
    SELECT * INTO grn_header_record
    FROM public.grn_header
    WHERE id = COALESCE(NEW.grn_header_id, OLD.grn_header_id);

    -- Only update if GRN is in accepted/received status
    IF grn_header_record.status IN ('accepted', 'partially_received', 'received') THEN
        PERFORM update_purchase_order_quantities_from_grn(grn_header_record.id);
    END IF;
    
    RETURN COALESCE(NEW, OLD);
END;
$$;

-- Create trigger on grn_line_items table
DROP TRIGGER IF EXISTS trg_update_po_quantities_on_grn_items ON public.grn_line_items;
CREATE TRIGGER trg_update_po_quantities_on_grn_items
    AFTER INSERT OR UPDATE OR DELETE ON public.grn_line_items
    FOR EACH ROW
    EXECUTE FUNCTION trigger_update_po_from_grn_items();