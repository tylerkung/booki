-- ============================================================================
-- Schedule sync_games — in the repo this time
-- Migration: 059_cron_sync_games.sql
--
-- WHY
-- ---
-- MLB had no games for tomorrow. Tracing it: no MLB event had been CREATED
-- since 2026-09-03 20:00, while odds refresh and score finalisation were both
-- healthy (57 and 63 events re-priced in the two hours before this was written,
-- zero games stuck past their start). Only new-event ingest had stopped, and
-- new-event ingest is sync_games alone.
--
-- sync_games is not scheduled anywhere in this repo. CLAUDE.md says it runs
-- twice daily, so a schedule existed at some point — created straight in the
-- dashboard, like the two markets policies found in 046/047 and the NOT NULL
-- constraints found in 055. Nobody can review what is not in the repo, and a
-- cron job that stops is silent: no function logs, because the function is
-- never invoked.
--
-- CADENCE. Not a guess: generateIdempotencyKey() buckets by four hours aligned
-- to 00,04,08,12,16,20 UTC and its comment says the cron MUST match, because a
-- second run inside one bucket finds the key already stored and silently skips
-- the odds sync. So the code has always expected every four hours.
--
-- COST. A full run measured 36 credits (27 calls) on 2026-09-05. Six runs a day
-- is ~216 credits/day, roughly 6,500 a month against a 20,000 allowance. If that
-- is too much, the safe change is 6-hourly at 00,06,12,18 — each of those still
-- lands in a distinct 4-hour bucket, so idempotency keeps working. Do NOT go
-- more frequent than 4-hourly without shrinking the bucket, or the extra runs
-- will skip their odds sync and cost nothing but also do nothing.
--
-- The url is written out in full. Three jobs once built it from
-- current_setting('app.edge_function_base_url', true), which is unset here;
-- current_setting(..., true) returns NULL, NULL || text is NULL, and the job
-- posted to a null url and died on a not-null constraint with nothing to show
-- for it. See migration 050.
-- ============================================================================

CREATE OR REPLACE FUNCTION call_sync_games()
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
        RAISE WARNING 'Service role key not found in vault. Games sync skipped.';
        RETURN;
    END IF;

    PERFORM net.http_post(
        url := 'https://vstfauqufwpdytmvjyfz.supabase.co/functions/v1/sync_games',
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || service_key
        ),
        body := '{}'::jsonb
    );
END;
$$;

COMMENT ON FUNCTION call_sync_games IS
  'Posts to sync_games. Body is empty so the function applies its own '
  'idempotency; force is for manual runs only.';

GRANT EXECUTE ON FUNCTION call_sync_games() TO postgres;

-- Unschedule by pattern, not by name. A job may already exist from the
-- dashboard under a name this migration cannot predict, and two jobs posting to
-- the same function would double the credit spend silently.
DO $$
DECLARE job RECORD;
BEGIN
    FOR job IN
        SELECT jobname FROM cron.job
         WHERE jobname ILIKE '%sync%game%' OR command ILIKE '%call_sync_games%'
    LOOP
        PERFORM cron.unschedule(job.jobname);
        RAISE NOTICE 'Unscheduled existing games-sync job: %', job.jobname;
    END LOOP;
END $$;

SELECT cron.schedule(
    'sync-games-every-4h',
    '0 0,4,8,12,16,20 * * *',   -- must align with generateIdempotencyKey()
    $$SELECT call_sync_games()$$
);

DO $$
DECLARE n INT;
BEGIN
    SELECT count(*) INTO n FROM cron.job
     WHERE jobname ILIKE '%sync%game%' OR command ILIKE '%call_sync_games%';
    IF n <> 1 THEN RAISE EXCEPTION '059: expected exactly 1 games-sync job, found %', n; END IF;

    PERFORM 1 FROM pg_proc
     WHERE proname = 'call_sync_games'
       AND prosrc LIKE '%https://vstfauqufwpdytmvjyfz.supabase.co/functions/v1/sync_games%';
    IF NOT FOUND THEN
        RAISE EXCEPTION '059: wrapper does not contain a literal function url';
    END IF;

    RAISE NOTICE '059: sync_games scheduled every 4h at :00';
END $$;
