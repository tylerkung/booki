-- ============================================================================
-- 037 — Add the auto-pilot columns the code has always assumed existed
--
-- bookies.manual_bet_acceptance and bookies.manual_bet_grading are read and
-- written across five edge functions, the web dashboard and the iOS client,
-- but no migration ever created them. PostgREST does not tolerate a missing
-- column in a select list: the WHOLE query fails with 42703 and the client
-- receives null, so every one of these reads has been silently taking its
-- fallback branch instead of the value it asked for.
--
-- What that broke, in order of severity:
--
--   submit_parlay          .select('manual_bet_acceptance, tier') fails, so
--                          `bookie` is null, so `bookie?.tier ?? 'free'`
--                          resolves to 'free' and EVERY organizer — Pro
--                          included — is rejected with 'pro_required'.
--                          Multi-Picks have been impossible for everyone.
--
--   submit_bet             .select('manual_bet_acceptance, auth_user_id')
--   submit_bets            fails the same way. manualMode correctly defaults
--                          to false, but auth_user_id comes back undefined,
--                          so the organizer's "new pick" push is never sent.
--
--   auto_refresh_games     .select('auth_user_id, manual_bet_grading') fails
--                          in both the catch-up and grading paths — grading
--                          notifications are likewise never delivered.
--
--   iOS Settings           BookieSettingsUpdate writes both columns, so the
--                          auto-pilot toggles have been erroring on save.
--
--   Web dashboard          bookie.manual_bet_acceptance is always undefined,
--                          so the manual accept/decline column on the Picks
--                          and Settlement tables never renders.
--
-- Defaults are false, which is exactly the fallback every call site was
-- already taking, so adding these columns changes no existing behaviour —
-- it only stops the queries from failing. Auto-pilot stays on by default,
-- as documented.
-- ============================================================================

ALTER TABLE bookies
    ADD COLUMN IF NOT EXISTS manual_bet_acceptance BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS manual_bet_grading    BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN bookies.manual_bet_acceptance IS
    'Opt-in: when true, every pick goes to pending instead of being auto-accepted.';
COMMENT ON COLUMN bookies.manual_bet_grading IS
    'Opt-in: when true, auto_refresh_games will not grade this organizer''s picks.';

-- Verify, rather than assume. A migration that silently no-ops here would
-- leave parlays broken with no signal that anything was wrong.
DO $$
DECLARE
    n INT;
BEGIN
    SELECT count(*) INTO n
      FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name   = 'bookies'
       AND column_name IN ('manual_bet_acceptance', 'manual_bet_grading');

    IF n <> 2 THEN
        RAISE EXCEPTION 'Expected 2 auto-pilot columns on bookies, found %', n;
    END IF;

    RAISE NOTICE 'bookies auto-pilot columns present';
END $$;
