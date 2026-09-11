-- ============================================================================
-- get_event_player_props returns the subject's team
-- Migration: 060_prop_subject_team.sql
--
-- The game detail page lists prop subjects in one alphabetical column, which
-- reads as one undifferentiated roster. Splitting it into away and home needs
-- to know whose player each subject is, and the RPC did not say — it returned
-- the name and the balldontlie id and nothing about the team.
--
-- The chain: markets.(subject_sport, subject_player_id) -> bdl_players.(sport,
-- bdl_player_id) -> bdl_team_id -> bdl_teams.(sport, bdl_team_id) ->
-- odds_api_name, which is by construction the same string events.home_team /
-- away_team hold. Verified against live data: all 250 prop rows stored at the
-- time resolved, 120 away and 130 home, none unmatched.
--
-- ASSERTING THIS IS HARDER THAN IT LOOKS, and the first version of this
-- migration got it wrong. It probed `markets WHERE type = 'player_prop' LIMIT 1`
-- and failed with "the join is wrong" when that returned nothing. The join was
-- fine. markets.player_prop is a VOLATILE table: rows are ingested for games
-- inside a two-day window and pruned the moment the game goes final, so it is
-- legitimately EMPTY for long stretches — every MLB game ingested two days
-- earlier had been played and swept, and NFL plays weekly so its slate sits
-- outside the ingest window most of the time. A schema migration must not
-- depend on the current contents of a table that empties itself on purpose.
--
-- So the assertion below tests the join against bdl_players and bdl_teams, which
-- are caches that only grow, and checks the prop rows only if any happen to
-- exist. It is re-runnable on an empty slate, which is the normal state.
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
DECLARE
    v_has_col  INT;
    v_chain    INT;
    v_broken   INT;
    v_props    INT;
    v_resolved INT;
BEGIN
    -- 1. The column exists. This is the part that is actually being added, and
    --    it is checkable whether or not a single prop row exists anywhere.
    SELECT count(*) INTO v_has_col
      FROM pg_proc
     WHERE proname = 'get_event_player_props'
       AND proargnames @> ARRAY['subject_team'];
    IF v_has_col = 0 THEN
        RAISE EXCEPTION '060: get_event_player_props has no subject_team column';
    END IF;

    -- 2. The join resolves. Tested against the caches rather than against
    --    markets: bdl_players and bdl_teams only ever grow, so this is a real
    --    test of the (sport, id) join on every day of the year. A player whose
    --    team does not resolve is the failure this is looking for — it is how
    --    the pre-056 single-column key would have shown up, and how identity
    --    drift will show up later.
    SELECT count(*) INTO v_chain FROM bdl_players bp
      JOIN bdl_teams bt ON bt.sport = bp.sport AND bt.bdl_team_id = bp.bdl_team_id;
    SELECT count(*) INTO v_broken FROM bdl_players bp
      LEFT JOIN bdl_teams bt ON bt.sport = bp.sport AND bt.bdl_team_id = bp.bdl_team_id
     WHERE bp.bdl_team_id IS NOT NULL AND bt.bdl_team_id IS NULL;

    IF v_chain = 0 THEN
        RAISE EXCEPTION '060: no cached player resolves to a team — the join is wrong';
    END IF;
    IF v_broken > 0 THEN
        RAISE EXCEPTION '060: % cached players have a team id that matches no team', v_broken;
    END IF;

    -- 3. If prop rows happen to exist, check them too. Not required: see the
    --    header. Reported either way, because "0 prop rows" is worth seeing in
    --    the output rather than inferring from a silent pass.
    SELECT count(*) INTO v_props FROM markets WHERE type = 'player_prop';
    IF v_props > 0 THEN
        SELECT count(*) INTO v_resolved
          FROM get_event_player_props(
              (SELECT event_id FROM markets WHERE type = 'player_prop' LIMIT 1))
         WHERE subject_team IS NOT NULL;
        IF v_resolved = 0 THEN
            RAISE EXCEPTION '060: % prop rows exist but none resolved a team', v_props;
        END IF;
        RAISE NOTICE '060: ok — % cached players resolve; % of the probe event''s rows have a team',
                     v_chain, v_resolved;
    ELSE
        RAISE NOTICE '060: ok — % cached players resolve. No prop rows stored right now (the ingest window is empty); the column and join are still verified.',
                     v_chain;
    END IF;
END $$;
