-- ============================================================================
-- 049 — Schedule the player-props pipeline
--
-- Both functions existed but ran only by hand, so props never refreshed and
-- nothing ever settled one. This puts them on cron.
--
-- COST, measured rather than assumed (2026-08-25, NFL week 1 sixteen days out):
--   sync_player_props dry run over 16 games -> 26 credits, 16 calls,
--   35 markets, 18 subjects resolved, 0 unresolved.
--
-- 26 is a floor, not a typical run: books had barely posted prop menus that far
-- out. The CEILING is what makes this schedulable — the Odds API charges
-- markets x regions per call, so 6 prop markets x 1 region caps a call at 6
-- credits no matter how many props appear. A full 16-game slate can therefore
-- never exceed 96 credits, however busy the board gets.
--
-- Every 6 hours against a 2-day window, using the real NFL calendar rather than
-- assuming every game sits in the window every day:
--   Thu game   in window Tue-Thu  = 3 days x 4 runs x 1 game  x 6 =    72
--   Sun slate  in window Fri-Sun  = 3 days x 4 runs x 13 games x 6 =   936
--   Mon game   in window Sat-Mon  = 3 days x 4 runs x 1 game  x 6 =    72
--                                                      per week   ~ 1,080
--                                                     per month   ~ 4,600  (23%)
--
-- On top of the odds pipeline's ~17% (about 50% at peak season overlap), that
-- leaves headroom but not a lot of it. Every response carries a quota block —
-- re-measure during a real game week before deciding to tighten or loosen, and
-- treat the 23% above as an estimate built on a 16-days-out sample.
--
-- grade_player_props costs no Odds API credits at all; it reads balldontlie.
-- Every 30 minutes so a finished game settles promptly — the function already
-- waits 30 minutes past the final whistle and refuses to grade on an incomplete
-- box score, so running it often is cheap and cannot half-settle a ticket.
--
-- Idempotent: wrappers are CREATE OR REPLACE, and each job is unscheduled by
-- loop before being rescheduled. Per CLAUDE.md the Supabase SQL editor does not
-- wrap this in a transaction, so it must be safe to re-run.
-- ============================================================================

CREATE OR REPLACE FUNCTION call_sync_player_props()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    edge_function_url TEXT;
    service_key TEXT;
BEGIN
    edge_function_url := current_setting('app.edge_function_base_url', true)
        || '/sync_player_props';

    SELECT decrypted_secret INTO service_key
    FROM vault.decrypted_secrets
    WHERE name = 'service_role_key';

    IF service_key IS NULL THEN
        RAISE WARNING 'Service role key not found in vault. Props sync skipped.';
        RETURN;
    END IF;

    PERFORM net.http_post(
        url := edge_function_url,
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || service_key
        ),
        body := '{}'::jsonb
    );
END;
$$;

CREATE OR REPLACE FUNCTION call_grade_player_props()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    edge_function_url TEXT;
    service_key TEXT;
BEGIN
    edge_function_url := current_setting('app.edge_function_base_url', true)
        || '/grade_player_props';

    SELECT decrypted_secret INTO service_key
    FROM vault.decrypted_secrets
    WHERE name = 'service_role_key';

    IF service_key IS NULL THEN
        RAISE WARNING 'Service role key not found in vault. Props grading skipped.';
        RETURN;
    END IF;

    PERFORM net.http_post(
        url := edge_function_url,
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || service_key
        ),
        body := '{}'::jsonb
    );
END;
$$;

GRANT EXECUTE ON FUNCTION call_sync_player_props() TO postgres;
GRANT EXECUTE ON FUNCTION call_grade_player_props() TO postgres;

-- Unschedule by loop rather than by name. Migration 033 learned this the hard
-- way: job names drifted across 008 and 014, and a leftover job under an old
-- name keeps firing and doubles the spend.
DO $$
DECLARE
    job RECORD;
BEGIN
    FOR job IN
        SELECT jobname FROM cron.job
        WHERE jobname LIKE '%player-props%' OR jobname LIKE '%player_props%'
    LOOP
        PERFORM cron.unschedule(job.jobname);
        RAISE NOTICE 'Unscheduled %', job.jobname;
    END LOOP;
END $$;

SELECT cron.schedule(
    'sync-player-props-every-6h',
    '15 0,6,12,18 * * *',   -- :15 to stay clear of the :00/:30 odds refresh
    $$SELECT call_sync_player_props()$$
);

SELECT cron.schedule(
    'grade-player-props-every-30min',
    '5,35 * * * *',         -- offset from the :00/:30 auto-refresh
    $$SELECT call_grade_player_props()$$
);

DO $$
DECLARE
    v_jobs INTEGER;
BEGIN
    SELECT count(*) INTO v_jobs
    FROM cron.job
    WHERE jobname IN ('sync-player-props-every-6h', 'grade-player-props-every-30min')
      AND active;

    IF v_jobs <> 2 THEN
        RAISE EXCEPTION 'expected 2 active props jobs, found %', v_jobs;
    END IF;

    RAISE NOTICE 'props pipeline scheduled: sync every 6h, grading every 30 min';
END $$;
