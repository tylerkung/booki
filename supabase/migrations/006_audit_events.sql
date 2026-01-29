-- ============================================================================
-- Audit Events Table
-- Migration: 006_audit_events.sql
-- Description: Comprehensive audit log for all state changes in the system
-- ============================================================================

-- ============================================================================
-- AUDIT_EVENTS TABLE
-- Stores immutable audit records of all state changes for traceability
-- ============================================================================
CREATE TABLE IF NOT EXISTS audit_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bookie_id UUID REFERENCES bookies(id) ON DELETE CASCADE NOT NULL,
    actor_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    entity_type TEXT NOT NULL,
    entity_id UUID NOT NULL,
    action_type TEXT NOT NULL,
    previous_state JSONB,
    new_state JSONB NOT NULL,
    reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for fast lookups by entity (bookie_id, entity_type, entity_id)
CREATE INDEX IF NOT EXISTS idx_audit_events_entity ON audit_events(bookie_id, entity_type, entity_id);

-- Index for timeline queries (bookie_id, created_at)
CREATE INDEX IF NOT EXISTS idx_audit_events_timeline ON audit_events(bookie_id, created_at);

-- ============================================================================
-- ENABLE ROW LEVEL SECURITY
-- ============================================================================
ALTER TABLE audit_events ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- AUDIT_EVENTS TABLE POLICIES
-- Bookies can only SELECT audit events where bookie_id matches their bookie record
-- No INSERT/UPDATE/DELETE via RLS - Edge Functions use service role
-- ============================================================================

-- SELECT: Bookies can only see audit events for their own bookie_id
CREATE POLICY audit_events_select_own ON audit_events
    FOR SELECT
    USING (
        bookie_id IN (
            SELECT id FROM bookies WHERE auth_user_id = auth.uid()
        )
    );

-- No INSERT/UPDATE/DELETE policies - Edge Functions use service role to insert audit events

-- ============================================================================
-- COMMENTS
-- ============================================================================
COMMENT ON TABLE audit_events IS 'Immutable audit log of all state changes for traceability';
COMMENT ON COLUMN audit_events.bookie_id IS 'The bookie this audit event belongs to';
COMMENT ON COLUMN audit_events.actor_user_id IS 'The user who performed the action (auth.users reference)';
COMMENT ON COLUMN audit_events.entity_type IS 'Type of entity: bet, ledger_entry, player, event';
COMMENT ON COLUMN audit_events.entity_id IS 'UUID of the entity that was modified';
COMMENT ON COLUMN audit_events.action_type IS 'Type of action: create, accept, grade, settle, adjust, reverse, override';
COMMENT ON COLUMN audit_events.previous_state IS 'JSON snapshot of entity state before the action (null for create)';
COMMENT ON COLUMN audit_events.new_state IS 'JSON snapshot of entity state after the action';
COMMENT ON COLUMN audit_events.reason IS 'Optional reason for the action (used for reversals, overrides, adjustments)';
COMMENT ON COLUMN audit_events.created_at IS 'Timestamp when the audit event was recorded';

COMMENT ON POLICY audit_events_select_own ON audit_events IS 'Bookies can only read audit events for their own bookie';
