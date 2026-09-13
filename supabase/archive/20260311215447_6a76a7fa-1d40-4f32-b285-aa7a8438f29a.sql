CREATE OR REPLACE FUNCTION public.prevent_role_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
BEGIN
  IF OLD.role IS DISTINCT FROM NEW.role THEN
    RAISE EXCEPTION 'Direct role updates not allowed. Use user_roles table.';
  END IF;
  RETURN NEW;
END;
$function$;