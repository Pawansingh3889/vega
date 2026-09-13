-- Sterling books, euro invoices. SPEC.md section 1.
--
-- GBP is the functional currency: the books, the VAT return and every report are
-- sterling. EUR is a presentment currency: an invoice may be raised and sent in
-- euro, and the document stores the amount, the currency, the rate used, and the
-- date that rate was sourced.
--
-- The rate lives ON the document rather than being resolved at read time. HMRC
-- wants sterling on the return whatever the invoice was raised in, and a figure
-- restated a year later has to reproduce exactly. A rate looked up at read time
-- cannot do that.

CREATE TABLE public.fx_rates (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  base_currency  text NOT NULL,
  quote_currency text NOT NULL,
  -- Enough precision that a round trip does not drift. numeric, never float.
  rate           numeric(18,8) NOT NULL,
  rate_date      date NOT NULL,
  -- Where the number came from, so a disputed figure can be traced rather than
  -- argued about. SPEC.md 1.1.
  source         text NOT NULL DEFAULT 'ECB',
  retrieved_at   timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT fx_rates_rate_positive CHECK (rate > 0),
  CONSTRAINT fx_rates_not_self      CHECK (base_currency <> quote_currency)
);

CREATE UNIQUE INDEX fx_rates_unique_day
  ON public.fx_rates (base_currency, quote_currency, rate_date, source);
CREATE INDEX fx_rates_lookup ON public.fx_rates (base_currency, quote_currency, rate_date DESC);

COMMENT ON TABLE public.fx_rates IS
  'Sourced FX rates. Reference data shared by every tenant. Never overwritten by an empty ingestion result: a failed update leaves yesterday standing and alerts (SECURITY.md N6).';

ALTER TABLE public.fx_rates ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Block anonymous access to fx_rates" ON public.fx_rates TO anon USING (false);
CREATE POLICY "Signed-in users read fx_rates"      ON public.fx_rates FOR SELECT TO authenticated USING (true);

-- Sterling replaces the rupee as the default everywhere a currency is recorded.
DO $$
DECLARE t text;
BEGIN
  FOR t IN
    SELECT table_name FROM information_schema.columns
     WHERE table_schema = 'public' AND column_name = 'currency'
  LOOP
    EXECUTE format('ALTER TABLE public.%I ALTER COLUMN currency SET DEFAULT ''GBP''', t);
    EXECUTE format('UPDATE public.%I SET currency = ''GBP'' WHERE currency = ''INR''', t);
  END LOOP;
END
$$;

-- Every document that can be raised in a presentment currency carries the rate
-- that applied and the date it was sourced. A document in GBP leaves both null;
-- a document in EUR must have both, which the constraint enforces.
DO $$
DECLARE
  t text;
  documents text[] := ARRAY[
    'sales_invoices', 'sales_orders', 'purchase_orders',
    'credit_notes', 'debit_notes', 'performa_invoices', 'supplier_credit_notes'
  ];
BEGIN
  FOREACH t IN ARRAY documents LOOP
    IF to_regclass('public.' || t) IS NULL THEN
      RAISE EXCEPTION 'expected document table public.% to exist', t;
    END IF;

    EXECUTE format($f$
      ALTER TABLE public.%I
        ADD COLUMN IF NOT EXISTS currency     text NOT NULL DEFAULT 'GBP',
        ADD COLUMN IF NOT EXISTS fx_rate      numeric(18,8),
        ADD COLUMN IF NOT EXISTS fx_rate_date date
    $f$, t);

    EXECUTE format($f$
      ALTER TABLE public.%I
        DROP CONSTRAINT IF EXISTS %I,
        ADD CONSTRAINT %I CHECK (
          (currency = 'GBP' AND fx_rate IS NULL AND fx_rate_date IS NULL)
          OR
          (currency <> 'GBP' AND fx_rate IS NOT NULL AND fx_rate_date IS NOT NULL)
        )
    $f$, t, t || '_fx_complete', t || '_fx_complete');
  END LOOP;
END
$$;
