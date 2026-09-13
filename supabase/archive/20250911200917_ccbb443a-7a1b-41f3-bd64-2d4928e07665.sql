-- Fix POD document access by making the documents bucket public for viewing
-- Update the documents bucket to be public
UPDATE storage.buckets 
SET public = true 
WHERE id = 'documents';

-- Drop existing restrictive SELECT policy
DROP POLICY IF EXISTS "Users can view their company POD documents" ON storage.objects;

-- Create new policy for public read access to POD documents
CREATE POLICY "Public read access to POD documents" 
ON storage.objects 
FOR SELECT 
TO public 
USING (bucket_id = 'documents');

-- Keep restrictive policies for upload/update/delete
-- These policies remain authenticated-only for security