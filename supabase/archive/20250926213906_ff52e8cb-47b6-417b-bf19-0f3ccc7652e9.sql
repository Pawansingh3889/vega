-- Add logo_url and tagline fields to companies table
ALTER TABLE public.companies 
ADD COLUMN IF NOT EXISTS logo_url text,
ADD COLUMN IF NOT EXISTS tagline text;

-- Create storage bucket for company logos
INSERT INTO storage.buckets (id, name, public)
VALUES ('company-logos', 'company-logos', true)
ON CONFLICT (id) DO NOTHING;

-- Create RLS policies for company logo storage
CREATE POLICY "Users can view company logos" ON storage.objects
FOR SELECT USING (bucket_id = 'company-logos');

CREATE POLICY "Users can upload their company logo" ON storage.objects
FOR INSERT WITH CHECK (
  bucket_id = 'company-logos' 
  AND auth.uid() IS NOT NULL
  AND (storage.foldername(name))[1] IN (
    SELECT c.id::text FROM companies c 
    JOIN profiles p ON p.company_id = c.id 
    WHERE p.user_id = auth.uid() AND p.role IN ('owner', 'admin')
  )
);

CREATE POLICY "Users can update their company logo" ON storage.objects
FOR UPDATE USING (
  bucket_id = 'company-logos' 
  AND auth.uid() IS NOT NULL
  AND (storage.foldername(name))[1] IN (
    SELECT c.id::text FROM companies c 
    JOIN profiles p ON p.company_id = c.id 
    WHERE p.user_id = auth.uid() AND p.role IN ('owner', 'admin')
  )
);

CREATE POLICY "Users can delete their company logo" ON storage.objects
FOR DELETE USING (
  bucket_id = 'company-logos' 
  AND auth.uid() IS NOT NULL
  AND (storage.foldername(name))[1] IN (
    SELECT c.id::text FROM companies c 
    JOIN profiles p ON p.company_id = c.id 
    WHERE p.user_id = auth.uid() AND p.role IN ('owner', 'admin')
  )
);