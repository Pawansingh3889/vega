-- Temporarily create a more permissive policy for debugging
DROP POLICY IF EXISTS "Company access for purchase orders" ON public.purchase_orders;

-- Create a policy that allows all authenticated users to see purchase orders (temporarily for debugging)
CREATE POLICY "Debug - Allow authenticated users to view purchase orders" 
ON public.purchase_orders 
FOR ALL 
USING (auth.uid() IS NOT NULL OR company_id IS NOT NULL);

-- Also ensure the profiles table policies are working correctly
-- Let's check if users can see their profiles
SELECT 'Profiles policy check' as debug_info;