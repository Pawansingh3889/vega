-- SPEC.md 3.1: an invoice has two states and one transition.
--
-- The inherited column allowed exactly one value, 'finalized', which meant
-- "this invoice is done" and nothing else: no draft to edit before issuing,
-- and no distinction between being prepared and being sent. Phase 3 drafting
-- needs the other state, and SPEC 3.1 names them 'draft' and 'issued' with a
-- one-way transition between them.
--
-- The inherited status machinery that keyed on 'finalized' is retargeted, not
-- deleted: process_sales_invoice (the stock movements an issue drives) and
-- handle_sales_invoice_status_change keep their behaviour, now on 'issued'.
-- The duplicate triggers the baseline carried are the exception:
--
--   trg_auto_generate_invoice_number      auto-numbering at 'finalized'
--   trigger_auto_generate_invoice_number  the same trigger, twice
--   trg_process_sales_invoice_status      AFTER, handle_sales_invoice_status_change
--   trigger_handle_sales_invoice_status_change  the same AFTER trigger, again
--   trg_sales_invoice_status_change       BEFORE, the same function a third time
--
-- The auto-numbering pair is replaced by issue-time allocation (issue #25).
-- The status-change trio ran the same inventory processing once via a broken
-- BEFORE trigger, then twice via two identical AFTER triggers, so one
-- retargeted AFTER trigger replaces all three and fires once, at draft to
-- issued. Numbering itself does not land here: #25 allocates at the same
-- transition, and until it does an issued invoice carries no number, which
-- the immutability migration following this one freezes as it finds it.

-- The function behind the retargeted trigger, first, so the data migration
-- below flips existing rows without any trigger watching it.
CREATE OR REPLACE FUNCTION public.handle_sales_invoice_status_change() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_result JSON;
BEGIN
    -- Process inventory when the invoice is issued, once, on the transition.
    IF (TG_OP = 'UPDATE' AND NEW.status = 'issued'
        AND OLD.status IS DISTINCT FROM 'issued') THEN

        SELECT public.process_sales_invoice(NEW.id) INTO v_result;

        -- Failures are logged, never swallowed silently (SECURITY.md N6).
        IF NOT (v_result ->> 'success')::boolean THEN
            RAISE WARNING 'Sales invoice processing failed for %: %',
                NEW.invoice_number, v_result ->> 'error';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.process_sales_invoice(p_invoice_id uuid) RETURNS json
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
        -- Only process an issued invoice. Drafts have not happened yet.
        IF invoice_record.status NOT IN ('issued') THEN
            RETURN json_build_object(
                'success', false,
                'error', 'Invoice status not eligible for processing',
                'status', invoice_record.status,
                'invoice_number', invoice_record.invoice_number
            );
        END IF;

        -- Check for missing warehouse_id on issued invoices
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
$$;

-- The five inherited triggers, before the value they key on disappears.
DROP TRIGGER IF EXISTS trg_auto_generate_invoice_number ON public.sales_invoices;
DROP TRIGGER IF EXISTS trigger_auto_generate_invoice_number ON public.sales_invoices;
DROP TRIGGER IF EXISTS trg_process_sales_invoice_status ON public.sales_invoices;
DROP TRIGGER IF EXISTS trigger_handle_sales_invoice_status_change ON public.sales_invoices;
DROP TRIGGER IF EXISTS trg_sales_invoice_status_change ON public.sales_invoices;

-- The lifecycle itself. Map first, then constrain: 'finalized' rows become
-- 'issued' because that is what the old value meant, and no existing row has
-- a state the new CHECK would refuse.
ALTER TABLE public.sales_invoices DROP CONSTRAINT IF EXISTS sales_invoices_status_check;
UPDATE public.sales_invoices SET status = 'issued' WHERE status = 'finalized';
ALTER TABLE public.sales_invoices
    ADD CONSTRAINT sales_invoices_status_check CHECK (status IN ('draft', 'issued'));
ALTER TABLE public.sales_invoices ALTER COLUMN status SET DEFAULT 'draft';

COMMENT ON COLUMN public.sales_invoices.status IS
  'draft: being prepared, editable, unnumbered. issued: sent, immutable, in the VAT return. The transition is one-way; corrections are credit notes (SPEC 3.1).';

COMMENT ON COLUMN public.sales_invoices.invoice_number IS
  'Allocated at issue (issue #25), NULL while draft. Never renumbered, never reused.';

-- One retargeted AFTER trigger, created after the data migration so the
-- mapping above does not re-run inventory processing for every old invoice.
CREATE TRIGGER trg_invoice_issued_process
AFTER UPDATE ON public.sales_invoices
FOR EACH ROW EXECUTE FUNCTION public.handle_sales_invoice_status_change();
