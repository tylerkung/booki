-- ============================================================================
-- 062 — Snapshot the prop identity onto the bet at submit
--
-- sync_games deletes every non-outright market on a finished event, and
-- bets.market_id is ON DELETE SET NULL. Once that happens the stat_key and
-- the player id live only on a row that no longer exists, so grade_player_props
-- cannot tell a receptions prop from a rushing-yards prop.
--
-- These columns are written by submit_bet, submit_bets and submit_parlay for
-- bets placed after this migration. They are nullable, they have no default
-- that would rewrite old rows, and this file does not UPDATE, backfill, or
-- regrade anything already stored.
--
-- `bets.side` is the existing side label. `prop_line` is the numeric line
-- parsed from that label so grading does not have to guess it later.
-- subject_player_id is intentionally NOT a foreign key: the snapshot has to
-- survive a roster-cache rebuild, and a missing bdl_players row must not
-- reject the bet.
-- ============================================================================

ALTER TABLE bets ADD COLUMN IF NOT EXISTS stat_key TEXT;
ALTER TABLE bets ADD COLUMN IF NOT EXISTS subject_player_id INTEGER;
ALTER TABLE bets ADD COLUMN IF NOT EXISTS prop_line NUMERIC;

COMMENT ON COLUMN bets.stat_key IS 'Prop stat key copied from the market at submit. Null for non-props and for bets placed before migration 062.';
COMMENT ON COLUMN bets.subject_player_id IS 'balldontlie player id copied from the market at submit. Null for non-props and for bets placed before migration 062.';
COMMENT ON COLUMN bets.prop_line IS 'Numeric prop line copied at submit (2.5, 79.5, 0.5). Null for non-props and for bets placed before migration 062.';
