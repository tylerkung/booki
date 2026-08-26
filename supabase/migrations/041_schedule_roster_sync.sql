-- ============================================================================
-- 041 — Weekly balldontlie roster refresh
--
-- Rosters churn constantly and a stale cache does NOT fail loudly: it simply
-- stops resolving newly signed players, whose props then quietly never appear.
-- Weekly is enough for that not to matter; the point is that it runs at all.
--
-- Tuesday 09:00 UTC, i.e. after Sunday and Monday games and before the next
-- slate is priced, so a player signed midweek is in the cache before any prop
-- is written against him.
--
-- Follows the wrapper-function pattern established in migration 008 rather than
-- inlining net.http_post with a key: the service key lives in the vault and is
-- read at call time, so it appears in neither this file nor cron.job.
-- ============================================================================

CREATE OR REPLACE FUNCTION call_sync_bdl_rosters()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    edge_function_url TEXT;
    service_key       TEXT;
BEGIN
    edge_function_url := current_setting('app.edge_function_base_url', true)
        || '/sync_bdl_rosters';

    SELECT decrypted_secret INTO service_key
    FROM vault.decrypted_secrets
    WHERE name = 'service_role_key';

    IF service_key IS NULL THEN
        RAISE WARNING 'Service role key not found in vault. Roster sync skipped.';
        RETURN;
    END IF;

    PERFORM net.http_post(
        url     := edge_function_url,
        headers := jsonb_build_object(
            'Content-Type',  'application/json',
            'Authorization', 'Bearer ' || service_key
        ),
        body    := '{}'::jsonb
    );
END;
$$;

GRANT EXECUTE ON FUNCTION call_sync_bdl_rosters() TO postgres;

-- Unschedule by loop rather than by name. Job naming has drifted across
-- migrations in this project before (008 and 014 disagreed), and a leftover
-- duplicate would double the API spend while looking fine from either side.
DO $$
DECLARE
    job RECORD;
BEGIN
    FOR job IN SELECT jobname FROM cron.job WHERE jobname LIKE '%bdl-roster%' LOOP
        PERFORM cron.unschedule(job.jobname);
        RAISE NOTICE 'unscheduled %', job.jobname;
    END LOOP;
END $$;

SELECT cron.schedule(
    'sync-bdl-rosters-weekly',
    '0 9 * * 2',
    $$SELECT call_sync_bdl_rosters()$$
);

DO $$
DECLARE
    n INT;
BEGIN
    SELECT count(*) INTO n FROM cron.job WHERE jobname = 'sync-bdl-rosters-weekly';
    IF n <> 1 THEN
        RAISE EXCEPTION 'expected exactly 1 roster sync job, found %', n;
    END IF;
    RAISE NOTICE 'roster refresh scheduled: Tuesdays 09:00 UTC';
END $$;
