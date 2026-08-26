-- ============================================================================
-- 050 — Cron wrappers were posting to a NULL url
--
-- Three scheduled jobs had been failing every run:
--   grade-player-props-every-30min   8 failures
--   sync-player-props-every-6h       1 failure
--   send-followup-email              1 failure
--
--   ERROR: null value in column "url" of relation "http_request_queue"
--          violates not-null constraint
--
-- WHY. Each wrapper built its target as
--
--     current_setting('app.edge_function_base_url', true) || '/name'
--
-- and that setting is NOT SET on this database. current_setting(..., true)
-- returns NULL rather than raising, and NULL || text is NULL, so every one of
-- them posted to a null url. The failure is invisible from the application: the
-- edge function is never invoked, so there are no function logs to find, and
-- nothing surfaces except a row in cron.job_run_details that nobody reads.
--
-- HOW IT WENT UNNOTICED. call_auto_refresh_games, written the same way in
-- migration 008, works — because the live copy does not match the migration.
-- Someone replaced it at some point with the URL written out in full, and that
-- fix never came back into a migration. So the repo's pattern looked proven,
-- and migrations 030 and 049 both copied a version of it that had never run.
-- This is the same trap as the markets RLS policies: the repo is not a complete
-- record of what is in the database.
--
-- The URL is written out here rather than read from a setting, matching the one
-- wrapper that demonstrably works. The project ref is not a secret — it is in
-- CLAUDE.md and in every client bundle.
-- ============================================================================

CREATE OR REPLACE FUNCTION call_sync_player_props()
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
        RAISE WARNING 'Service role key not found in vault. Props sync skipped.';
        RETURN;
    END IF;

    PERFORM net.http_post(
        url := 'https://vstfauqufwpdytmvjyfz.supabase.co/functions/v1/sync_player_props',
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
    service_key TEXT;
BEGIN
    SELECT decrypted_secret INTO service_key
    FROM vault.decrypted_secrets WHERE name = 'service_role_key';

    IF service_key IS NULL THEN
        RAISE WARNING 'Service role key not found in vault. Props grading skipped.';
        RETURN;
    END IF;

    PERFORM net.http_post(
        url := 'https://vstfauqufwpdytmvjyfz.supabase.co/functions/v1/grade_player_props',
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || service_key
        ),
        body := '{}'::jsonb
    );
END;
$$;

CREATE OR REPLACE FUNCTION call_send_followup_email()
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
        RAISE WARNING 'Service role key not found in vault. Follow-up email skipped.';
        RETURN;
    END IF;

    -- NOTE: send_followup_email still has PAUSED = true at the top of its
    -- index.ts, so a successful invocation returns {paused:true, sent:0} and
    -- mails nobody. Fixing the url only means the job stops erroring; it does
    -- not start sending.
    PERFORM net.http_post(
        url := 'https://vstfauqufwpdytmvjyfz.supabase.co/functions/v1/send_followup_email',
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
GRANT EXECUTE ON FUNCTION call_send_followup_email() TO postgres;

-- Assert none of the three can still build a null url.
DO $$
DECLARE
    v_bad INTEGER;
BEGIN
    SELECT count(*) INTO v_bad
    FROM pg_proc
    WHERE proname IN ('call_sync_player_props', 'call_grade_player_props',
                      'call_send_followup_email')
      AND prosrc LIKE '%app.edge_function_base_url%';

    IF v_bad > 0 THEN
        RAISE EXCEPTION '% wrapper(s) still read the unset base-url setting', v_bad;
    END IF;

    RAISE NOTICE 'three cron wrappers now post to an explicit url';
    RAISE NOTICE 'verify after the next tick: SELECT jobname, status FROM cron.job_run_details d JOIN cron.job j USING (jobid) ORDER BY d.start_time DESC LIMIT 5;';
END $$;
