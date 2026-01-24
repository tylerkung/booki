-- ============================================================================
-- Booki Multi-Tenant Database Schema
-- Migration: 001_initial_schema.sql
-- Description: Foundation schema with all tables and bookie_id for tenant isolation
-- ============================================================================

-- ============================================================================
-- BOOKIES TABLE
-- Stores bookie account information, linked to Supabase auth.users
-- ============================================================================
CREATE TABLE IF NOT EXISTS bookies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    auth_user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL UNIQUE,
    name TEXT NOT NULL,
    email TEXT,
    subscription_status TEXT NOT NULL DEFAULT 'trial',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for fast lookup by auth user
CREATE INDEX IF NOT EXISTS idx_bookies_auth_user_id ON bookies(auth_user_id);

-- ============================================================================
-- PLAYERS TABLE
-- Stores player accounts that belong to a bookie
-- ============================================================================
CREATE TABLE IF NOT EXISTS players (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bookie_id UUID REFERENCES bookies(id) ON DELETE CASCADE NOT NULL,
    auth_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    name TEXT NOT NULL,
    email TEXT,
    credit_limit DECIMAL(15, 2) NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'active',
    collection_status TEXT,
    collection_status_date TIMESTAMPTZ,
    promised_payment_date TIMESTAMPTZ,
    username TEXT,
    password_hash TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for tenant isolation queries
CREATE INDEX IF NOT EXISTS idx_players_bookie_id ON players(bookie_id);
-- Index for player authentication lookup
CREATE INDEX IF NOT EXISTS idx_players_auth_user_id ON players(auth_user_id);
-- Index for player status filtering
CREATE INDEX IF NOT EXISTS idx_players_status ON players(status);

-- ============================================================================
-- EVENTS TABLE
-- Stores sports events that bets can be placed on
-- ============================================================================
CREATE TABLE IF NOT EXISTS events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bookie_id UUID REFERENCES bookies(id) ON DELETE CASCADE NOT NULL,
    name TEXT NOT NULL,
    sport TEXT NOT NULL,
    league TEXT,
    start_time TIMESTAMPTZ NOT NULL,
    status TEXT NOT NULL DEFAULT 'scheduled',
    home_team TEXT NOT NULL,
    away_team TEXT NOT NULL,
    final_score TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for tenant isolation queries
CREATE INDEX IF NOT EXISTS idx_events_bookie_id ON events(bookie_id);
-- Index for filtering by status
CREATE INDEX IF NOT EXISTS idx_events_status ON events(status);
-- Index for filtering by start time
CREATE INDEX IF NOT EXISTS idx_events_start_time ON events(start_time);
-- Index for filtering by sport
CREATE INDEX IF NOT EXISTS idx_events_sport ON events(sport);

-- ============================================================================
-- BETS TABLE
-- Stores all bets placed by players
-- ============================================================================
CREATE TABLE IF NOT EXISTS bets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bookie_id UUID REFERENCES bookies(id) ON DELETE CASCADE NOT NULL,
    player_id UUID REFERENCES players(id) ON DELETE CASCADE NOT NULL,
    event_id TEXT NOT NULL,
    ticket_id UUID NOT NULL,
    market TEXT,
    side TEXT NOT NULL,
    odds INT NOT NULL,
    stake DECIMAL(15, 2) NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    grade_result TEXT,
    is_parlay BOOLEAN NOT NULL DEFAULT FALSE,
    parlay_legs INT NOT NULL DEFAULT 1,
    policy_violation_reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for tenant isolation queries
CREATE INDEX IF NOT EXISTS idx_bets_bookie_id ON bets(bookie_id);
-- Index for player bets lookup
CREATE INDEX IF NOT EXISTS idx_bets_player_id ON bets(player_id);
-- Index for ticket grouping
CREATE INDEX IF NOT EXISTS idx_bets_ticket_id ON bets(ticket_id);
-- Index for status filtering
CREATE INDEX IF NOT EXISTS idx_bets_status ON bets(status);
-- Index for event lookup
CREATE INDEX IF NOT EXISTS idx_bets_event_id ON bets(event_id);

-- ============================================================================
-- LEDGER_ENTRIES TABLE
-- Append-only ledger for tracking all balance changes
-- ============================================================================
CREATE TABLE IF NOT EXISTS ledger_entries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bookie_id UUID REFERENCES bookies(id) ON DELETE CASCADE NOT NULL,
    player_id UUID REFERENCES players(id) ON DELETE CASCADE NOT NULL,
    bet_id UUID REFERENCES bets(id) ON DELETE SET NULL,
    amount DECIMAL(15, 2) NOT NULL,
    type TEXT NOT NULL,
    description TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for tenant isolation queries
CREATE INDEX IF NOT EXISTS idx_ledger_entries_bookie_id ON ledger_entries(bookie_id);
-- Index for player ledger lookup
CREATE INDEX IF NOT EXISTS idx_ledger_entries_player_id ON ledger_entries(player_id);
-- Index for bet association
CREATE INDEX IF NOT EXISTS idx_ledger_entries_bet_id ON ledger_entries(bet_id);
-- Index for type filtering
CREATE INDEX IF NOT EXISTS idx_ledger_entries_type ON ledger_entries(type);

-- ============================================================================
-- ACCEPTANCE_POLICIES TABLE
-- Stores bookie's acceptance policy configuration (one per bookie)
-- ============================================================================
CREATE TABLE IF NOT EXISTS acceptance_policies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bookie_id UUID REFERENCES bookies(id) ON DELETE CASCADE NOT NULL UNIQUE,
    max_stake DECIMAL(15, 2) NOT NULL DEFAULT 100,
    require_approval_above DECIMAL(15, 2),
    auto_accept_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    auto_accept_new_players BOOLEAN NOT NULL DEFAULT FALSE,
    new_player_bet_threshold INT NOT NULL DEFAULT 5,
    auto_accept_parlays BOOLEAN NOT NULL DEFAULT FALSE,
    parlay_max_legs INT NOT NULL DEFAULT 4,
    event_lock_offset_minutes INT NOT NULL DEFAULT 0,
    parlay_push_void_policy TEXT NOT NULL DEFAULT 'reduceLegReprice',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for tenant isolation queries (also used by UNIQUE constraint)
CREATE INDEX IF NOT EXISTS idx_acceptance_policies_bookie_id ON acceptance_policies(bookie_id);

-- ============================================================================
-- UPDATED_AT TRIGGER FUNCTION
-- Automatically updates updated_at column on row modification
-- ============================================================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply trigger to tables with updated_at
CREATE TRIGGER update_bookies_updated_at
    BEFORE UPDATE ON bookies
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_players_updated_at
    BEFORE UPDATE ON players
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_events_updated_at
    BEFORE UPDATE ON events
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_bets_updated_at
    BEFORE UPDATE ON bets
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_acceptance_policies_updated_at
    BEFORE UPDATE ON acceptance_policies
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- COMMENTS
-- ============================================================================
COMMENT ON TABLE bookies IS 'Bookie accounts linked to Supabase Auth users';
COMMENT ON TABLE players IS 'Player accounts belonging to a bookie';
COMMENT ON TABLE events IS 'Sports events that bets can be placed on';
COMMENT ON TABLE bets IS 'All bets placed by players';
COMMENT ON TABLE ledger_entries IS 'Append-only ledger tracking all balance changes';
COMMENT ON TABLE acceptance_policies IS 'Bookie acceptance policy configuration (one per bookie)';

COMMENT ON COLUMN bookies.auth_user_id IS 'Links to Supabase auth.users for authentication';
COMMENT ON COLUMN players.bookie_id IS 'Tenant isolation - which bookie owns this player';
COMMENT ON COLUMN players.auth_user_id IS 'Optional link to auth.users for player login';
COMMENT ON COLUMN events.bookie_id IS 'Tenant isolation - which bookie created this event';
COMMENT ON COLUMN bets.bookie_id IS 'Tenant isolation - redundant for RLS efficiency';
COMMENT ON COLUMN bets.ticket_id IS 'Groups bets placed in same submission';
COMMENT ON COLUMN ledger_entries.bookie_id IS 'Tenant isolation - redundant for RLS efficiency';
COMMENT ON COLUMN acceptance_policies.bookie_id IS 'One policy per bookie (UNIQUE constraint)';
