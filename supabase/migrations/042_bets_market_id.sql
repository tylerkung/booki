-- ============================================================================
-- 042 — Record WHICH market a bet was placed on
--
-- bets stores `market` (the market TYPE, e.g. 'spread') and `side` (the label),
-- but never a reference to the market row itself. For every market type that
-- existed until now that was sufficient: an event has one spread, one total and
-- one moneyline, so (event_id, market, side) identifies the line uniquely.
--
-- Player props break that assumption. An event carries many markets of type
-- 'player_prop', and their side labels are not unique across stats:
-- "Jalen Hurts Over 1.5" is a legitimate label for BOTH passing touchdowns and
-- rushing touchdowns. Settlement has to know which stat the bet was on, and
-- guessing from a display string is exactly the fragility this design has
-- avoided everywhere else.
--
-- The submit functions already load the market by id to validate the price;
-- they simply discard the id afterwards. This keeps it.
--
-- Nullable, and deliberately so: every existing bet predates this column and
-- backfilling one by matching display strings would be inventing data. Old
-- bets keep grading the way they always have, from (market, side).
-- ============================================================================

ALTER TABLE bets
    ADD COLUMN IF NOT EXISTS market_id UUID REFERENCES markets(id) ON DELETE SET NULL;

COMMENT ON COLUMN bets.market_id IS
    'The market row this bet was placed on. Required in practice for player props, whose side labels are not unique within an event. NULL on bets placed before migration 042.';

-- Settlement looks bets up by market, so index that direction.
CREATE INDEX IF NOT EXISTS idx_bets_market_id
    ON bets (market_id) WHERE market_id IS NOT NULL;

DO $$
DECLARE
    n INT;
BEGIN
    SELECT count(*) INTO n
      FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'bets' AND column_name = 'market_id';
    IF n <> 1 THEN
        RAISE EXCEPTION 'bets.market_id was not created';
    END IF;
    RAISE NOTICE 'bets.market_id added (nullable; existing bets unaffected)';
END $$;
