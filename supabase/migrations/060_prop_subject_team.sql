-- ============================================================================
-- get_event_player_props returns the subject's team
-- Migration: 060_prop_subject_team.sql
--
-- The game detail page lists prop subjects in one alphabetical column, which
-- reads as one undifferentiated roster. Splitting it into away and home needs
-- to know whose player each subject is, and the RPC did not say — it returned
-- the name and the balldontlie id and nothing about the team.
--
-- The chain already exists and is fully populated: markets.(subject_sport,
-- subject_player_id) -> bdl_players.(sport, bdl_player_id) -> bdl_team_id ->
-- bdl_teams.(sport, bdl_team_id) -> odds_api_name, which is by construction the
-- same string events.home_team / away_team hold. Verified against live data
-- before writing this: all 250 stored prop rows resolve, 120 away and 130 home,
-- none unmatched.
--
-- Both joins are LEFT. A subject whose team is missing must still return its
-- market — losing a priced line because a roster row is stale would be a far
-- worse failure than showing it in an "other" bucket.
--
-- DROP first: CREATE OR REPLACE cannot change a return type, and this adds an
-- OUT column. Postgres raises 42P13 rather than replacing. This bit 057.
-- ============================================================================

DROP FUNCTION IF EXISTS get_event_player_props(UUID);

CREATE FUNCTION get_event_player_props(p_event_id UUID)
RETURNS TABLE (
    id UUID, event_id UUID, type TEXT, side_a TEXT, side_b TEXT,
    odds_a NUMERIC, odds_b NUMERIC,
    stat_key TEXT, subject_name TEXT, subject_player_id INTEGER,
    subject_sport TEXT, bettable BOOLEAN, subject_team TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT m.id, m.event_id, m.type, m.side_a, m.side_b,
           m.odds_a, m.odds_b, m.stat_key, m.subject_name, m.subject_player_id,
           m.subject_sport, m.bettable,
           bt.odds_api_name AS subject_team
      FROM markets m
      LEFT JOIN bdl_players bp
             ON bp.sport = m.subject_sport
            AND bp.bdl_player_id = m.subject_player_id
      LEFT JOIN bdl_teams bt
             ON bt.sport = bp.sport
            AND bt.bdl_team_id = bp.bdl_team_id
     WHERE m.event_id = p_event_id
       AND m.type = ANY (legacy_client_hidden_market_types())
     ORDER BY m.subject_name, m.stat_key, m.side_a;
$$;

REVOKE ALL ON FUNCTION get_event_player_props(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_event_player_props(UUID) TO authenticated, service_role;

DO $$
DECLARE n INT;
BEGIN
    -- Assert the new column exists and actually resolves, rather than trusting
    -- that the joins were written correctly.
    SELECT count(*) INTO n
      FROM get_event_player_props(
          (SELECT event_id FROM markets WHERE type = 'player_prop' LIMIT 1)
      )
     WHERE subject_team IS NOT NULL;
    IF n = 0 THEN
        RAISE EXCEPTION '060: subject_team resolved for no rows — the join is wrong';
    END IF;
    RAISE NOTICE '060: subject_team returned, % rows resolved on the probe event', n;
END $$;
