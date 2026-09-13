-- Drop the conflicting RLS policy that prevents initial company registration
-- This policy required users to be authenticated with an 'owner' role before creating a company,
-- which is impossible for new users registering their business for the first time.
-- The "Allow company registration operations" policy will remain active to allow
-- unauthenticated users to insert company records during registration.

DROP POLICY IF EXISTS "Owners can create companies" ON public.companies;

-- Verify remaining policies:
-- 1. "Allow company registration operations" (INSERT for PUBLIC) - allows initial registration
-- 2. "Company owners can update their company" (UPDATE for owners/admins) - restricts updates
-- 3. "Users can view their own company" (SELECT for authenticated users) - data isolation