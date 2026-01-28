-- ============================================================================
-- User Agreements Table
-- Migration: 003_user_agreements.sql
-- Description: Stores user agreement acceptances for legal acknowledgments
-- ============================================================================

-- ============================================================================
-- USER_AGREEMENTS TABLE
-- Stores immutable records of user agreement acceptances
-- ============================================================================
CREATE TABLE IF NOT EXISTS user_agreements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('bookie', 'player')),
    version TEXT NOT NULL,
    accepted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ip_address TEXT,
    user_agent TEXT
);

-- Index for fast lookup by user_id
CREATE INDEX IF NOT EXISTS idx_user_agreements_user_id ON user_agreements(user_id);
-- Index for filtering by version
CREATE INDEX IF NOT EXISTS idx_user_agreements_version ON user_agreements(version);

-- ============================================================================
-- ENABLE ROW LEVEL SECURITY
-- ============================================================================
ALTER TABLE user_agreements ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- USER_AGREEMENTS TABLE POLICIES
-- Users can only SELECT their own agreements
-- Authenticated users can INSERT their own agreements
-- No UPDATE or DELETE allowed (immutable)
-- ============================================================================

-- SELECT: Users can only see their own agreement records
CREATE POLICY user_agreements_select_own ON user_agreements
    FOR SELECT
    USING (user_id = auth.uid());

-- INSERT: Authenticated users can insert their own agreement records
CREATE POLICY user_agreements_insert_own ON user_agreements
    FOR INSERT
    WITH CHECK (user_id = auth.uid());

-- No UPDATE policy - agreements are immutable
-- No DELETE policy - agreements are immutable

-- ============================================================================
-- COMMENTS
-- ============================================================================
COMMENT ON TABLE user_agreements IS 'Immutable records of user agreement acceptances';
COMMENT ON COLUMN user_agreements.user_id IS 'References auth.users - which user accepted';
COMMENT ON COLUMN user_agreements.role IS 'User role at time of acceptance: bookie or player';
COMMENT ON COLUMN user_agreements.version IS 'Agreement version accepted (e.g., 1.0)';
COMMENT ON COLUMN user_agreements.accepted_at IS 'Timestamp when agreement was accepted';
COMMENT ON COLUMN user_agreements.ip_address IS 'Optional: IP address at time of acceptance';
COMMENT ON COLUMN user_agreements.user_agent IS 'Optional: User agent at time of acceptance';

COMMENT ON POLICY user_agreements_select_own ON user_agreements IS 'Users can only read their own agreement records';
COMMENT ON POLICY user_agreements_insert_own ON user_agreements IS 'Users can only insert their own agreement records';
