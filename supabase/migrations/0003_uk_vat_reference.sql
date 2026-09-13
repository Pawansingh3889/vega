-- UK VAT reference data: treatments, their EN 16931 mapping, and rates by date.
--
-- SPEC.md section 2.1: a line carries a TREATMENT, never a loose percentage. A
-- rate is a consequence of a treatment, and storing the rate alone loses why it
-- applied, which is exactly what a VAT return has to explain.

CREATE TABLE public.vat_treatments (
  code                text PRIMARY KEY,
  description         text NOT NULL,
  -- EN 16931 tax category, the code PEPPOL BIS Billing 3.0 actually carries.
  -- Phase 3 emits UBL by looking this up, never by improvising at the call site.
  en16931_category    text NOT NULL,
  is_reverse_charge   boolean NOT NULL DEFAULT false,
  -- Northern Ireland cases move goods inside the EU regime under the Windsor
  -- Framework. They take the category their underlying treatment implies and are
  -- distinguished by the XI endpoint on the party identifier, not by a different
  -- category. SPEC.md section 2.4.
  is_northern_ireland boolean NOT NULL DEFAULT false,
  -- Feeds boxes 8 and 9 of the return.
  is_ec_sales_list    boolean NOT NULL DEFAULT false,
  sort_order          integer NOT NULL DEFAULT 0,
  created_at          timestamp with time zone NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.vat_treatments IS
  'UK VAT treatments. Reference data, identical for every tenant, so deliberately not company-scoped.';

CREATE TABLE public.vat_rates (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  treatment_code  text NOT NULL REFERENCES public.vat_treatments(code),
  -- Percentage, so 20.00 means 20%. numeric, never float: these numbers are
  -- filed with HMRC.
  rate            numeric(5,2) NOT NULL,
  effective_from  date NOT NULL,
  effective_to    date,
  created_at      timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT vat_rates_period_valid CHECK (effective_to IS NULL OR effective_to > effective_from),
  CONSTRAINT vat_rates_rate_sane    CHECK (rate >= 0 AND rate <= 100)
);

-- One open-ended rate per treatment at a time. A rate change closes the old row
-- and opens a new one; it never rewrites an issued document.
CREATE UNIQUE INDEX vat_rates_one_open_period
  ON public.vat_rates (treatment_code) WHERE effective_to IS NULL;
CREATE INDEX vat_rates_lookup ON public.vat_rates (treatment_code, effective_from DESC);

INSERT INTO public.vat_treatments
  (code, description, en16931_category, is_reverse_charge, is_northern_ireland, is_ec_sales_list, sort_order)
VALUES
  ('STD',    'Standard rated',                              'S',  false, false, false, 10),
  ('RED',    'Reduced rated',                               'S',  false, false, false, 20),
  ('ZER',    'Zero rated',                                  'Z',  false, false, false, 30),
  ('EXM',    'Exempt from VAT',                             'E',  false, false, false, 40),
  ('OUT',    'Outside the scope of UK VAT',                 'O',  false, false, false, 50),
  ('DRC',    'Domestic reverse charge',                     'AE', true,  false, false, 60),
  ('ERC',    'EU business to business reverse charge',      'AE', true,  false, true,  70),
  ('EXP',    'Export of goods outside the UK',              'G',  false, false, false, 80),
  ('XI_STD', 'Northern Ireland, standard rated',            'S',  false, true,  false, 90),
  ('XI_ZER', 'Northern Ireland, zero rated',                'Z',  false, true,  false, 100),
  ('XI_ICS', 'Northern Ireland intra-community supply',     'K',  false, true,  true,  110);

-- Rates as at the 2026-09 position. RED and STD share EN 16931 category S; the
-- percentage carries the difference, which is why emitting a distinct category
-- for the reduced rate produces a document that fails validation.
INSERT INTO public.vat_rates (treatment_code, rate, effective_from) VALUES
  ('STD',    20.00, '2011-01-04'),
  ('RED',     5.00, '1997-09-01'),
  ('ZER',     0.00, '1973-04-01'),
  ('EXM',     0.00, '1973-04-01'),
  ('OUT',     0.00, '1973-04-01'),
  ('DRC',     0.00, '2019-10-01'),
  ('ERC',     0.00, '2021-01-01'),
  ('EXP',     0.00, '2021-01-01'),
  ('XI_STD', 20.00, '2021-01-01'),
  ('XI_ZER',  0.00, '2021-01-01'),
  ('XI_ICS',  0.00, '2021-01-01');

-- Reference data is readable by any signed-in user and writable by nobody
-- through the API: rates change by migration, so the change is reviewed.
-- Deny-by-default still applies, so anon is blocked explicitly.
ALTER TABLE public.vat_treatments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vat_rates      ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Block anonymous access to vat_treatments" ON public.vat_treatments TO anon USING (false);
CREATE POLICY "Signed-in users read vat_treatments"      ON public.vat_treatments FOR SELECT TO authenticated USING (true);
CREATE POLICY "Block anonymous access to vat_rates"      ON public.vat_rates      TO anon USING (false);
CREATE POLICY "Signed-in users read vat_rates"           ON public.vat_rates      FOR SELECT TO authenticated USING (true);
