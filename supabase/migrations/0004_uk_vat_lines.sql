-- Replace the India GST triple with a single UK VAT treatment on every line.
--
-- The inherited schema carries cgst/sgst/igst rate and amount pairs on eight
-- line-item tables, which is India's split between central, state and
-- integrated GST. The UK has one VAT, so the six columns collapse to three: the
-- treatment that applied, the rate it resolved to, and the amount.
--
-- The rate is stored alongside the treatment deliberately. A treatment resolves
-- to a rate through vat_rates by date, and re-resolving it at read time would
-- silently restate an issued document after a rate change.

DO $$
DECLARE
  t text;
  line_tables text[] := ARRAY[
    'sales_invoice_items',
    'sales_order_items',
    'purchase_order_items',
    'credit_note_items',
    'debit_note_items',
    'supplier_credit_note_items',
    'performa_invoice_items',
    'grn_line_items',
    'return_order_lines'
  ];
BEGIN
  FOREACH t IN ARRAY line_tables LOOP
    IF to_regclass('public.' || t) IS NULL THEN
      RAISE EXCEPTION 'expected line table public.% to exist', t;
    END IF;

    EXECUTE format($f$
      ALTER TABLE public.%I
        ADD COLUMN IF NOT EXISTS vat_treatment_code text
          NOT NULL DEFAULT 'STD' REFERENCES public.vat_treatments(code),
        ADD COLUMN IF NOT EXISTS vat_rate   numeric(5,2) NOT NULL DEFAULT 0,
        ADD COLUMN IF NOT EXISTS vat_amount numeric(12,2) NOT NULL DEFAULT 0
    $f$, t);

    -- The India columns go. Nothing in a UK filing can use them, and leaving
    -- them invites a report that quietly sums the wrong thing.
    EXECUTE format($f$
      ALTER TABLE public.%I
        DROP COLUMN IF EXISTS cgst_rate,   DROP COLUMN IF EXISTS cgst_amount,
        DROP COLUMN IF EXISTS sgst_rate,   DROP COLUMN IF EXISTS sgst_amount,
        DROP COLUMN IF EXISTS igst_rate,   DROP COLUMN IF EXISTS igst_amount,
        DROP COLUMN IF EXISTS gst_rate
    $f$, t);

    EXECUTE format(
      'CREATE INDEX IF NOT EXISTS %I ON public.%I (vat_treatment_code)',
      t || '_vat_treatment_idx', t);
  END LOOP;
END
$$;

-- products.gst_percentage becomes a default treatment, not a default rate. A
-- product is zero rated because of what it is, and the percentage follows.
ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS default_vat_treatment_code text
    NOT NULL DEFAULT 'STD' REFERENCES public.vat_treatments(code);
ALTER TABLE public.products DROP COLUMN IF EXISTS gst_percentage;

COMMENT ON COLUMN public.products.default_vat_treatment_code IS
  'Suggested treatment when this product is added to a document. The document line owns the treatment that actually applied.';
