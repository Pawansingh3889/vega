-- ===========================================================================
-- CRITICAL SECURITY FIXES - MINIMAL VERSION (Tables Confirmed to Exist)
-- ===========================================================================

-- 1. CREATE USER_ROLES TABLE FOR SECURE ROLE MANAGEMENT
CREATE TABLE IF NOT EXISTS public.user_roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role app_role NOT NULL,
    company_id UUID REFERENCES public.companies(id) ON DELETE CASCADE,
    granted_by UUID REFERENCES auth.users(id),
    granted_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    UNIQUE (user_id, role, company_id)
);

ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

-- 2. MIGRATE EXISTING ROLES FROM PROFILES
INSERT INTO public.user_roles (user_id, role, company_id, granted_at)
SELECT user_id, role, company_id, created_at
FROM public.profiles
ON CONFLICT (user_id, role, company_id) DO NOTHING;

-- 3. CREATE SECURITY DEFINER FUNCTIONS
CREATE OR REPLACE FUNCTION public.get_user_role(p_user_id UUID DEFAULT auth.uid())
RETURNS app_role
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT role FROM public.user_roles WHERE user_id = p_user_id LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.is_user_admin_v2(p_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles 
    WHERE user_id = p_user_id AND role IN ('owner', 'admin')
  );
$$;

-- 4. RLS POLICIES FOR USER_ROLES
DROP POLICY IF EXISTS "Users can view their own roles" ON public.user_roles;
CREATE POLICY "Users can view their own roles" ON public.user_roles
FOR SELECT TO authenticated USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Admins can view company roles" ON public.user_roles;
CREATE POLICY "Admins can view company roles" ON public.user_roles
FOR SELECT TO authenticated
USING (
  company_id IN (
    SELECT company_id FROM public.user_roles 
    WHERE user_id = auth.uid() AND role IN ('owner', 'admin')
  )
);

DROP POLICY IF EXISTS "Only owners can manage roles" ON public.user_roles;
CREATE POLICY "Only owners can manage roles" ON public.user_roles
FOR ALL TO authenticated
USING (
  company_id IN (
    SELECT company_id FROM public.user_roles 
    WHERE user_id = auth.uid() AND role = 'owner'
  )
)
WITH CHECK (
  company_id IN (
    SELECT company_id FROM public.user_roles 
    WHERE user_id = auth.uid() AND role = 'owner'
  )
);

-- 5. PREVENT ROLE UPDATES ON PROFILES TABLE
CREATE OR REPLACE FUNCTION public.prevent_role_update()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
  IF OLD.role IS DISTINCT FROM NEW.role THEN
    RAISE EXCEPTION 'Direct role updates not allowed. Use user_roles table.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS prevent_role_update_trigger ON public.profiles;
CREATE TRIGGER prevent_role_update_trigger
BEFORE UPDATE ON public.profiles
FOR EACH ROW EXECUTE FUNCTION public.prevent_role_update();

-- 6. FIX PROFILES UPDATE POLICY
DROP POLICY IF EXISTS "Users can update their own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can update their own profile (not role)" ON public.profiles;
CREATE POLICY "Users can update their own profile (not role)" ON public.profiles
FOR UPDATE TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

-- 7. CREATE SAFE VIEW FOR COMPANY_USERS (HIDE PASSWORD HASHES)
DROP VIEW IF EXISTS public.company_users_safe CASCADE;
CREATE VIEW public.company_users_safe AS
SELECT id, company_id, user_id, username, email, access_type, status,
       full_name, designation, created_by, created_at, updated_at
FROM public.company_users;
GRANT SELECT ON public.company_users_safe TO authenticated;

-- 8. BLOCK ANONYMOUS ACCESS - Core Tables Only
DROP POLICY IF EXISTS "Block anonymous access to profiles" ON public.profiles;
CREATE POLICY "Block anonymous access to profiles" ON public.profiles FOR ALL TO anon USING (false);

DROP POLICY IF EXISTS "Block anonymous access to customers" ON public.customers;
CREATE POLICY "Block anonymous access to customers" ON public.customers FOR ALL TO anon USING (false);

DROP POLICY IF EXISTS "Block anonymous access to suppliers" ON public.suppliers;
CREATE POLICY "Block anonymous access to suppliers" ON public.suppliers FOR ALL TO anon USING (false);

DROP POLICY IF EXISTS "Block anonymous access to companies" ON public.companies;
CREATE POLICY "Block anonymous access to companies" ON public.companies FOR ALL TO anon USING (false);

DROP POLICY IF EXISTS "Block anonymous access to products" ON public.products;
CREATE POLICY "Block anonymous access to products" ON public.products FOR ALL TO anon USING (false);

DROP POLICY IF EXISTS "Block anonymous access to sales_invoices" ON public.sales_invoices;
CREATE POLICY "Block anonymous access to sales_invoices" ON public.sales_invoices FOR ALL TO anon USING (false);

DROP POLICY IF EXISTS "Block anonymous access to purchase_orders" ON public.purchase_orders;
CREATE POLICY "Block anonymous access to purchase_orders" ON public.purchase_orders FOR ALL TO anon USING (false);

DROP POLICY IF EXISTS "Block anonymous access to sales_orders" ON public.sales_orders;
CREATE POLICY "Block anonymous access to sales_orders" ON public.sales_orders FOR ALL TO anon USING (false);

DROP POLICY IF EXISTS "Block anonymous access to payment_transactions" ON public.payment_transactions;
CREATE POLICY "Block anonymous access to payment_transactions" ON public.payment_transactions FOR ALL TO anon USING (false);

-- 9. AUDIT LOGGING FOR ROLE CHANGES
CREATE OR REPLACE FUNCTION public.log_role_change_v2()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.security_audit_log (user_id, action, details, ip_address, severity)
    VALUES (auth.uid(), 'role_granted',
      jsonb_build_object('target_user_id', NEW.user_id, 'role', NEW.role, 'company_id', NEW.company_id),
      '127.0.0.1', 'medium');
  ELSIF TG_OP = 'DELETE' THEN
    INSERT INTO public.security_audit_log (user_id, action, details, ip_address, severity)
    VALUES (auth.uid(), 'role_revoked',
      jsonb_build_object('target_user_id', OLD.user_id, 'role', OLD.role),
      '127.0.0.1', 'high');
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS log_role_changes_trigger ON public.user_roles;
CREATE TRIGGER log_role_changes_trigger AFTER INSERT OR DELETE ON public.user_roles
FOR EACH ROW EXECUTE FUNCTION public.log_role_change_v2();