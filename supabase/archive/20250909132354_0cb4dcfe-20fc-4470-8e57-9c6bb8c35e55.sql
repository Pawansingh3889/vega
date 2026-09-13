-- First check if there are any existing policies and drop them all
DROP POLICY IF EXISTS "Users can access their company purchase orders" ON public.purchase_orders;
DROP POLICY IF EXISTS "Company isolation" ON public.purchase_orders;

-- Create a simple and effective policy that works with client-side auth
CREATE POLICY "Company access for purchase orders" 
ON public.purchase_orders 
FOR ALL 
USING (
  company_id IN (
    SELECT company_id 
    FROM public.profiles 
    WHERE user_id = auth.uid()
  )
);

-- Ensure RLS is enabled
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;