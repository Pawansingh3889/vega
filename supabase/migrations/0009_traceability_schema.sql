-- Batch traceability: structure only, no behaviour.
--
-- PROBLEM.md names small UK food manufacturers as the wedge, and their binding
-- constraint is that retained EU law 178/2002 Article 18 requires one step back
-- and one step forward for everything they handle. The inherited schema has
-- almost nothing for it: 2 of the 344 migrations mention a batch at all.
--
-- WHY NOW, GIVEN THE HYPOTHESIS IS UNTESTED. The columns are cheap and the
-- retrofit is not. Adding a batch reference to stock, delivery and invoice lines
-- later means every movement, despatch, report and policy learns about batches
-- after they already hold data. The cost ratio is roughly fifty to one, which is
-- enough to justify the tables without believing the wedge.
--
-- WHAT IS DELIBERATELY ABSENT. No movement logic, no splits or merges, no
-- shelf-life alerting, no mass balance, no UI. Those wait for discovery to say
-- the wedge is real. This migration only makes sure nothing has to be reshaped
-- if it is.

CREATE TABLE public.batches (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id       uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  product_id       uuid NOT NULL REFERENCES public.products(id),

  -- The manufacturer's own identifier, as printed. Unique per product per
  -- company, because that is the promise a traceability exercise relies on.
  batch_code       text NOT NULL,
  -- Some operations carry a finer lot inside a batch. Nullable: most do not.
  lot_code         text,

  manufactured_on  date,
  -- Best before is quality, use by is safety. They are different obligations and
  -- a single "expiry" column loses which one applied.
  best_before_on   date,
  use_by_on        date,

  quantity_received numeric(14,3) NOT NULL DEFAULT 0,
  unit_of_measure   text NOT NULL DEFAULT 'kg',

  -- One step back: where this batch came from.
  supplier_id       uuid REFERENCES public.suppliers(id),
  supplier_batch_code text,
  country_of_origin text,

  status            text NOT NULL DEFAULT 'available',
  created_at        timestamp with time zone NOT NULL DEFAULT now(),
  updated_at        timestamp with time zone NOT NULL DEFAULT now(),

  CONSTRAINT batches_status_known CHECK (status IN ('available','quarantined','released','rejected','consumed','recalled')),
  CONSTRAINT batches_quantity_sane CHECK (quantity_received >= 0),
  CONSTRAINT batches_dates_ordered CHECK (
    (best_before_on IS NULL OR manufactured_on IS NULL OR best_before_on >= manufactured_on) AND
    (use_by_on      IS NULL OR manufactured_on IS NULL OR use_by_on      >= manufactured_on)
  )
);

CREATE UNIQUE INDEX batches_code_unique_per_product
  ON public.batches (company_id, product_id, batch_code, COALESCE(lot_code, ''));
CREATE INDEX batches_company_product ON public.batches (company_id, product_id);
CREATE INDEX batches_expiry          ON public.batches (company_id, use_by_on) WHERE use_by_on IS NOT NULL;

COMMENT ON TABLE public.batches IS
  'One physical batch or lot. Structure only in Phase 1: nothing writes to it yet.';

-- One step forward: where it went. An append-only ledger of quantity leaving or
-- entering a batch, pointing at whatever document caused it.
CREATE TABLE public.batch_movements (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id     uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  batch_id       uuid NOT NULL REFERENCES public.batches(id),

  movement_type  text NOT NULL,
  -- Signed: positive receives into the batch, negative issues out of it.
  quantity       numeric(14,3) NOT NULL,
  occurred_at    timestamp with time zone NOT NULL DEFAULT now(),

  -- Deliberately a loose reference rather than nine nullable foreign keys. The
  -- causing document can be a receipt, a despatch, an adjustment or a transfer,
  -- and a polymorphic pair keeps the ledger readable.
  source_table   text,
  source_id      uuid,

  note           text,
  created_at     timestamp with time zone NOT NULL DEFAULT now(),

  CONSTRAINT batch_movements_type_known CHECK (
    movement_type IN ('receipt','issue','adjustment','transfer','production_input','production_output','disposal')
  ),
  CONSTRAINT batch_movements_quantity_nonzero CHECK (quantity <> 0)
);

CREATE INDEX batch_movements_batch  ON public.batch_movements (batch_id, occurred_at);
CREATE INDEX batch_movements_source ON public.batch_movements (source_table, source_id);

COMMENT ON TABLE public.batch_movements IS
  'Append-only batch ledger. The grants-based enforcement of that lands with N2 in Phase 2; today it is a convention.';

-- Products gain shelf life and an opt-in flag. Not every product is batched, and
-- forcing a batch on a service line would make the feature hated.
ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS shelf_life_days        integer,
  ADD COLUMN IF NOT EXISTS requires_batch_tracking boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS country_of_origin      text;

ALTER TABLE public.products
  DROP CONSTRAINT IF EXISTS products_shelf_life_positive,
  ADD CONSTRAINT products_shelf_life_positive CHECK (shelf_life_days IS NULL OR shelf_life_days > 0);

-- Every line that moves stock can name the batch it moved. Nullable throughout:
-- an unbatched product leaves it null, and Phase 1 writes none of them.
DO $$
DECLARE
  t text;
  stock_lines text[] := ARRAY[
    'sales_invoice_items', 'sales_order_items', 'grn_line_items',
    'return_order_lines', 'inventory_transactions', 'stock_transfers',
    'inventory_adjustments'
  ];
BEGIN
  FOREACH t IN ARRAY stock_lines LOOP
    IF to_regclass('public.' || t) IS NULL THEN
      RAISE EXCEPTION 'expected stock line table public.% to exist', t;
    END IF;
    EXECUTE format(
      'ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS batch_id uuid REFERENCES public.batches(id)', t);
    EXECUTE format(
      'CREATE INDEX IF NOT EXISTS %I ON public.%I (batch_id) WHERE batch_id IS NOT NULL',
      t || '_batch_idx', t);
  END LOOP;
END
$$;

-- N1: deny by default, then the company boundary. Same two-policy shape as every
-- inherited table.
ALTER TABLE public.batches         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.batch_movements ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Block anonymous access to batches"         ON public.batches         TO anon USING (false);
CREATE POLICY "Company isolation"                         ON public.batches         USING (company_id = public.user_company_id());
CREATE POLICY "Block anonymous access to batch_movements" ON public.batch_movements TO anon USING (false);
CREATE POLICY "Company isolation"                         ON public.batch_movements USING (company_id = public.user_company_id());
