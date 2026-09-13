-- Add missing INSERT, UPDATE, and DELETE RLS policies for company-logos storage bucket
-- These policies allow users with 'owner' or 'admin' roles to manage their company logos

-- Allow users to upload their company logo (INSERT)
CREATE POLICY "Users can upload their company logo" ON storage.objects
FOR INSERT 
WITH CHECK (
  bucket_id = 'company-logos' 
  AND auth.uid() IS NOT NULL
  AND (storage.foldername(name))[1] IN (
    SELECT c.id::text 
    FROM companies c 
    JOIN user_roles ur ON ur.company_id = c.id 
    WHERE ur.user_id = auth.uid() 
      AND ur.role IN ('owner', 'admin')
  )
);

-- Allow users to update/replace their company logo (UPDATE)
CREATE POLICY "Users can update their company logo" ON storage.objects
FOR UPDATE 
USING (
  bucket_id = 'company-logos' 
  AND auth.uid() IS NOT NULL
  AND (storage.foldername(name))[1] IN (
    SELECT c.id::text 
    FROM companies c 
    JOIN user_roles ur ON ur.company_id = c.id 
    WHERE ur.user_id = auth.uid() 
      AND ur.role IN ('owner', 'admin')
  )
);

-- Allow users to delete their company logo (DELETE)
CREATE POLICY "Users can delete their company logo" ON storage.objects
FOR DELETE 
USING (
  bucket_id = 'company-logos' 
  AND auth.uid() IS NOT NULL
  AND (storage.foldername(name))[1] IN (
    SELECT c.id::text 
    FROM companies c 
    JOIN user_roles ur ON ur.company_id = c.id 
    WHERE ur.user_id = auth.uid() 
      AND ur.role IN ('owner', 'admin')
  )
);