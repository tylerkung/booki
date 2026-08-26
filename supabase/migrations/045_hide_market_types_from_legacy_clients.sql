-- ============================================================================
-- 045 — Hide market types that shipped clients cannot render
--
-- THE PROBLEM this solves is not storage or quota. It is that
-- Booki/Services/SyncService.swift decodes a market with
--
--     MarketType(rawValue: record.type) ?? .moneyline
--
-- so any type the iOS enum lacks a case for is not ignored — it is SILENTLY
-- RELABELLED A MONEYLINE. A player prop reaches a shipped build as a moneyline
-- named "Patrick Mahomes Over 245.5", and odd/even as a moneyline whose sides
-- are Odd and No... Even. Grading is unaffected, because submit reads
-- market.type from the row rather than the client, but it is visibly wrong.
--
-- iOS is deprioritized, so waiting for a build is not the answer and would not
-- help the builds already installed regardless. The fix belongs on the server.
--
-- HOW: the read policy hides those types from ordinary clients. The service
-- role bypasses RLS, so ingest and grading are untouched. The web reaches them
-- through get_event_player_props() below, which is an explicit opt-in rather
-- than a table read every client shares.
--
-- Adding a type to the hidden list is a one-line change here, and REMOVING one
-- is how a future iOS release ships support for it. tasks/ios-pending.md tracks
-- which entries are waiting on that.
-- ============================================================================

CREATE OR REPLACE FUNCTION legacy_client_hidden_market_types()
RETURNS TEXT[]
LANGUAGE sql
IMMUTABLE
AS $$
    -- Types that iOS's MarketType enum has no case for. Anything listed here
    -- would be mislabelled rather than skipped, so it must not reach a client
    -- that reads the markets table directly.
    SELECT ARRAY['player_prop', 'odd_even']::TEXT[];
$$;

COMMENT ON FUNCTION legacy_client_hidden_market_types IS
    'Market types hidden from direct client reads because SyncService coerces unknown types to .moneyline instead of skipping them. Remove an entry when an iOS release can render it.';

DROP POLICY IF EXISTS markets_select ON markets;
CREATE POLICY markets_select ON markets
    FOR SELECT
    USING (
        (bookie_id = get_user_bookie_id() OR bookie_id IS NULL)
        AND NOT (type = ANY (legacy_client_hidden_market_types()))
    );

-- The web's explicit way in. Props are shared, public odds — there is no tenant
-- data here — so this returns them for any event to any signed-in caller, which
-- is exactly what the table read did before.
CREATE OR REPLACE FUNCTION get_event_player_props(p_event_id UUID)
RETURNS TABLE (
    id UUID, event_id UUID, type TEXT, side_a TEXT, side_b TEXT,
    odds_a NUMERIC, odds_b NUMERIC,
    stat_key TEXT, subject_name TEXT, subject_player_id INTEGER
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT m.id, m.event_id, m.type, m.side_a, m.side_b,
           m.odds_a, m.odds_b, m.stat_key, m.subject_name, m.subject_player_id
      FROM markets m
     WHERE m.event_id = p_event_id
       AND m.type = ANY (legacy_client_hidden_market_types())
     ORDER BY m.subject_name, m.stat_key, m.side_a;
$$;

REVOKE ALL ON FUNCTION get_event_player_props(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_event_player_props(UUID) TO authenticated, service_role;

DO $$
DECLARE
    n INT;
BEGIN
    SELECT count(*) INTO n FROM pg_policies
     WHERE tablename = 'markets' AND policyname = 'markets_select';
    IF n <> 1 THEN
        RAISE EXCEPTION 'markets_select policy missing after rewrite';
    END IF;
    RAISE NOTICE 'hidden from direct client reads: %', legacy_client_hidden_market_types();
    RAISE NOTICE 'web reaches them via get_event_player_props(event_id)';
END $$;
