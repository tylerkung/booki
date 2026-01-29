-- ============================================================================
-- Migration: 008_cron_auto_refresh.sql
-- Description: Create pg_cron jobs to trigger auto_refresh_games twice daily
-- Required for: PRD - Automatic Server-Side Odds & Score Refresh
-- ============================================================================

-- Enable required extensions for cron scheduling and HTTP requests
-- Note: These may require superuser privileges or enabling in Supabase Dashboard
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

-- ============================================================================
-- Cron Jobs for Auto Refresh
-- ============================================================================
-- Schedule: Twice daily
--   - Morning:   17:00 UTC (09:00 PT / 10:00 MT / 11:00 CT / 12:00 ET)
--   - Afternoon: 21:00 UTC (13:00 PT / 14:00 MT / 15:00 CT / 16:00 ET)
--
-- IMPORTANT: Before running this migration, you must set the service role key
-- as a database secret. Run the following in SQL Editor:
--
--   SELECT vault.create_secret('your-service-role-key', 'service_role_key');
--
-- Or if using older Supabase without vault:
--   INSERT INTO vault.secrets (name, secret) VALUES ('service_role_key', 'your-service-role-key');
--
-- The service role key can be found in Supabase Dashboard > Settings > API > service_role
-- ============================================================================

-- Remove existing jobs if they exist (for idempotent migrations)
SELECT cron.unschedule('auto-refresh-morning') WHERE EXISTS (
    SELECT 1 FROM cron.job WHERE jobname = 'auto-refresh-morning'
);

SELECT cron.unschedule('auto-refresh-afternoon') WHERE EXISTS (
    SELECT 1 FROM cron.job WHERE jobname = 'auto-refresh-afternoon'
);

-- ============================================================================
-- Create wrapper function to call the Edge Function
-- This function handles the HTTP POST call with proper headers
-- ============================================================================
CREATE OR REPLACE FUNCTION call_auto_refresh_games()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    edge_function_url TEXT;
    service_key TEXT;
BEGIN
    -- Construct the Edge Function URL from project reference
    -- Replace 'YOUR_PROJECT_REF' with your actual Supabase project reference
    -- Or set this as a database configuration parameter
    edge_function_url := current_setting('app.edge_function_base_url', true)
        || '/auto_refresh_games';

    -- Get service role key from vault
    SELECT decrypted_secret INTO service_key
    FROM vault.decrypted_secrets
    WHERE name = 'service_role_key';

    IF service_key IS NULL THEN
        RAISE WARNING 'Service role key not found in vault. Auto-refresh skipped.';
        RETURN;
    END IF;

    -- Make HTTP POST request to Edge Function
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

-- Grant execute permission to postgres (cron runs as postgres)
GRANT EXECUTE ON FUNCTION call_auto_refresh_games() TO postgres;

-- ============================================================================
-- Schedule the cron jobs
-- ============================================================================

-- Morning refresh: 17:00 UTC daily (09:00 PT)
SELECT cron.schedule(
    'auto-refresh-morning',
    '0 17 * * *',  -- Cron expression: minute hour day month day-of-week
    $$SELECT call_auto_refresh_games()$$
);

-- Afternoon refresh: 21:00 UTC daily (13:00 PT)
SELECT cron.schedule(
    'auto-refresh-afternoon',
    '0 21 * * *',
    $$SELECT call_auto_refresh_games()$$
);

-- ============================================================================
-- Verify jobs are created (optional - for debugging)
-- ============================================================================
-- SELECT * FROM cron.job WHERE jobname LIKE 'auto-refresh%';

-- ============================================================================
-- SETUP INSTRUCTIONS
-- ============================================================================
-- 1. Enable extensions in Supabase Dashboard:
--    Database > Extensions > Enable "pg_cron" and "pg_net"
--
-- 2. Set the Edge Function base URL:
--    ALTER DATABASE postgres SET app.edge_function_base_url =
--    'https://YOUR_PROJECT_REF.supabase.co/functions/v1';
--
-- 3. Store the service role key in vault:
--    SELECT vault.create_secret('your-service-role-key', 'service_role_key');
--
-- 4. Run this migration in SQL Editor
--
-- 5. Verify jobs are scheduled:
--    SELECT * FROM cron.job WHERE jobname LIKE 'auto-refresh%';
--
-- 6. Monitor job history:
--    SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 10;
-- ============================================================================
