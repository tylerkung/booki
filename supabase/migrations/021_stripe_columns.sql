-- Add Stripe columns to bookies table for subscription management
ALTER TABLE bookies ADD COLUMN IF NOT EXISTS stripe_customer_id TEXT UNIQUE;
ALTER TABLE bookies ADD COLUMN IF NOT EXISTS stripe_subscription_id TEXT UNIQUE;
