-- ============================================================================
-- Migration: 030_lifecycle_emails.sql
-- Description: Tracking table + dormancy query + daily cron for lifecycle
--              emails. First use: the "you haven't invited anyone" follow-up.
-- ============================================================================

-- ============================================================================
-- LIFECYCLE EMAILS TABLE
-- One row per (user, email_type) send. Presence of a row is what prevents a
-- second send, so rows are only written after the provider accepts the email.
-- ============================================================================
CREATE TABLE IF NOT EXISTS lifecycle_emails (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    auth_user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    email_type TEXT NOT NULL,
    provider_message_id TEXT,
    sent_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (auth_user_id, email_type)
);

CREATE INDEX IF NOT EXISTS idx_lifecycle_emails_lookup
    ON lifecycle_emails(auth_user_id, email_type);

-- Service role only — no user ever reads or writes this directly
ALTER TABLE lifecycle_emails ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- DORMANT ORGANIZER QUERY
-- An organizer is dormant when their account is at least p_min_age_days old
-- and they have created no invites and have no members. Excludes anyone who
-- already received this email type.
-- ============================================================================
CREATE OR REPLACE FUNCTION get_dormant_organizers(
    p_min_age_days INT DEFAULT 10,
    p_email_type TEXT DEFAULT 'invite_followup',
    p_limit INT DEFAULT 50
)
RETURNS TABLE (
    bookie_id UUID,
    auth_user_id UUID,
    name TEXT,
    email TEXT,
    created_at TIMESTAMPTZ
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT b.id, b.auth_user_id, b.name, b.email, b.created_at
    FROM bookies b
    WHERE b.created_at < NOW() - (p_min_age_days || ' days')::INTERVAL
      AND NOT EXISTS (SELECT 1 FROM invites i WHERE i.bookie_id = b.id)
      AND NOT EXISTS (SELECT 1 FROM players p WHERE p.bookie_id = b.id)
      AND NOT EXISTS (
          SELECT 1 FROM lifecycle_emails le
          WHERE le.auth_user_id = b.auth_user_id
            AND le.email_type = p_email_type
      )
    ORDER BY b.created_at ASC
    LIMIT p_limit;
$$;

REVOKE EXECUTE ON FUNCTION get_dormant_organizers(INT, TEXT, INT) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION get_dormant_organizers(INT, TEXT, INT) TO service_role;

-- ============================================================================
-- CRON WRAPPER
-- Mirrors call_auto_refresh_games() from migration 008 — same vault secret and
-- same app.edge_function_base_url setting.
-- ============================================================================
CREATE OR REPLACE FUNCTION call_send_followup_email()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    edge_function_url TEXT;
    service_key TEXT;
BEGIN
    edge_function_url := current_setting('app.edge_function_base_url', true)
        || '/send_followup_email';

    SELECT decrypted_secret INTO service_key
    FROM vault.decrypted_secrets
    WHERE name = 'service_role_key';

    IF service_key IS NULL THEN
        RAISE WARNING 'Service role key not found in vault. Follow-up email skipped.';
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

GRANT EXECUTE ON FUNCTION call_send_followup_email() TO postgres;

-- ============================================================================
-- SCHEDULE
-- Once daily at 17:00 UTC (09:00 PT) — a reasonable hour to land in an inbox.
-- The 50-per-run cap in the edge function means an existing backlog of dormant
-- organizers drains over several days rather than sending all at once.
-- ============================================================================
SELECT cron.unschedule('send-followup-email') WHERE EXISTS (
    SELECT 1 FROM cron.job WHERE jobname = 'send-followup-email'
);

SELECT cron.schedule(
    'send-followup-email',
    '0 17 * * *',
    $$SELECT call_send_followup_email()$$
);

-- ============================================================================
-- VERIFICATION
-- ============================================================================
-- Preview who would receive it (no send):
--   SELECT * FROM get_dormant_organizers(10, 'invite_followup', 50);
--
-- Check the job is scheduled:
--   SELECT * FROM cron.job WHERE jobname = 'send-followup-email';
--
-- Review sends:
--   SELECT * FROM lifecycle_emails ORDER BY sent_at DESC LIMIT 20;
-- ============================================================================
