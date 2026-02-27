-- ============================================================================
-- Add Apple IAP columns and subscription_source to bookies table
-- Migration: 026_apple_iap_columns.sql
-- ============================================================================

-- Track which platform manages the subscription (prevents cross-platform webhook conflicts)
ALTER TABLE bookies ADD COLUMN IF NOT EXISTS subscription_source TEXT;

-- Store Apple's original transaction ID for subscription linking
ALTER TABLE bookies ADD COLUMN IF NOT EXISTS apple_original_transaction_id TEXT UNIQUE;

-- Add check constraint for valid subscription_source values
ALTER TABLE bookies ADD CONSTRAINT bookies_subscription_source_check
    CHECK (subscription_source IN ('apple', 'stripe') OR subscription_source IS NULL);

COMMENT ON COLUMN bookies.subscription_source IS 'Which platform manages this subscription: apple, stripe, or NULL (no active subscription)';
COMMENT ON COLUMN bookies.apple_original_transaction_id IS 'Apple StoreKit 2 original transaction ID for subscription linking';
