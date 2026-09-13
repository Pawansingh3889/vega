-- UK identity and addresses.
--
-- The inherited schema is India-shaped: GSTIN on companies and customers, GST
-- and PAN on suppliers, IFSC bank codes, PIN codes, a place of supply. SPEC.md
-- section 4 needs the UK and EU set instead: a VAT number, a Companies House
-- registration number, an EORI for customs, and an XI VAT number for Northern
-- Ireland movements.
--
-- Renames where the concept survives the border (a postcode is a postcode, a
-- GSTIN and a VAT number are both "the tax identity of this party"), drops where
-- it does not (an IFSC code has no UK meaning).
--
-- customers_safe and suppliers_safe project several of these columns, so they
-- are dropped first and rebuilt at the end. Their role-masking behaviour is
-- reproduced exactly; only the column names change.

DROP VIEW IF EXISTS public.customers_safe;
DROP VIEW IF EXISTS public.suppliers_safe;

-- Companies ----------------------------------------------------------------
ALTER TABLE public.companies RENAME COLUMN gstn TO vat_number;
ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS company_registration_number text,
  ADD COLUMN IF NOT EXISTS eori_number                 text,
  -- Held separately: a business trading under the Windsor Framework has both a
  -- GB and an XI number, and the document decides which one appears.
  ADD COLUMN IF NOT EXISTS xi_vat_number               text,
  ADD COLUMN IF NOT EXISTS county                      text;
ALTER TABLE public.companies DROP COLUMN IF EXISTS ifsc_code;

COMMENT ON COLUMN public.companies.vat_number IS 'GB VAT registration number. XI numbers live in xi_vat_number.';
COMMENT ON COLUMN public.companies.eori_number IS 'Economic Operators Registration and Identification number, required on customs declarations.';

-- Customers ----------------------------------------------------------------
ALTER TABLE public.customers RENAME COLUMN gstin TO vat_number;
ALTER TABLE public.customers RENAME COLUMN pin_code TO postcode;
ALTER TABLE public.customers RENAME COLUMN shipping_pin_code TO shipping_postcode;
ALTER TABLE public.customers
  ADD COLUMN IF NOT EXISTS company_registration_number text,
  ADD COLUMN IF NOT EXISTS eori_number                 text,
  ADD COLUMN IF NOT EXISTS county                      text,
  -- VIES evidence, deliberately narrow: the number checked, when, and the
  -- answer. The response body is not evidence and is not kept. SPEC.md 4.1.
  ADD COLUMN IF NOT EXISTS vat_number_checked_at       timestamp with time zone,
  ADD COLUMN IF NOT EXISTS vat_number_valid            boolean;
ALTER TABLE public.customers
  DROP COLUMN IF EXISTS pan_number,
  DROP COLUMN IF EXISTS ifsc_code,
  DROP COLUMN IF EXISTS gst_tax_location;

-- Suppliers ----------------------------------------------------------------
ALTER TABLE public.suppliers RENAME COLUMN gst_number TO vat_number;
ALTER TABLE public.suppliers RENAME COLUMN pin_code TO postcode;
ALTER TABLE public.suppliers RENAME COLUMN dispatch_pin_code TO dispatch_postcode;
ALTER TABLE public.suppliers
  ADD COLUMN IF NOT EXISTS company_registration_number text,
  ADD COLUMN IF NOT EXISTS eori_number                 text,
  ADD COLUMN IF NOT EXISTS county                      text,
  ADD COLUMN IF NOT EXISTS sort_code                   text,
  ADD COLUMN IF NOT EXISTS vat_number_checked_at       timestamp with time zone,
  ADD COLUMN IF NOT EXISTS vat_number_valid            boolean;
ALTER TABLE public.suppliers
  DROP COLUMN IF EXISTS pan_number,
  DROP COLUMN IF EXISTS ifsc_code,
  -- Place of supply decides which GST applies between Indian states. The UK has
  -- one VAT, and cross-border treatment is carried by the line's treatment code.
  DROP COLUMN IF EXISTS place_of_supply;

-- Document addresses -------------------------------------------------------
ALTER TABLE public.sales_invoices      RENAME COLUMN billing_pin_code  TO billing_postcode;
ALTER TABLE public.sales_invoices      RENAME COLUMN shipping_pin_code TO shipping_postcode;
ALTER TABLE public.sales_orders        RENAME COLUMN billing_pin_code  TO billing_postcode;
ALTER TABLE public.sales_orders        RENAME COLUMN delivery_pin_code TO delivery_postcode;
ALTER TABLE public.return_order_header RENAME COLUMN delivery_pin_code TO delivery_postcode;

-- Documents carrying India's place-of-supply, which decides which GST applies
-- between Indian states. The UK has one VAT and cross-border treatment is
-- carried by the line's treatment code, so the concept has no counterpart.
ALTER TABLE public.sales_orders        DROP COLUMN IF EXISTS place_of_supply;
ALTER TABLE public.performa_invoices   DROP COLUMN IF EXISTS place_of_supply;
ALTER TABLE public.return_order_header DROP COLUMN IF EXISTS place_of_supply;

-- Onboarding collects the applicant's tax identity.
ALTER TABLE public.business_registration_requests RENAME COLUMN gstin TO vat_number;

-- Views rebuilt --------------------------------------------------------------
CREATE VIEW public.customers_safe WITH (security_invoker='true') AS
 SELECT id, company_id, customer_ref, name, customer_type,
    CASE WHEN (public.has_role(auth.uid(), 'owner'::public.app_role) OR public.has_role(auth.uid(), 'admin'::public.app_role) OR public.has_role(auth.uid(), 'manager'::public.app_role)) THEN email ELSE NULL::text END AS email,
    CASE WHEN (public.has_role(auth.uid(), 'owner'::public.app_role) OR public.has_role(auth.uid(), 'admin'::public.app_role) OR public.has_role(auth.uid(), 'manager'::public.app_role)) THEN phone ELSE NULL::text END AS phone,
    address, address_line1, address_line2, city, county, state, postcode, country,
    shipping_address_line1, shipping_address_line2, shipping_city, shipping_state, shipping_postcode, shipping_country,
    vat_number, company_registration_number, eori_number, website, contact_person,
    CASE WHEN (public.has_role(auth.uid(), 'owner'::public.app_role) OR public.has_role(auth.uid(), 'admin'::public.app_role)) THEN credit_limit ELSE NULL::numeric END AS credit_limit,
    CASE WHEN (public.has_role(auth.uid(), 'owner'::public.app_role) OR public.has_role(auth.uid(), 'admin'::public.app_role)) THEN payment_terms ELSE NULL::text END AS payment_terms,
    CASE WHEN (public.has_role(auth.uid(), 'owner'::public.app_role) OR public.has_role(auth.uid(), 'admin'::public.app_role)) THEN account_number ELSE NULL::text END AS account_number,
    is_active, created_at, updated_at
   FROM public.customers
  WHERE (company_id = public.user_company_id());

CREATE VIEW public.suppliers_safe WITH (security_invoker='true') AS
 SELECT id, company_id, supplier_ref, name, supplier_type,
    CASE WHEN (public.has_role(auth.uid(), 'owner'::public.app_role) OR public.has_role(auth.uid(), 'admin'::public.app_role) OR public.has_role(auth.uid(), 'manager'::public.app_role)) THEN email ELSE NULL::text END AS email,
    CASE WHEN (public.has_role(auth.uid(), 'owner'::public.app_role) OR public.has_role(auth.uid(), 'admin'::public.app_role) OR public.has_role(auth.uid(), 'manager'::public.app_role)) THEN phone ELSE NULL::text END AS phone,
    address, address_line1, address_line2, city, county, state, postcode, country,
    vat_number, company_registration_number, eori_number, website,
    CASE WHEN (public.has_role(auth.uid(), 'owner'::public.app_role) OR public.has_role(auth.uid(), 'admin'::public.app_role)) THEN payment_terms ELSE NULL::text END AS payment_terms,
    CASE WHEN (public.has_role(auth.uid(), 'owner'::public.app_role) OR public.has_role(auth.uid(), 'admin'::public.app_role)) THEN credit_time ELSE NULL::integer END AS credit_time,
    CASE WHEN (public.has_role(auth.uid(), 'owner'::public.app_role) OR public.has_role(auth.uid(), 'admin'::public.app_role)) THEN account_number ELSE NULL::text END AS account_number,
    is_active, created_at, updated_at
   FROM public.suppliers
  WHERE (company_id = public.user_company_id());

-- Nothing may still be India-shaped.
DO $$
DECLARE leftovers text;
BEGIN
  SELECT string_agg(table_name || '.' || column_name, ', ')
    INTO leftovers
    FROM information_schema.columns
   WHERE table_schema = 'public'
     AND (column_name LIKE '%pin_code%'
          OR column_name IN ('gstn','gstin','gst_number','pan_number','ifsc_code','place_of_supply','gst_tax_location'));
  IF leftovers IS NOT NULL THEN
    RAISE EXCEPTION 'India-era identity columns still present: %', leftovers;
  END IF;
END
$$;
