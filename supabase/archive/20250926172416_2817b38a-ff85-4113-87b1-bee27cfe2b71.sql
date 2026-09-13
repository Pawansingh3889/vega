-- Add designation column to company_users table
ALTER TABLE public.company_users 
ADD COLUMN designation text;