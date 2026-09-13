-- CRITICAL SECURITY FIXES - Phase 1
CREATE OR REPLACE FUNCTION public.has_role(_user_id uuid, _role app_role)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$ SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role); $$;

ALTER TABLE public.profiles DROP COLUMN IF EXISTS role CASCADE;

DROP POLICY IF EXISTS "Company owners can update their company" ON public.companies;
DROP POLICY IF EXISTS "Business owners can manage their subscriptions" ON public.subscriptions;
DROP POLICY IF EXISTS "Company admins can manage access" ON public.user_company_access;

CREATE POLICY "Company owners can update their company" ON public.companies FOR UPDATE
USING (id IN (SELECT company_id FROM public.profiles WHERE user_id = auth.uid()) 
  AND (public.has_role(auth.uid(), 'owner') OR public.has_role(auth.uid(), 'admin')));

CREATE POLICY "Business owners can manage their subscriptions" ON public.subscriptions FOR ALL
USING (business_id IN (SELECT company_id FROM public.profiles WHERE user_id = auth.uid())
  AND (public.has_role(auth.uid(), 'owner') OR public.has_role(auth.uid(), 'admin')));

CREATE POLICY "Company admins can manage access" ON public.user_company_access FOR ALL
USING (company_id IN (SELECT company_id FROM public.profiles WHERE user_id = auth.uid())
  AND (public.has_role(auth.uid(), 'owner') OR public.has_role(auth.uid(), 'admin')));

ALTER FUNCTION public.generate_customer_ref(text) SET search_path = public;
ALTER FUNCTION public.generate_supplier_ref(text) SET search_path = public;
ALTER FUNCTION public.generate_cn_number(uuid) SET search_path = public;
ALTER FUNCTION public.generate_invoice_number(uuid) SET search_path = public;
ALTER FUNCTION public.generate_grn_number(uuid) SET search_path = public;
ALTER FUNCTION public.generate_company_invoice_number(uuid) SET search_path = public;
ALTER FUNCTION public.generate_business_ref() SET search_path = public;
ALTER FUNCTION public.generate_business_ref_no(text) SET search_path = public;

DROP VIEW IF EXISTS public.customers_safe CASCADE;
CREATE VIEW public.customers_safe WITH (security_invoker=true) AS
SELECT id, company_id, customer_ref, name, customer_type,
  CASE WHEN public.has_role(auth.uid(), 'owner') OR public.has_role(auth.uid(), 'admin') OR public.has_role(auth.uid(), 'manager') 
    THEN email ELSE NULL END AS email,
  CASE WHEN public.has_role(auth.uid(), 'owner') OR public.has_role(auth.uid(), 'admin') OR public.has_role(auth.uid(), 'manager') 
    THEN phone ELSE NULL END AS phone,
  address, address_line1, address_line2, city, state, pin_code, country, shipping_address_line1, shipping_address_line2, 
  shipping_city, shipping_state, shipping_pin_code, shipping_country, gstin, pan_number, website, contact_person,
  CASE WHEN public.has_role(auth.uid(), 'owner') OR public.has_role(auth.uid(), 'admin') 
    THEN credit_limit ELSE NULL END AS credit_limit,
  CASE WHEN public.has_role(auth.uid(), 'owner') OR public.has_role(auth.uid(), 'admin') 
    THEN payment_terms ELSE NULL END AS payment_terms,
  CASE WHEN public.has_role(auth.uid(), 'owner') OR public.has_role(auth.uid(), 'admin') 
    THEN account_number ELSE NULL END AS account_number,
  is_active, created_at, updated_at
FROM public.customers WHERE company_id = public.user_company_id();

DROP VIEW IF EXISTS public.suppliers_safe CASCADE;
CREATE VIEW public.suppliers_safe WITH (security_invoker=true) AS
SELECT id, company_id, supplier_ref, name, supplier_type,
  CASE WHEN public.has_role(auth.uid(), 'owner') OR public.has_role(auth.uid(), 'admin') OR public.has_role(auth.uid(), 'manager') 
    THEN email ELSE NULL END AS email,
  CASE WHEN public.has_role(auth.uid(), 'owner') OR public.has_role(auth.uid(), 'admin') OR public.has_role(auth.uid(), 'manager') 
    THEN phone ELSE NULL END AS phone,
  address, address_line1, address_line2, city, state, pin_code, country, gst_number, pan_number, place_of_supply, website,
  CASE WHEN public.has_role(auth.uid(), 'owner') OR public.has_role(auth.uid(), 'admin') 
    THEN payment_terms ELSE NULL END AS payment_terms,
  CASE WHEN public.has_role(auth.uid(), 'owner') OR public.has_role(auth.uid(), 'admin') 
    THEN credit_time ELSE NULL END AS credit_time,
  CASE WHEN public.has_role(auth.uid(), 'owner') OR public.has_role(auth.uid(), 'admin') 
    THEN account_number ELSE NULL END AS account_number,
  is_active, created_at, updated_at
FROM public.suppliers WHERE company_id = public.user_company_id();