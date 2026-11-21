-- ============================================================================
-- 066 — Bookmaker key on markets
--
-- A moneyline's two sides have to come from one book. Until this column
-- existed there was nothing on the row that said which book that was, so a
-- home price from DraftKings and an away price from Fanatics could not be
-- told apart from a real two-sided line.
--
-- markets.bookmaker is the Odds API bookmaker key (draftkings, fanatics, …).
-- Nullable. Rows written before this migration stay NULL. This file does not
-- update, delete, or backfill them. sync_games and auto_refresh_games set
-- the key on the rows they write.
--
-- Apply this BEFORE deploying those two functions. Their writes include
-- bookmaker. Deploying them first fails every market write on the unknown
-- column, and the odds sync stops. 065 is the submit-idempotency migration
-- on another branch. 067 is reserved. This file does not touch either.
--
-- Idempotent. A re-run after a partial failure only adds the column if it
-- is missing.
-- ============================================================================

ALTER TABLE markets
    ADD COLUMN IF NOT EXISTS bookmaker TEXT;

COMMENT ON COLUMN markets.bookmaker IS
  'Odds API bookmaker key that priced this row (draftkings, fanatics, and the rest). '
  'Both sides of a moneyline are taken from this one book. NULL on rows written '
  'before migration 066. The ingest sets it; this migration does not backfill.';

DO $$
DECLARE
    v_col INTEGER;
BEGIN
    SELECT count(*) INTO v_col
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'markets'
      AND column_name = 'bookmaker';
    IF v_col <> 1 THEN
        RAISE EXCEPTION 'markets.bookmaker was not added (found %)', v_col;
    END IF;

    RAISE NOTICE '066 ok: markets.bookmaker exists and is nullable; no market row was updated';
END $$;
