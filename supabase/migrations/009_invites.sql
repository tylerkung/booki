-- ============================================================================
-- Invites Table
-- Migration: 009_invites.sql
-- Description: Lightweight invite model for bookie-to-player invite flow
-- ============================================================================

-- ============================================================================
-- INVITES TABLE
-- Tracks invite lifecycle: creation by bookie, claiming by player
-- ============================================================================
CREATE TABLE IF NOT EXISTS invites (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bookie_id UUID NOT NULL REFERENCES bookies(id) ON DELETE CASCADE,
    invite_code TEXT UNIQUE NOT NULL,
    email TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    claimed_at TIMESTAMPTZ,
    claimed_by_player_id UUID REFERENCES players(id) ON DELETE SET NULL,
    version INT NOT NULL DEFAULT 0
);

-- Index on invite_code for fast lookups during claim flow
CREATE INDEX IF NOT EXISTS idx_invites_invite_code ON invites(invite_code);

-- Index for bookie's invite list queries
CREATE INDEX IF NOT EXISTS idx_invites_bookie_id ON invites(bookie_id);

-- ============================================================================
-- ENABLE ROW LEVEL SECURITY
-- ============================================================================
ALTER TABLE invites ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- INVITES TABLE POLICIES
-- ============================================================================

-- SELECT: Bookies can read their own invites
CREATE POLICY invites_select_own ON invites
    FOR SELECT
    USING (
        bookie_id IN (
            SELECT id FROM bookies WHERE auth_user_id = auth.uid()
        )
    );

-- INSERT: Bookies can create invites for themselves
CREATE POLICY invites_insert_own ON invites
    FOR INSERT
    WITH CHECK (
        bookie_id IN (
            SELECT id FROM bookies WHERE auth_user_id = auth.uid()
        )
    );

-- No UPDATE/DELETE policies via RLS — Edge Functions use service role for claiming

-- ============================================================================
-- COMMENTS
-- ============================================================================
COMMENT ON TABLE invites IS 'Invite records for bookie-to-player invite flow';
COMMENT ON COLUMN invites.bookie_id IS 'The bookie who created this invite';
COMMENT ON COLUMN invites.invite_code IS 'Unique 8-character invite code (A-Z, 2-9)';
COMMENT ON COLUMN invites.email IS 'Optional email the invite was sent to';
COMMENT ON COLUMN invites.expires_at IS 'When the invite expires (24 hours after creation)';
COMMENT ON COLUMN invites.claimed_at IS 'When the invite was claimed by a player (NULL if pending)';
COMMENT ON COLUMN invites.claimed_by_player_id IS 'The player who claimed this invite';
COMMENT ON COLUMN invites.version IS 'Optimistic concurrency version for sync';
