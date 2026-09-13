-- Create AI conversation history table for storing chat history
CREATE TABLE IF NOT EXISTS public.ai_conversation_history (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  company_id UUID NOT NULL,
  user_id UUID NOT NULL,
  user_message TEXT NOT NULL,
  ai_response TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable Row Level Security
ALTER TABLE public.ai_conversation_history ENABLE ROW LEVEL SECURITY;

-- Create policies for user access (users can only see conversations from their company)
CREATE POLICY "Users can view their company's AI conversations" 
ON public.ai_conversation_history 
FOR SELECT 
USING (company_id IN (
  SELECT company_id FROM public.profiles WHERE id = auth.uid()
));

CREATE POLICY "Users can create AI conversations for their company" 
ON public.ai_conversation_history 
FOR INSERT 
WITH CHECK (company_id IN (
  SELECT company_id FROM public.profiles WHERE id = auth.uid()
));

-- Create index for better performance on queries
CREATE INDEX idx_ai_conversation_history_company_user_created 
ON public.ai_conversation_history (company_id, user_id, created_at DESC);

-- Create trigger for automatic timestamp updates
CREATE TRIGGER update_ai_conversation_history_updated_at
BEFORE UPDATE ON public.ai_conversation_history
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();