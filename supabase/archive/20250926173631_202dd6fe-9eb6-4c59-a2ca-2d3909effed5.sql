-- Add foreign key relationship between transaction_audit_log and profiles
ALTER TABLE public.transaction_audit_log 
ADD CONSTRAINT fk_transaction_audit_log_user_id 
FOREIGN KEY (user_id) REFERENCES public.profiles(user_id) ON DELETE SET NULL;