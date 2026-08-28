-- ============================================================================
-- markets.bettable — priced, shown, but not accepted
-- Migration: 057_market_bettable_flag.sql
--
-- WHY
-- ---
-- MLB player props can be PRICED but not SETTLED. The Odds API quotes 21 of
-- them (measured 2026-08-28: batter_total_bases at 6 books, pitcher_strikeouts
-- at 6, and so on), but balldontlie's /mlb/v1/stats returns 401 on the current
-- plan while /nfl/v1/stats and /nba/v1/stats return 200. No statline means no
-- box score means nothing to settle against.
--
-- Showing them anyway is deliberate: it proves ingest, identity resolution and
-- display end to end while the season is on, and it is how members discover the
-- markets exist. Accepting a bet on one would not be -- there would be no way
-- to grade it, and an ungradeable bet is worse than an absent market.
--
-- The flag is a COLUMN rather than a rule computed in two places. The client
-- must disable the control and the submit endpoints must refuse the wager, and
-- those two answers drifting apart is the failure this avoids. One writer (the
-- ingest), two readers.
--
-- Flip to true when the settlement path exists. Nothing else has to change.
-- ============================================================================

ALTER TABLE markets
    ADD COLUMN IF NOT EXISTS bettable BOOLEAN NOT NULL DEFAULT TRUE;

COMMENT ON COLUMN markets.bettable IS
  'FALSE when a market can be priced and displayed but not graded, so no wager '
  'may be accepted on it. Set by the ingest. MLB player props are the first '
  'case: the Odds API quotes them, balldontlie has no MLB statlines on this '
  'plan, and an ungradeable bet is worse than an absent market.';

-- Partial index: the read that matters is "show me the unbettable ones", which
-- is a small minority of a large table.
CREATE INDEX IF NOT EXISTS idx_markets_not_bettable
    ON markets (event_id) WHERE bettable = FALSE;

-- ── The display path has to carry the flag ──────────────────────────────────
-- get_event_player_props is the web's only way into prop rows (migration 045
-- hides `player_prop` from direct table reads, because iOS coerces unknown
-- market types to .moneyline instead of skipping them). It returns an explicit
-- column list, so the flag is invisible to the client until it is added here.
-- subject_sport comes along for the same reason: the UI needs to say WHY a
-- market cannot be bet, and "MLB" is the reason.
CREATE OR REPLACE FUNCTION get_event_player_props(p_event_id UUID)
RETURNS TABLE (
    id UUID, event_id UUID, type TEXT, side_a TEXT, side_b TEXT,
    odds_a NUMERIC, odds_b NUMERIC,
    stat_key TEXT, subject_name TEXT, subject_player_id INTEGER,
    subject_sport TEXT, bettable BOOLEAN
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT m.id, m.event_id, m.type, m.side_a, m.side_b,
           m.odds_a, m.odds_b, m.stat_key, m.subject_name, m.subject_player_id,
           m.subject_sport, m.bettable
      FROM markets m
     WHERE m.event_id = p_event_id
       AND m.type = ANY (legacy_client_hidden_market_types())
     ORDER BY m.subject_name, m.stat_key, m.side_a;
$$;

REVOKE ALL ON FUNCTION get_event_player_props(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_event_player_props(UUID) TO authenticated, service_role;

DO $$
DECLARE v INT;
BEGIN
    SELECT count(*) INTO v FROM markets WHERE bettable = FALSE;
    PERFORM 1 FROM pg_proc WHERE proname = 'get_event_player_props';
    IF NOT FOUND THEN RAISE EXCEPTION '057: get_event_player_props missing'; END IF;
    RAISE NOTICE '057: bettable flag in place; % markets currently not bettable', v;
END $$;
