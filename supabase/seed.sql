-- A known dataset: one small UK food manufacturer.
--
-- Deterministic on purpose. Every id is fixed, so a restore drill can compare
-- row counts and specific values rather than "looks about right". Re-runnable:
-- it deletes its own company first, and every child row cascades or is removed
-- with it.
--
-- Shaped after the target user rather than a generic ERP demo: a bakery with
-- batches, shelf life, a mix of VAT treatments including a zero-rated staple and
-- a standard-rated luxury, and one EU customer so the reverse charge path has
-- real data behind it.
--
-- The auth user is created separately by scripts/seed-demo.sh through the Auth
-- admin API, because auth.users belongs to GoTrue and a hand-written row is not
-- a user anybody can sign in as.

BEGIN;

DELETE FROM public.companies WHERE id = '11111111-0000-4000-8000-000000000001';

INSERT INTO public.companies
  (id, name, email, vat_number, company_registration_number, eori_number,
   address_line1, city, county, postcode, country, status)
VALUES
  ('11111111-0000-4000-8000-000000000001', 'Pennine Bakehouse Ltd',
   'accounts@pennine-bakehouse.test', 'GB123456789', '09876543', 'GB123456789000',
   'Unit 4, Mill Road', 'Hebden Bridge', 'West Yorkshire', 'HX7 6AB', 'GB', 'active');

INSERT INTO public.profiles (id, user_id, company_id, first_name, last_name)
VALUES ('11111111-0000-4000-8000-0000000000a1',
        '11111111-0000-4000-8000-0000000000f1',
        '11111111-0000-4000-8000-000000000001', 'Ruth', 'Ackroyd');

INSERT INTO public.company_users
  (id, company_id, user_id, username, email, password_hash, access_type, status, full_name)
VALUES ('11111111-0000-4000-8000-0000000000b1',
        '11111111-0000-4000-8000-000000000001',
        '11111111-0000-4000-8000-0000000000f1',
        'ruth', 'ruth@pennine-bakehouse.test', 'managed-by-gotrue', 'OWNER', 'ACTIVE',
        'Ruth Ackroyd');

-- Customers: one domestic, one in the Republic of Ireland so an EU reverse
-- charge line has somewhere to point.
INSERT INTO public.customers
  (id, company_id, name, email, vat_number, address_line1, city, county, postcode, country)
VALUES
  ('11111111-0000-4000-8000-0000000000c1', '11111111-0000-4000-8000-000000000001',
   'Calder Valley Farm Shop', 'orders@cvfarmshop.test', 'GB223344556',
   '12 Market Street', 'Todmorden', 'West Yorkshire', 'OL14 5AB', 'GB'),
  ('11111111-0000-4000-8000-0000000000c2', '11111111-0000-4000-8000-000000000001',
   'Bandon Fine Foods', 'buyer@bandonfine.test', 'IE9825613N',
   'Riverside Units', 'Bandon', 'Co. Cork', 'P72 X284', 'IE');

INSERT INTO public.suppliers
  (id, company_id, name, email, vat_number, address_line1, city, postcode, country)
VALUES
  ('11111111-0000-4000-8000-0000000000d1', '11111111-0000-4000-8000-000000000001',
   'Marriage''s Millers', 'sales@marriages.test', 'GB334455667',
   'Chelmer Mills', 'Chelmsford', 'CM1 1PN', 'GB'),
  ('11111111-0000-4000-8000-0000000000d2', '11111111-0000-4000-8000-000000000001',
   'Cocoa Direct Imports', 'trade@cocoadirect.test', 'GB445566778',
   'Dock Road', 'Liverpool', 'L3 0AA', 'GB');

INSERT INTO public.product_categories (id, company_id, name)
VALUES ('11111111-0000-4000-8000-0000000000e1', '11111111-0000-4000-8000-000000000001', 'Bakery');

-- Treatments carry the difference: bread is zero rated, a chocolate product is
-- standard rated, and both sit in the same catalogue.
INSERT INTO public.products
  (id, company_id, category_id, sku, name, unit, unit_price, cost_price,
   default_vat_treatment_code, commodity_code, shelf_life_days,
   requires_batch_tracking, country_of_origin)
VALUES
  ('11111111-0000-4000-8000-000000000101', '11111111-0000-4000-8000-000000000001',
   '11111111-0000-4000-8000-0000000000e1', 'SD-800', 'Sourdough loaf 800g',
   'each', 3.20, 0.95, 'ZER', '1905908000', 4, true, 'GB'),
  ('11111111-0000-4000-8000-000000000102', '11111111-0000-4000-8000-000000000001',
   '11111111-0000-4000-8000-0000000000e1', 'RY-400', 'Rye loaf 400g',
   'each', 2.60, 0.80, 'ZER', '1905908000', 5, true, 'GB'),
  ('11111111-0000-4000-8000-000000000103', '11111111-0000-4000-8000-000000000001',
   '11111111-0000-4000-8000-0000000000e1', 'CB-200', 'Chocolate brownie tray',
   'each', 12.50, 4.10, 'STD', '1905311000', 10, true, 'GB'),
  ('11111111-0000-4000-8000-000000000104', '11111111-0000-4000-8000-000000000001',
   '11111111-0000-4000-8000-0000000000e1', 'FL-STRONG', 'Strong white flour 16kg',
   'sack', 18.00, 14.20, 'ZER', '1101000000', 180, true, 'GB');

-- Batches: one already past its use-by so a shelf-life query has something true
-- to find, and one imported input for the EUDR path later.
INSERT INTO public.batches
  (id, company_id, product_id, batch_code, manufactured_on, best_before_on, use_by_on,
   quantity_received, unit_of_measure, supplier_id, supplier_batch_code,
   country_of_origin, status)
VALUES
  ('11111111-0000-4000-8000-000000000201', '11111111-0000-4000-8000-000000000001',
   '11111111-0000-4000-8000-000000000101', 'SD-2026-0901', '2026-09-01', '2026-09-05',
   '2026-09-05', 120.000, 'each', NULL, NULL, 'GB', 'consumed'),
  ('11111111-0000-4000-8000-000000000202', '11111111-0000-4000-8000-000000000001',
   '11111111-0000-4000-8000-000000000101', 'SD-2026-0904', '2026-09-04', '2026-09-08',
   '2026-09-08', 150.000, 'each', NULL, NULL, 'GB', 'available'),
  ('11111111-0000-4000-8000-000000000203', '11111111-0000-4000-8000-000000000001',
   '11111111-0000-4000-8000-000000000103', 'CB-2026-0903', '2026-09-03', '2026-09-13',
   NULL, 40.000, 'each', NULL, NULL, 'GB', 'available'),
  ('11111111-0000-4000-8000-000000000204', '11111111-0000-4000-8000-000000000001',
   '11111111-0000-4000-8000-000000000104', 'FL-24-2211', '2026-08-15', '2027-02-11',
   NULL, 32.000, 'sack', '11111111-0000-4000-8000-0000000000d1', 'MM-2211', 'GB', 'available');

INSERT INTO public.batch_movements
  (id, company_id, batch_id, movement_type, quantity, occurred_at, source_table, note)
VALUES
  ('11111111-0000-4000-8000-000000000301', '11111111-0000-4000-8000-000000000001',
   '11111111-0000-4000-8000-000000000204', 'receipt', 32.000, '2026-08-15 08:00+01',
   'suppliers', 'Delivery from Marriage''s'),
  ('11111111-0000-4000-8000-000000000302', '11111111-0000-4000-8000-000000000001',
   '11111111-0000-4000-8000-000000000204', 'production_input', -6.000, '2026-09-01 05:30+01',
   'batches', 'Into SD-2026-0901'),
  ('11111111-0000-4000-8000-000000000303', '11111111-0000-4000-8000-000000000001',
   '11111111-0000-4000-8000-000000000201', 'production_output', 120.000, '2026-09-01 09:00+01',
   'batches', 'Sourdough bake'),
  ('11111111-0000-4000-8000-000000000304', '11111111-0000-4000-8000-000000000001',
   '11111111-0000-4000-8000-000000000201', 'issue', -120.000, '2026-09-02 07:00+01',
   'sales_invoices', 'Despatched to Calder Valley');

-- One domestic invoice with a zero-rated and a standard-rated line, so boxes 1
-- and 6 of a VAT return have something non-trivial to derive from.
INSERT INTO public.sales_invoices
  (id, company_id, invoice_number, invoice_date, customer_id, customer_name,
   billing_address_line1, billing_city, billing_postcode, billing_country,
   currency, created_by)
VALUES
  ('11111111-0000-4000-8000-000000000401', '11111111-0000-4000-8000-000000000001',
   'VG-INV-0001', '2026-09-02', '11111111-0000-4000-8000-0000000000c1',
   'Calder Valley Farm Shop', '12 Market Street', 'Todmorden', 'OL14 5AB', 'GB',
   'GBP', '11111111-0000-4000-8000-0000000000f1');

INSERT INTO public.sales_invoice_items
  (id, sales_invoice_id, product_id, item_code, item_description, commodity_code,
   quantity_invoiced, unit_of_measure, unit_price, vat_treatment_code, vat_rate,
   vat_amount, line_subtotal, line_total, batch_id)
VALUES
  ('11111111-0000-4000-8000-000000000411', '11111111-0000-4000-8000-000000000401',
   '11111111-0000-4000-8000-000000000101', 'SD-800', 'Sourdough loaf 800g',
   '1905908000', 120, 'each', 3.20, 'ZER', 0.00, 0.00, 384.00, 384.00,
   '11111111-0000-4000-8000-000000000201'),
  ('11111111-0000-4000-8000-000000000412', '11111111-0000-4000-8000-000000000401',
   '11111111-0000-4000-8000-000000000103', 'CB-200', 'Chocolate brownie tray',
   '1905311000', 10, 'each', 12.50, 'STD', 20.00, 25.00, 125.00, 150.00,
   '11111111-0000-4000-8000-000000000203');

COMMIT;
