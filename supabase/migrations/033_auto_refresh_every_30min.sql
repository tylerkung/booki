-- ============================================================================
-- Migration: 033_auto_refresh_every_30min.sql
-- Description: Move auto_refresh_games to a 30-minute cadence so the tiered
--              refresh in the function can take effect.
--
-- The function now decides per game how often it is actually re-priced:
--
--   within 4h    every run       (30 min)   lines move fastest here
--   4h to 48h    every 2 hours              visible to members, slower moving
--   outrights    once a day (12:00 UTC)     futures drift over weeks
--
-- The cron therefore fires at the FASTEST tier and the function filters down.
-- Changing this schedule silently changes the near-tier cadence.
--
-- Cost note: Odds API credits are charged per distinct sport key per run, not
-- per game — one call returns every game for its sport. Doubling the cadence
-- does not double spend, because the mid tier stays 2-hourly and outrights
-- (which each carry their own futures key, and were previously refreshed on
-- every hourly run) drop to once daily. Measured 2026-08-18: a full
-- sync_games run costs 30 credits; auto_refresh_games cost 9 for 9 games,
-- most of them outrights.
-- ============================================================================

-- Remove EVERY existing auto-refresh job, whatever it is called.
-- Naming has drifted across migrations 008 ('auto-refresh-morning' /
-- '-afternoon') and 014 ('auto-refresh-every-2h'), and the live schedule may
-- have been changed by hand. Unscheduling by exact name risks leaving an old
-- job in place alongside the new one, which would silently double the spend.
DO $$
DECLARE
    job RECORD;
BEGIN
    FOR job IN SELECT jobname FROM cron.job WHERE jobname LIKE 'auto-refresh%' LOOP
        PERFORM cron.unschedule(job.jobname);
        RAISE NOTICE 'Unscheduled %', job.jobname;
    END LOOP;
END $$;

SELECT cron.schedule(
    'auto-refresh-every-30min',
    '0,30 * * * *',
    $$SELECT call_auto_refresh_games()$$
);

-- ============================================================================
-- VERIFICATION
-- ============================================================================
--   SELECT jobname, schedule FROM cron.job WHERE jobname LIKE 'auto-refresh%';
--     -> exactly one row: auto-refresh-every-30min, '0,30 * * * *'
--
--   Watch spend after a day; every response now carries a quota block:
--   SELECT ... or just invoke the function and read quota.remaining
-- ============================================================================
