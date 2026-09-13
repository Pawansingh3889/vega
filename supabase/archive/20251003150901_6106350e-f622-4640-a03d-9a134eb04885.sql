-- Add subscription tracking columns to companies table
ALTER TABLE companies 
ADD COLUMN IF NOT EXISTS subscription_plan TEXT CHECK (subscription_plan IN ('trial', 'monthly', 'yearly')),
ADD COLUMN IF NOT EXISTS subscription_start_date DATE,
ADD COLUMN IF NOT EXISTS subscription_end_date DATE,
ADD COLUMN IF NOT EXISTS subscription_status TEXT DEFAULT 'trial' CHECK (subscription_status IN ('trial', 'active', 'expired', 'suspended')),
ADD COLUMN IF NOT EXISTS payment_reminder_sent BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS last_payment_date DATE,
ADD COLUMN IF NOT EXISTS next_payment_due DATE;

-- Create index for faster subscription status queries
CREATE INDEX IF NOT EXISTS idx_companies_subscription_status ON companies(subscription_status);
CREATE INDEX IF NOT EXISTS idx_companies_subscription_end_date ON companies(subscription_end_date);