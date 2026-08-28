-- ============================================================================
-- MLB props on their own schedule
-- Migration: 058_cron_mlb_props.sql
--
-- The existing sync-player-props job posts an empty body, which the function
-- reads as NFL. MLB needs its own wrapper because the sport is a request
-- parameter, and its own cadence because the two sports behave nothing alike:
-- the NFL plays sixteen games a week, MLB plays fifteen a day.
--
-- CADENCE. MLB props are not bettable (see migration 057 — balldontlie has no
-- MLB statlines on this plan), so there is nothing to gain from re-pricing
-- them: the function ingests each game ONCE for an unsettleable sport and
-- skips it thereafter. That makes cost proportional to NEW games rather than to
-- how often the job runs, so most runs cost zero Odds API credits and the ones
-- that do cost 6 per game.
--
-- Every three hours covers a daily slate comfortably: eight runs at three games
-- each is 24 games of capacity against roughly fifteen real ones, with slack
-- for a run that stops on its time budget.
--
-- THE URL IS WRITTEN OUT IN FULL, deliberately. Three jobs previously built it
-- from current_setting('app.edge_function_base_url', true), a setting that is
-- not set on this database. current_setting(..., true) returns NULL rather than
-- raising, NULL || text is NULL, and the job then posted to a null url and died
-- on a not-null constraint — invisibly, because the function is never invoked
-- and so leaves no logs. Migration 050 fixed those three; this one must not
-- reintroduce the pattern.
-- ============================================================================

CREATE OR REPLACE FUNCTION call_sync_player_props_mlb()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    service_key TEXT;
BEGIN
    SELECT decrypted_secret INTO service_key
    FROM vault.decrypted_secrets WHERE name = 'service_role_key';

    IF service_key IS NULL THEN
        RAISE WARNING 'Service role key not found in vault. MLB props sync skipped.';
        RETURN;
    END IF;

    PERFORM net.http_post(
        url := 'https://vstfauqufwpdytmvjyfz.supabase.co/functions/v1/sync_player_props',
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || service_key
        ),
        body := '{"sport":"MLB","max_games":3}'::jsonb
    );
END;
$$;

COMMENT ON FUNCTION call_sync_player_props_mlb IS
  'Posts sport=MLB to sync_player_props. Separate from call_sync_player_props, '
  'which posts an empty body and therefore runs NFL.';

GRANT EXECUTE ON FUNCTION call_sync_player_props_mlb() TO postgres;

-- Unschedule by pattern rather than by name: the naming of these jobs has
-- already drifted once across migrations, and a leftover duplicate would double
-- the spend silently.
DO $$
DECLARE job RECORD;
BEGIN
    FOR job IN SELECT jobname FROM cron.job WHERE jobname LIKE '%mlb-props%'
    LOOP
        PERFORM cron.unschedule(job.jobname);
        RAISE NOTICE 'Unscheduled %', job.jobname;
    END LOOP;
END $$;

SELECT cron.schedule(
    'sync-mlb-props-every-3h',
    '25 1,4,7,10,13,16,19,22 * * *',  -- :25 clears the :00/:30 odds refresh,
                                      -- the :15 NFL props job and :05/:35 grading
    $$SELECT call_sync_player_props_mlb()$$
);

DO $$
DECLARE n INT;
BEGIN
    SELECT count(*) INTO n FROM cron.job WHERE jobname = 'sync-mlb-props-every-3h';
    IF n <> 1 THEN RAISE EXCEPTION '058: expected 1 MLB props job, found %', n; END IF;

    -- The failure mode this guards is a wrapper that builds its url from an
    -- unset setting and posts NULL. Assert the literal is present instead.
    PERFORM 1 FROM pg_proc
     WHERE proname = 'call_sync_player_props_mlb'
       AND prosrc LIKE '%https://vstfauqufwpdytmvjyfz.supabase.co/functions/v1/sync_player_props%';
    IF NOT FOUND THEN
        RAISE EXCEPTION '058: MLB wrapper does not contain a literal function url';
    END IF;

    RAISE NOTICE '058: MLB props scheduled every 3h at :25';
END $$;
