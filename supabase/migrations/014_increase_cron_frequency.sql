-- Migration: 014_increase_cron_frequency.sql
-- Description: Increase auto_refresh_games frequency from twice daily to every 2 hours
-- With 20k API calls/month, we have ~670 calls/day budget (was using ~86/day)

-- Remove old schedules
SELECT cron.unschedule('auto-refresh-morning') WHERE EXISTS (
    SELECT 1 FROM cron.job WHERE jobname = 'auto-refresh-morning'
);
SELECT cron.unschedule('auto-refresh-afternoon') WHERE EXISTS (
    SELECT 1 FROM cron.job WHERE jobname = 'auto-refresh-afternoon'
);

-- New schedule: every 2 hours from 8 AM to midnight PT (15:00-07:00 UTC)
-- That's 15,17,19,21,23,01,03,05,07 UTC = 9 runs/day
SELECT cron.schedule(
    'auto-refresh-every-2h',
    '0 15,17,19,21,23,1,3,5,7 * * *',
    $$SELECT call_auto_refresh_games()$$
);
