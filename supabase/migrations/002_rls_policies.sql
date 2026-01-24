-- ============================================================================
-- Booki Row Level Security Policies
-- Migration: 002_rls_policies.sql
-- Description: Enables RLS and creates policies for multi-tenant data isolation
-- ============================================================================

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- get_user_bookie_id(): Returns the bookie_id for the current authenticated user
-- This function is used by RLS policies to determine which bookie's data the user can access
-- Works for both bookies (via auth_user_id in bookies table) and players (via auth_user_id in players table)
CREATE OR REPLACE FUNCTION get_user_bookie_id()
RETURNS UUID
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
    -- First check if user is a bookie
    SELECT COALESCE(
        -- If user is a bookie, return their bookie.id
        (SELECT id FROM bookies WHERE auth_user_id = auth.uid()),
        -- If user is a player, return their bookie_id
        (SELECT bookie_id FROM players WHERE auth_user_id = auth.uid() LIMIT 1)
    );
$$;

COMMENT ON FUNCTION get_user_bookie_id() IS 'Returns bookie_id for current auth user (works for both bookies and players)';

-- is_bookie(): Returns true if current user is a bookie (not a player)
CREATE OR REPLACE FUNCTION is_bookie()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
    SELECT EXISTS (SELECT 1 FROM bookies WHERE auth_user_id = auth.uid());
$$;

COMMENT ON FUNCTION is_bookie() IS 'Returns true if current user is a bookie';

-- get_player_id(): Returns player_id for current auth user (if they are a player)
CREATE OR REPLACE FUNCTION get_player_id()
RETURNS UUID
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
    SELECT id FROM players WHERE auth_user_id = auth.uid() LIMIT 1;
$$;

COMMENT ON FUNCTION get_player_id() IS 'Returns player_id for current auth user if they are a player';

-- ============================================================================
-- ENABLE ROW LEVEL SECURITY
-- ============================================================================

ALTER TABLE bookies ENABLE ROW LEVEL SECURITY;
ALTER TABLE players ENABLE ROW LEVEL SECURITY;
ALTER TABLE events ENABLE ROW LEVEL SECURITY;
ALTER TABLE bets ENABLE ROW LEVEL SECURITY;
ALTER TABLE ledger_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE acceptance_policies ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- BOOKIES TABLE POLICIES
-- Bookies can only access their own record
-- ============================================================================

-- SELECT: Bookie can only see their own record
CREATE POLICY bookies_select_own ON bookies
    FOR SELECT
    USING (auth_user_id = auth.uid());

-- INSERT: New bookie record can only be created for the authenticated user
CREATE POLICY bookies_insert_own ON bookies
    FOR INSERT
    WITH CHECK (auth_user_id = auth.uid());

-- UPDATE: Bookie can only update their own record
CREATE POLICY bookies_update_own ON bookies
    FOR UPDATE
    USING (auth_user_id = auth.uid())
    WITH CHECK (auth_user_id = auth.uid());

-- DELETE: Bookie can only delete their own record
CREATE POLICY bookies_delete_own ON bookies
    FOR DELETE
    USING (auth_user_id = auth.uid());

-- ============================================================================
-- PLAYERS TABLE POLICIES
-- Bookies: Full CRUD on all their players
-- Players: Can only SELECT their own record
-- ============================================================================

-- SELECT: Bookie sees all their players, player sees only self
CREATE POLICY players_select ON players
    FOR SELECT
    USING (
        -- Bookie can see all players in their organization
        (is_bookie() AND bookie_id = get_user_bookie_id())
        OR
        -- Player can see their own record
        (auth_user_id = auth.uid())
    );

-- INSERT: Only bookies can create players
CREATE POLICY players_insert ON players
    FOR INSERT
    WITH CHECK (is_bookie() AND bookie_id = get_user_bookie_id());

-- UPDATE: Only bookies can update players (for their own organization)
CREATE POLICY players_update ON players
    FOR UPDATE
    USING (is_bookie() AND bookie_id = get_user_bookie_id())
    WITH CHECK (is_bookie() AND bookie_id = get_user_bookie_id());

-- DELETE: Only bookies can delete players (for their own organization)
CREATE POLICY players_delete ON players
    FOR DELETE
    USING (is_bookie() AND bookie_id = get_user_bookie_id());

-- ============================================================================
-- EVENTS TABLE POLICIES
-- Bookies: Full CRUD on their events
-- Players: Can SELECT events from their bookie
-- ============================================================================

-- SELECT: Bookie and players can see events from their organization
CREATE POLICY events_select ON events
    FOR SELECT
    USING (bookie_id = get_user_bookie_id());

-- INSERT: Only bookies can create events
CREATE POLICY events_insert ON events
    FOR INSERT
    WITH CHECK (is_bookie() AND bookie_id = get_user_bookie_id());

-- UPDATE: Only bookies can update events
CREATE POLICY events_update ON events
    FOR UPDATE
    USING (is_bookie() AND bookie_id = get_user_bookie_id())
    WITH CHECK (is_bookie() AND bookie_id = get_user_bookie_id());

-- DELETE: Only bookies can delete events
CREATE POLICY events_delete ON events
    FOR DELETE
    USING (is_bookie() AND bookie_id = get_user_bookie_id());

-- ============================================================================
-- BETS TABLE POLICIES
-- Bookies: Full CRUD on all bets in their organization
-- Players: Can SELECT own bets, can INSERT own bets (with their player_id)
-- ============================================================================

-- SELECT: Bookie sees all bets, player sees only own bets
CREATE POLICY bets_select ON bets
    FOR SELECT
    USING (
        -- Bookie can see all bets in their organization
        (is_bookie() AND bookie_id = get_user_bookie_id())
        OR
        -- Player can see their own bets
        (player_id = get_player_id() AND bookie_id = get_user_bookie_id())
    );

-- INSERT: Bookie can insert any bet, player can only insert their own bets
CREATE POLICY bets_insert ON bets
    FOR INSERT
    WITH CHECK (
        -- Bookie can insert any bet in their organization
        (is_bookie() AND bookie_id = get_user_bookie_id())
        OR
        -- Player can insert their own bets
        (player_id = get_player_id() AND bookie_id = get_user_bookie_id())
    );

-- UPDATE: Only bookies can update bets
CREATE POLICY bets_update ON bets
    FOR UPDATE
    USING (is_bookie() AND bookie_id = get_user_bookie_id())
    WITH CHECK (is_bookie() AND bookie_id = get_user_bookie_id());

-- DELETE: Only bookies can delete bets
CREATE POLICY bets_delete ON bets
    FOR DELETE
    USING (is_bookie() AND bookie_id = get_user_bookie_id());

-- ============================================================================
-- LEDGER_ENTRIES TABLE POLICIES
-- Bookies: Full CRUD on their ledger entries
-- Players: Can only SELECT their own ledger entries
-- ============================================================================

-- SELECT: Bookie sees all entries, player sees only own entries
CREATE POLICY ledger_entries_select ON ledger_entries
    FOR SELECT
    USING (
        -- Bookie can see all entries in their organization
        (is_bookie() AND bookie_id = get_user_bookie_id())
        OR
        -- Player can see their own entries
        (player_id = get_player_id() AND bookie_id = get_user_bookie_id())
    );

-- INSERT: Only bookies can insert ledger entries (or system via service role)
CREATE POLICY ledger_entries_insert ON ledger_entries
    FOR INSERT
    WITH CHECK (is_bookie() AND bookie_id = get_user_bookie_id());

-- UPDATE: Only bookies can update ledger entries
-- Note: In practice, ledger entries should be immutable (append-only),
-- but we allow bookie updates for corrections if needed
CREATE POLICY ledger_entries_update ON ledger_entries
    FOR UPDATE
    USING (is_bookie() AND bookie_id = get_user_bookie_id())
    WITH CHECK (is_bookie() AND bookie_id = get_user_bookie_id());

-- DELETE: Only bookies can delete ledger entries
-- Note: In practice, ledger entries should never be deleted
CREATE POLICY ledger_entries_delete ON ledger_entries
    FOR DELETE
    USING (is_bookie() AND bookie_id = get_user_bookie_id());

-- ============================================================================
-- ACCEPTANCE_POLICIES TABLE POLICIES
-- Only bookies can access their own acceptance policy (one per bookie)
-- ============================================================================

-- SELECT: Bookie can only see their own policy
CREATE POLICY acceptance_policies_select ON acceptance_policies
    FOR SELECT
    USING (is_bookie() AND bookie_id = get_user_bookie_id());

-- INSERT: Bookie can only insert their own policy
CREATE POLICY acceptance_policies_insert ON acceptance_policies
    FOR INSERT
    WITH CHECK (is_bookie() AND bookie_id = get_user_bookie_id());

-- UPDATE: Bookie can only update their own policy
CREATE POLICY acceptance_policies_update ON acceptance_policies
    FOR UPDATE
    USING (is_bookie() AND bookie_id = get_user_bookie_id())
    WITH CHECK (is_bookie() AND bookie_id = get_user_bookie_id());

-- DELETE: Bookie can only delete their own policy
CREATE POLICY acceptance_policies_delete ON acceptance_policies
    FOR DELETE
    USING (is_bookie() AND bookie_id = get_user_bookie_id());

-- ============================================================================
-- COMMENTS ON POLICIES
-- ============================================================================

COMMENT ON POLICY bookies_select_own ON bookies IS 'Bookie can only read their own record';
COMMENT ON POLICY bookies_insert_own ON bookies IS 'User can only create bookie record for themselves';
COMMENT ON POLICY bookies_update_own ON bookies IS 'Bookie can only update their own record';
COMMENT ON POLICY bookies_delete_own ON bookies IS 'Bookie can only delete their own record';

COMMENT ON POLICY players_select ON players IS 'Bookie sees all players, player sees only self';
COMMENT ON POLICY players_insert ON players IS 'Only bookies can create players';
COMMENT ON POLICY players_update ON players IS 'Only bookies can update players';
COMMENT ON POLICY players_delete ON players IS 'Only bookies can delete players';

COMMENT ON POLICY events_select ON events IS 'Bookie and players see events in their org';
COMMENT ON POLICY events_insert ON events IS 'Only bookies can create events';
COMMENT ON POLICY events_update ON events IS 'Only bookies can update events';
COMMENT ON POLICY events_delete ON events IS 'Only bookies can delete events';

COMMENT ON POLICY bets_select ON bets IS 'Bookie sees all bets, player sees own bets';
COMMENT ON POLICY bets_insert ON bets IS 'Bookie inserts any, player inserts own only';
COMMENT ON POLICY bets_update ON bets IS 'Only bookies can update bets';
COMMENT ON POLICY bets_delete ON bets IS 'Only bookies can delete bets';

COMMENT ON POLICY ledger_entries_select ON ledger_entries IS 'Bookie sees all, player sees own entries';
COMMENT ON POLICY ledger_entries_insert ON ledger_entries IS 'Only bookies insert ledger entries';
COMMENT ON POLICY ledger_entries_update ON ledger_entries IS 'Only bookies update ledger entries';
COMMENT ON POLICY ledger_entries_delete ON ledger_entries IS 'Only bookies delete ledger entries';

COMMENT ON POLICY acceptance_policies_select ON acceptance_policies IS 'Bookie only reads own policy';
COMMENT ON POLICY acceptance_policies_insert ON acceptance_policies IS 'Bookie only inserts own policy';
COMMENT ON POLICY acceptance_policies_update ON acceptance_policies IS 'Bookie only updates own policy';
COMMENT ON POLICY acceptance_policies_delete ON acceptance_policies IS 'Bookie only deletes own policy';
