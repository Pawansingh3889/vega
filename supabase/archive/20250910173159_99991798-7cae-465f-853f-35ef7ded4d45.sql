-- Create user_company_id helper function if not exists
CREATE OR REPLACE FUNCTION public.user_company_id()
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT company_id FROM public.profiles WHERE user_id = auth.uid() LIMIT 1;
$function$;

-- Enable RLS on current_stock_levels view
ALTER VIEW public.current_stock_levels ENABLE ROW LEVEL SECURITY;

-- Add RLS policy for current_stock_levels
CREATE POLICY "Company isolation for current_stock_levels" 
ON public.current_stock_levels 
FOR SELECT 
USING (company_id = user_company_id());

-- Enable RLS on current_stock_with_aging view  
ALTER VIEW public.current_stock_with_aging ENABLE ROW LEVEL SECURITY;

-- Add RLS policy for current_stock_with_aging
CREATE POLICY "Company isolation for current_stock_with_aging" 
ON public.current_stock_with_aging 
FOR SELECT 
USING (company_id = user_company_id());