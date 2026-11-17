-- ============================================================================
-- 064 — One shared main line per event and type
--
-- THE BUG. A spread (and a total) was stored under a key that included the
-- line value: event + type + "+11.5". The number moving to +12.5 INSERTED a
-- new row and never touched the old one. sync_games has no step that retires
-- the previous main line. auto_refresh_games deletes a withdrawn line only
-- for games it actually refreshes, and only when that delete succeeds, so a
-- line that moved between syncs stayed bettable forever.
--
-- Colts @ Texans, 19 Nov 2026, event 672953b5, had four live shared spread
-- rows at once (+10, +10.5, +11.5, +12.5), each with its own updated_at. The
-- board query is unordered, so it showed +11.5 from 08:00Z. submit_bets
-- refused it: superseded_market_ids (migration 048) saw the 20:00Z sibling
-- and returned that market. The client mapped the error to
-- "One of these games is no longer available".
--
-- WHAT THIS MIGRATION DOES. Two things, neither of which rewrites a market.
--
-- 1. markets.main_line, nullable, plus a partial unique index on
--    (event_id, type) WHERE main_line IS TRUE AND bookie_id IS NULL. Existing
--    rows stay NULL, so the index builds on top of the duplicates instead of
--    failing on them. The next sync_games / auto_refresh_games run is what
--    flags the current row TRUE and the others FALSE. A unique index on
--    (event_id, type) itself cannot be created while those duplicates are
--    still bettable, and this file does not clean them up.
--
-- 2. superseded_market_ids ignores bettable = false. Retiring a row is an
--    UPDATE, and the updated_at trigger then makes the retired row look like
--    the newest sibling. Without this exclusion the live line would start
--    failing the guard the moment the old ones were retired.
--
-- Apply this BEFORE deploying sync_games or auto_refresh_games. Those
-- functions write main_line. Deploying them first makes every market write
-- fail on the unknown column, and the odds sync stops.
--
-- Idempotent. The SQL editor does not wrap a script in a transaction, so a
-- re-run after a partial failure must be safe. Nothing here updates, deletes,
-- or backfills markets.
-- ============================================================================

ALTER TABLE markets
    ADD COLUMN IF NOT EXISTS main_line BOOLEAN;

COMMENT ON COLUMN markets.main_line IS
  'TRUE on the single shared moneyline, spread, or total currently offered for an event. '
  'NULL on rows written before migration 064 and on every market that is not a main line '
  '(alternates, team totals, props, outrights). FALSE on a previous main line the ingest '
  'has retired. Partial unique index markets_one_shared_main_line allows one TRUE per '
  '(event_id, type) among shared rows. The ingest sets it; this migration does not.';

CREATE UNIQUE INDEX IF NOT EXISTS markets_one_shared_main_line
    ON markets (event_id, type)
    WHERE main_line IS TRUE AND bookie_id IS NULL;

-- Sibling freshness. Same signature as migration 048, so CREATE OR REPLACE
-- is enough — a new OUT column would need DROP FUNCTION first (42P13).
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
        -- Unbettable rows are retired main lines (or an ungradeable prop).
        -- Their updated_at moves when they are retired, which would otherwise
        -- make them the "newest" sibling and refuse the line that replaced them.
        SELECT m.event_id, m.type, max(m.updated_at) AS newest_write
        FROM markets m
        WHERE (m.event_id, m.type) IN (SELECT t.event_id, t.type FROM targets t)
          AND m.bettable IS DISTINCT FROM FALSE
        GROUP BY m.event_id, m.type
    )
    SELECT t.id
    FROM targets t
    JOIN newest n ON n.event_id = t.event_id AND n.type = t.type
    WHERE t.updated_at < n.newest_write - make_interval(mins => greatest(p_grace_minutes, 0));
$$;

COMMENT ON FUNCTION superseded_market_ids IS
    'Markets that trail the newest bettable sibling of the same event and type and must be refused at submit time. Unbettable rows are not siblings: retiring one must not make the live line look stale.';

-- ---------------------------------------------------------------------------
-- Read-only. Lists every shared main line that still has a bettable duplicate.
-- Not executed by this migration. Run it in the SQL editor before and after
-- the next sync_games / auto_refresh_games deploy to see the pile collapse.
--
-- SELECT e.id AS event_id,
--        e.away_team,
--        e.home_team,
--        e.start_time,
--        m.type,
--        m.id AS market_id,
--        m.side_a,
--        m.side_b,
--        m.odds_a,
--        m.odds_b,
--        m.updated_at,
--        m.bettable,
--        m.main_line
--   FROM markets m
--   JOIN events e ON e.id = m.event_id
--  WHERE m.bookie_id IS NULL
--    AND m.type IN ('moneyline', 'spread', 'total')
--    AND m.bettable IS DISTINCT FROM FALSE
--    AND e.status IS DISTINCT FROM 'final'
--    AND (m.event_id, m.type) IN (
--          SELECT m2.event_id, m2.type
--            FROM markets m2
--           WHERE m2.bookie_id IS NULL
--             AND m2.type IN ('moneyline', 'spread', 'total')
--             AND m2.bettable IS DISTINCT FROM FALSE
--           GROUP BY m2.event_id, m2.type
--          HAVING count(*) > 1
--        )
--  ORDER BY e.start_time, m.type, m.updated_at DESC;
-- ---------------------------------------------------------------------------

DO $$
DECLARE
    v_col INTEGER;
    v_idx INTEGER;
    v_def TEXT;
BEGIN
    SELECT count(*) INTO v_col
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'markets'
      AND column_name = 'main_line';
    IF v_col <> 1 THEN
        RAISE EXCEPTION 'markets.main_line was not added (found %)', v_col;
    END IF;

    SELECT count(*) INTO v_idx
    FROM pg_indexes
    WHERE schemaname = 'public'
      AND indexname = 'markets_one_shared_main_line';
    IF v_idx <> 1 THEN
        RAISE EXCEPTION 'markets_one_shared_main_line was not created (found %)', v_idx;
    END IF;

    SELECT pg_get_functiondef('public.superseded_market_ids(uuid[], integer)'::regprocedure)
      INTO v_def;
    IF v_def IS NULL OR position('bettable' IN v_def) = 0 THEN
        RAISE EXCEPTION 'superseded_market_ids does not ignore unbettable rows';
    END IF;

    RAISE NOTICE '064 ok: main_line column, unique index, superseded_market_ids ignores bettable = false';
    RAISE NOTICE 'no market row was updated; run the commented duplicate-main-line query to see the current pile';
END $$;
