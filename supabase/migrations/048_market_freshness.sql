-- ============================================================================
-- 048 — Make the superseded-line guard mean what it says
--
-- THE GUARD. submit_bet / submit_bets / submit_parlay refuse a market whose
-- updated_at trails a reference by >15 min. It exists because market rows are
-- keyed event + type + LINE VALUE, so a spread moving -3 -> -3.5 INSERTS a new
-- row and never touches the old one. The -3 row lingers, still bettable, frozen
-- at a stale price, and it passes a pure odds comparison because its odds
-- genuinely are what that row says. Trailing the last write is how it gives
-- itself away.
--
-- TWO THINGS WERE WRONG.
--
-- 1. markets had NO updated_at trigger — the only table with an updated_at
--    column and no trigger to maintain it (bookies, players, events, bets and
--    acceptance_policies all have one from migration 001). So the column meant
--    "when this row was INSERTED", never "when it was last priced", while the
--    guard read it as the latter. Confirmed against production, not inferred:
--    pg_trigger held no non-internal trigger on markets.
--
-- 2. The reference was events.last_odds_update, which only sync_games and
--    auto_refresh_games write. That is one timestamp describing several
--    pipelines running at different cadences, so it cannot answer "was this row
--    in the latest feed of ITS OWN kind".
--
-- WHAT THAT COST, measured in production before this migration:
--
--   outright     705 of 705 markets rejected   <- every futures bet, refused
--   moneyline      9 of  53
--   player_prop    0 of  35   (only because those events are far enough out
--                              that auto_refresh_games has not touched them
--                              yet; every prop fails once a game nears)
--
-- The World Series winner markets were inserted 2026-02-24 and their updated_at
-- had not moved since, against a last_odds_update 30 minutes old — 4,370 hours
-- behind. Their PRICES were current the whole time; only the timestamp lied.
--
-- THE FIX, in two parts:
--
-- (a) a trigger, so updated_at finally means "last written";
-- (b) superseded_market_ids(), which compares a market against its SIBLINGS —
--     the markets of the same type on the same event — instead of an
--     event-wide timestamp. Siblings are written by one pipeline in one pass,
--     so they answer the question the guard is actually asking, and no cadence
--     is baked in anywhere. Adding a third pipeline later needs no new column.
--
-- Note outrights never needed the guard at all: auto_refresh_games removes a
-- withdrawn selection by DELETING the row (skipping any with active bets), so
-- a stale outright cannot linger the way an orphaned spread does. Under (b)
-- they stop being rejected because every still-offered selection is updated on
-- each refresh and so shares a write time.
--
-- Idempotent throughout — per CLAUDE.md the Supabase SQL editor does not wrap a
-- script in a transaction, so each statement commits on its own and the script
-- must be safe to re-run after a partial failure.
-- ============================================================================

-- (a) -----------------------------------------------------------------------
DROP TRIGGER IF EXISTS update_markets_updated_at ON markets;
CREATE TRIGGER update_markets_updated_at
    BEFORE UPDATE ON markets
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- markets was the table this migration is about, but the same audit found three
-- more with an updated_at column and nothing maintaining it. prop_grading_runs
-- is the one that mattered — grade_player_props upserts it, so a re-run left
-- updated_at showing the first attempt. The other two are written rarely, but a
-- column that means "last written" on four tables and "inserted" on three is
-- the trap this whole migration exists to close.
DROP TRIGGER IF EXISTS update_prop_grading_runs_updated_at ON prop_grading_runs;
CREATE TRIGGER update_prop_grading_runs_updated_at
    BEFORE UPDATE ON prop_grading_runs
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_device_tokens_updated_at ON device_tokens;
CREATE TRIGGER update_device_tokens_updated_at
    BEFORE UPDATE ON device_tokens
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_bdl_teams_updated_at ON bdl_teams;
CREATE TRIGGER update_bdl_teams_updated_at
    BEFORE UPDATE ON bdl_teams
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- (b) -----------------------------------------------------------------------
-- Returns the subset of the given markets that trail their siblings, i.e. the
-- rows the caller must refuse. Kept in SQL so the window function has one
-- definition rather than a copy inside each of the three submit endpoints.
--
-- A market with no sibling newer than itself is never returned, which is the
-- deliberate fail-open case: if a pipeline stops running entirely, its markets
-- all age together and none is judged superseded. That is a monitoring problem,
-- not something to encode here — the alternative (an absolute age ceiling)
-- would re-break futures, which are legitimately weeks old.
CREATE OR REPLACE FUNCTION superseded_market_ids(
    p_market_ids UUID[],
    p_grace_minutes INTEGER DEFAULT 15
)
RETURNS TABLE (market_id UUID)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    WITH targets AS (
        SELECT id, event_id, type, updated_at
        FROM markets
        WHERE id = ANY(p_market_ids)
    ),
    newest AS (
        SELECT m.event_id, m.type, max(m.updated_at) AS newest_write
        FROM markets m
        WHERE (m.event_id, m.type) IN (SELECT t.event_id, t.type FROM targets t)
        GROUP BY m.event_id, m.type
    )
    SELECT t.id
    FROM targets t
    JOIN newest n ON n.event_id = t.event_id AND n.type = t.type
    WHERE t.updated_at < n.newest_write - make_interval(mins => greatest(p_grace_minutes, 0));
$$;

REVOKE ALL ON FUNCTION superseded_market_ids(UUID[], INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION superseded_market_ids(UUID[], INTEGER) TO service_role;

COMMENT ON FUNCTION superseded_market_ids IS
    'Markets that trail their same-event same-type siblings and must be refused at submit time. Replaces comparing against events.last_odds_update, which described only one of several pipelines.';

-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_trigger INTEGER;
    v_before  INTEGER;
    v_after   INTEGER;
BEGIN
    SELECT count(*) INTO v_trigger
    FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
    WHERE c.relname = 'markets' AND NOT t.tgisinternal
      AND t.tgname = 'update_markets_updated_at';
    IF v_trigger <> 1 THEN
        RAISE EXCEPTION 'markets updated_at trigger not installed (found %)', v_trigger;
    END IF;

    -- The old model against every live outright, versus the new one. This is
    -- the regression the migration exists to undo, so assert it rather than
    -- trusting the reasoning above.
    SELECT count(*) INTO v_before
    FROM markets m JOIN events e ON e.id = m.event_id
    WHERE m.type = 'outright' AND e.status <> 'final'
      AND m.updated_at < e.last_odds_update - interval '15 min';

    SELECT count(*) INTO v_after
    FROM superseded_market_ids(
        ARRAY(SELECT m.id FROM markets m JOIN events e ON e.id = m.event_id
              WHERE m.type = 'outright' AND e.status <> 'final')
    );

    IF v_after >= v_before AND v_before > 0 THEN
        RAISE EXCEPTION 'sibling model did not improve outrights: % -> %', v_before, v_after;
    END IF;

    RAISE NOTICE 'trigger installed; outrights refused: % (old model) -> % (sibling model)', v_before, v_after;
    RAISE NOTICE 'the remaining ones collapse once a refresh runs and bumps every selection together';
END $$;
