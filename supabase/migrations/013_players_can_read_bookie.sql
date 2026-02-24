-- Migration: Allow players to read their bookie's record
-- Players need to fetch bookie settings (e.g. allow_futures_parlays) during sync
--
-- Cannot use a direct subquery on `players` table because `players` RLS calls
-- `is_bookie()` which queries `bookies` → infinite recursion.
-- Solution: SECURITY DEFINER function bypasses RLS to look up the player's bookie_id.

-- Drop the recursive policy first
DROP POLICY IF EXISTS bookies_select_by_player ON bookies;

-- Helper function: get the bookie_id for the current auth user if they are a player
CREATE OR REPLACE FUNCTION get_player_bookie_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT bookie_id FROM players WHERE auth_user_id = auth.uid() LIMIT 1;
$$;

-- Players can read the bookie record they belong to
CREATE POLICY bookies_select_by_player ON bookies
    FOR SELECT
    USING (id = get_player_bookie_id());

COMMENT ON POLICY bookies_select_by_player ON bookies IS 'Players can read the bookie record they belong to';
