-- Commodity codes replace HSN codes.
--
-- HSN is India's classification. The UK and EU use the Harmonised System, and
-- the code sits in Phase 1 rather than with the customs work because CBAM and
-- the product passport both join on it. SPEC.md section 4.1.

ALTER TABLE public.products RENAME COLUMN hsn_code TO commodity_code;
COMMENT ON COLUMN public.products.commodity_code IS
  'Harmonised System commodity code. Required for export documentation, and the join CBAM and the Digital Product Passport both use.';

DO $$
DECLARE
  t text;
  line_tables text[] := ARRAY[
    'sales_invoice_items', 'sales_order_items', 'purchase_order_items',
    'credit_note_items', 'debit_note_items', 'supplier_credit_note_items',
    'performa_invoice_items', 'grn_line_items', 'return_order_lines'
  ];
BEGIN
  FOREACH t IN ARRAY line_tables LOOP
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
       WHERE table_schema = 'public' AND table_name = t AND column_name = 'hsn_sac_code'
    ) THEN
      EXECUTE format('ALTER TABLE public.%I RENAME COLUMN hsn_sac_code TO commodity_code', t);
    END IF;
  END LOOP;
END
$$;

DO $$
DECLARE leftovers text;
BEGIN
  SELECT string_agg(table_name || '.' || column_name, ', ')
    INTO leftovers FROM information_schema.columns
   WHERE table_schema = 'public' AND column_name LIKE '%hsn%';
  IF leftovers IS NOT NULL THEN
    RAISE EXCEPTION 'HSN columns still present: %', leftovers;
  END IF;
END
$$;
