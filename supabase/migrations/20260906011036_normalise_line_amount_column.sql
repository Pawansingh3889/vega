-- One name for the pre-VAT amount on every line table: line_subtotal.
--
-- The inherited schema carried three spellings. Six line tables already say
-- line_subtotal, purchase_order_items says taxable_value and sales_order_items
-- says net_amount. Two names for one fact is the exact class of defect that
-- migration 0006 produced on sales_orders (delivery_postal_code and
-- delivery_postcode side by side) and 0012 had to repair, so the disagreement
-- goes now, before more line tables arrive and pick a side by accident.
--
-- Rename, not reshape: the column keeps its type, its default and its
-- nullability, because making it NOT NULL is a data decision this migration
-- has no business making. Tables with no pre-VAT amount column at all
-- (performa_invoice_items carries total_price, grn_line_items carries
-- line_total) are left alone: a goods receipt is not a VAT document, and
-- inventing a subtotal for one is a different change.
--
-- line_subtotal is the name kept, not taxable_value. Six of the eight tables
-- with the column already use it, the VAT module's sales query already reads
-- it, and "sub-total on this line, before VAT" is the plainer English.

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
    'return_order_lines',
    'backorder_items'
  ];
  has_line_subtotal boolean;
  has_legacy boolean;
  legacy_name text;
  stale int;
BEGIN
  FOREACH t IN ARRAY line_tables LOOP
    IF to_regclass('public.' || t) IS NULL THEN
      RAISE EXCEPTION 'expected line table public.% to exist', t;
    END IF;

    SELECT EXISTS (
             SELECT 1 FROM information_schema.columns
              WHERE table_schema = 'public' AND table_name = t
                AND column_name = 'line_subtotal'
           ),
           EXISTS (
             SELECT 1 FROM information_schema.columns
              WHERE table_schema = 'public' AND table_name = t
                AND column_name IN ('taxable_value', 'net_amount')
           )
      INTO has_line_subtotal, has_legacy;

    IF has_line_subtotal AND has_legacy THEN
      RAISE EXCEPTION
        'public.% holds line_subtotal and a legacy pre-VAT amount side by side; merging them needs a data decision, not a rename', t;
    ELSIF has_legacy THEN
      -- One legacy spelling or the other; both is impossible with a single
      -- rename, but the guard above would already have caught it.
      SELECT COALESCE(
               (SELECT 'taxable_value'
                  FROM information_schema.columns
                 WHERE table_schema = 'public' AND table_name = t
                   AND column_name = 'taxable_value'),
               'net_amount'
             )
        INTO legacy_name;

      EXECUTE format('ALTER TABLE public.%I RENAME COLUMN %I TO line_subtotal',
                     t, legacy_name);
    END IF;
  END LOOP;

  -- The migration ends by asserting the invariant it exists to protect: no
  -- line table carries a legacy pre-VAT amount name any more, so the VAT
  -- module can read every line table through one column name.
  FOREACH t IN ARRAY line_tables LOOP
    SELECT count(*) INTO stale
      FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name = t
       AND column_name IN ('taxable_value', 'net_amount');
    IF stale > 0 THEN
      RAISE EXCEPTION
        'line table public.% still carries a legacy pre-VAT amount column; the name is line_subtotal', t;
    END IF;
  END LOOP;
END
$$;
