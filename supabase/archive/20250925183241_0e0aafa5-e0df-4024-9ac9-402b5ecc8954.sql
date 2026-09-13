-- Create document format configurations table
CREATE TABLE public.document_format_configs (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  company_id UUID NOT NULL,
  document_type TEXT NOT NULL CHECK (document_type IN ('purchase_order', 'invoice', 'debit_note', 'credit_note', 'customer_id', 'supplier_id', 'grn', 'return_sales_order')),
  prefix TEXT NOT NULL DEFAULT '',
  suffix TEXT NOT NULL DEFAULT '001',
  current_counter INTEGER NOT NULL DEFAULT 1001,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  UNIQUE(company_id, document_type)
);

-- Enable RLS
ALTER TABLE public.document_format_configs ENABLE ROW LEVEL SECURITY;

-- Create RLS policies
CREATE POLICY "Company isolation for document_format_configs" 
ON public.document_format_configs 
FOR ALL 
USING (company_id = user_company_id())
WITH CHECK (company_id = user_company_id());

-- Create indexes for performance
CREATE INDEX idx_document_format_configs_company_id ON public.document_format_configs(company_id);
CREATE INDEX idx_document_format_configs_document_type ON public.document_format_configs(document_type);

-- Create trigger for updated_at
CREATE TRIGGER update_document_format_configs_updated_at
BEFORE UPDATE ON public.document_format_configs
FOR EACH ROW
EXECUTE FUNCTION public.set_current_timestamp_updated_at();