-- Fix the RLS policy for purchase_orders to work with client-side auth
-- Drop the existing policy
DROP POLICY IF EXISTS "Company isolation" ON public.purchase_orders;

-- Create a new policy that works with client-side authentication
CREATE POLICY "Users can access their company purchase orders" 
ON public.purchase_orders 
FOR ALL 
USING (
  company_id IN (
    SELECT company_id 
    FROM public.profiles 
    WHERE user_id = auth.uid()
  )
);

-- Also ensure RLS is enabled on the table
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;