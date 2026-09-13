-- Remove sales order status update from process_sales_invoice function
-- The SO status should NOT change automatically when an invoice is generated
CREATE OR REPLACE FUNCTION public.process_sales_invoice(p_invoice_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    invoice_record RECORD;
    item_record RECORD;
    v_items_processed INTEGER := 0;
    v_transactions_created INTEGER := 0;
    error_msg TEXT;
    result JSON;
    missing_warehouse_items TEXT := '';
BEGIN
    -- Load invoice record
    SELECT * INTO invoice_record FROM public.sales_invoices WHERE id = p_invoice_id;
    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Sales invoice not found',
            'invoice_id', p_invoice_id
        );
    END IF;

    BEGIN
        -- Only process when invoice is finalized
        IF invoice_record.status NOT IN ('finalized') THEN
            RETURN json_build_object(
                'success', false,
                'error', 'Invoice status not eligible for processing',
                'status', invoice_record.status,
                'invoice_number', invoice_record.invoice_number
            );
        END IF;

        -- Check for missing warehouse_id in finalized invoices
        SELECT string_agg(sii.item_description, ', ')
        INTO missing_warehouse_items
        FROM public.sales_invoice_items sii
        WHERE sii.sales_invoice_id = p_invoice_id 
        AND sii.warehouse_id IS NULL;

        IF missing_warehouse_items IS NOT NULL AND missing_warehouse_items != '' THEN
            RETURN json_build_object(
                'success', false,
                'error', 'Missing warehouse information for items: ' || missing_warehouse_items,
                'invoice_number', invoice_record.invoice_number
            );
        END IF;

        -- Process each invoice item
        FOR item_record IN 
            SELECT * FROM public.sales_invoice_items WHERE sales_invoice_id = p_invoice_id
        LOOP
            v_items_processed := v_items_processed + 1;
            
            -- Update product stock (reduce by invoiced quantity)
            UPDATE public.products 
            SET stock_quantity = stock_quantity - item_record.quantity_invoiced,
                updated_at = now()
            WHERE id = item_record.product_id;

            -- Record inventory transaction for sales invoice
            PERFORM public.record_inventory_transaction(
                invoice_record.company_id,
                'sales_invoice'::transaction_type,
                invoice_record.id,
                invoice_record.invoice_number,
                item_record.product_id,
                item_record.warehouse_id,
                item_record.bin_id,
                -item_record.quantity_invoiced, -- negative for sales
                item_record.unit_price,
                'Sales Invoice - ' || invoice_record.invoice_number,
                NULL -- created_by: use session user (auth.uid())
            );
            
            v_transactions_created := v_transactions_created + 1;
        END LOOP;

        -- NOTE: We no longer update sales order status here
        -- Sales order status must be managed independently

        result := json_build_object(
            'success', true,
            'invoice_number', invoice_record.invoice_number,
            'items_processed', v_items_processed,
            'transactions_created', v_transactions_created
        );

    EXCEPTION WHEN OTHERS THEN
        error_msg := SQLERRM;
        result := json_build_object(
            'success', false,
            'error', error_msg,
            'invoice_number', invoice_record.invoice_number,
            'items_processed', v_items_processed,
            'transactions_created', v_transactions_created
        );
    END;

    RETURN result;
END;
$function$;