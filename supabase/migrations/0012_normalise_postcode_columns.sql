-- One name for a postcode, and no table with two of them.
--
-- The inherited schema used postal_code on some tables and pin_code on others.
-- 0006 renamed every pin_code to postcode, which fixed the India-shaped half and
-- left the schema with both spellings side by side. Worse, sales_orders already
-- had delivery_postal_code, so the rename produced a table carrying
-- delivery_postal_code AND delivery_postcode: two columns for one fact, which is
-- how a despatch address ends up in the column nobody reads.
--
-- Found by writing the seed dataset. A schema-shaped check cannot see this,
-- because both spellings are perfectly valid columns; it only shows up when
-- something tries to write a real address.

-- Merge before dropping: whichever column holds a value wins, and the duplicate
-- goes. Both are empty today, so this is precaution rather than repair, but a
-- migration that silently discards data is not one worth writing.
UPDATE public.sales_orders
   SET delivery_postcode = COALESCE(delivery_postcode, delivery_postal_code)
 WHERE delivery_postal_code IS NOT NULL;
ALTER TABLE public.sales_orders DROP COLUMN IF EXISTS delivery_postal_code;

ALTER TABLE public.companies                      RENAME COLUMN postal_code TO postcode;
ALTER TABLE public.business_registration_requests RENAME COLUMN postal_code TO postcode;
ALTER TABLE public.warehouse_bins                 RENAME COLUMN postal_code TO postcode;
ALTER TABLE public.purchase_orders  RENAME COLUMN delivery_postal_code TO delivery_postcode;

-- One spelling, and no table with two.
DO $$
DECLARE leftovers text;
BEGIN
  SELECT string_agg(table_name || '.' || column_name, ', ')
    INTO leftovers FROM information_schema.columns
   WHERE table_schema = 'public' AND column_name LIKE '%postal_code%';
  IF leftovers IS NOT NULL THEN
    RAISE EXCEPTION 'postal_code columns still present: %', leftovers;
  END IF;

  SELECT string_agg(table_name, ', ') INTO leftovers
    FROM (
      SELECT table_name FROM information_schema.columns
       WHERE table_schema = 'public' AND column_name LIKE '%postcode%'
       GROUP BY table_name, replace(column_name, 'postal_code', 'postcode')
      HAVING count(*) > 1
    ) d;
  IF leftovers IS NOT NULL THEN
    RAISE EXCEPTION 'table carries two columns for one postcode: %', leftovers;
  END IF;
END
$$;
