-- ============================================================================
-- Idempotency Keys Table
-- Migration: 004_idempotency_keys.sql
-- Description: Stores idempotency keys for Edge Functions to prevent duplicate operations
-- ============================================================================

-- ============================================================================
-- IDEMPOTENCY_KEYS TABLE
-- Stores idempotency keys with cached responses for deduplication
-- ============================================================================
CREATE TABLE IF NOT EXISTS idempotency_keys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    key TEXT NOT NULL,
    operation TEXT NOT NULL,
    response TEXT NOT NULL,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '24 hours'),
    UNIQUE(key, operation)
);

-- Index for fast lookup by key and operation
CREATE INDEX IF NOT EXISTS idx_idempotency_keys_key_operation ON idempotency_keys(key, operation);

-- Index for cleanup of expired keys
CREATE INDEX IF NOT EXISTS idx_idempotency_keys_expires_at ON idempotency_keys(expires_at);

-- ============================================================================
-- NO RLS - Service role access only
-- Edge Functions use service role key to access this table
-- ============================================================================

COMMENT ON TABLE idempotency_keys IS 'Stores idempotency keys for Edge Functions to prevent duplicate operations';
COMMENT ON COLUMN idempotency_keys.key IS 'Client-provided idempotency key (usually UUID)';
COMMENT ON COLUMN idempotency_keys.operation IS 'Name of the operation (e.g., submit_bet, accept_bet)';
COMMENT ON COLUMN idempotency_keys.response IS 'Cached JSON response to return for duplicate requests';
COMMENT ON COLUMN idempotency_keys.user_id IS 'User who initiated the request';
COMMENT ON COLUMN idempotency_keys.expires_at IS 'When this key expires and can be cleaned up';
