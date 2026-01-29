# Supabase Migrations

Track all SQL changes needed in Supabase when updating the app.

---

## How to Use

1. When making app changes that require database updates, add them here
2. Run the SQL in Supabase Dashboard > SQL Editor
3. Mark as completed with date

---

## Pending Migrations

### The Odds API Integration

**Required for:** PRD - Odds API Integration (when implemented)

```sql
-- Add fields to events table for API tracking and scores
ALTER TABLE events
ADD COLUMN IF NOT EXISTS external_id TEXT,
ADD COLUMN IF NOT EXISTS external_source TEXT,
ADD COLUMN IF NOT EXISTS last_odds_update TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS home_score INTEGER,
ADD COLUMN IF NOT EXISTS away_score INTEGER;

-- Index for faster lookups by external_id
CREATE INDEX IF NOT EXISTS idx_events_external_id ON events(external_id);
```

---

## Completed Migrations

### 2026-01-29: Cron Jobs for Auto Refresh

**Required for:** PRD - Automatic Server-Side Odds & Score Refresh (scheduled triggers)

This migration creates pg_cron jobs that call the `auto_refresh_games` Edge Function twice daily.

**Setup Instructions:**

1. **Enable extensions** in Supabase Dashboard:
   - Go to Database > Extensions
   - Enable `pg_cron` (for scheduled jobs)
   - Enable `pg_net` (for HTTP requests)

2. **Set the Edge Function base URL:**
   ```sql
   ALTER DATABASE postgres SET app.edge_function_base_url =
       'https://YOUR_PROJECT_REF.supabase.co/functions/v1';
   ```
   Replace `YOUR_PROJECT_REF` with your actual project reference (found in Settings > General).

3. **Store the service role key in vault:**
   ```sql
   SELECT vault.create_secret('your-service-role-key', 'service_role_key');
   ```
   The service role key is found in Settings > API > `service_role` (secret).

4. **Run the migration** in SQL Editor.

5. **Verify jobs are scheduled:**
   ```sql
   SELECT jobname, schedule, active FROM cron.job WHERE jobname LIKE 'auto-refresh%';
   ```

6. **Monitor job execution:**
   ```sql
   SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 10;
   ```

**Schedule:**
- Morning: 17:00 UTC (09:00 PT / 12:00 ET) - `'0 17 * * *'`
- Afternoon: 21:00 UTC (13:00 PT / 16:00 ET) - `'0 21 * * *'`

**Troubleshooting:**
- If jobs aren't running, verify extensions are enabled
- Check `cron.job_run_details` for error messages
- Ensure the service role key is correctly stored in vault
- Verify the Edge Function URL is correct

```sql
-- Enable extensions
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Wrapper function to call Edge Function
CREATE OR REPLACE FUNCTION call_auto_refresh_games()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    edge_function_url TEXT;
    service_key TEXT;
BEGIN
    edge_function_url := current_setting('app.edge_function_base_url', true)
        || '/auto_refresh_games';

    SELECT decrypted_secret INTO service_key
    FROM vault.decrypted_secrets
    WHERE name = 'service_role_key';

    IF service_key IS NULL THEN
        RAISE WARNING 'Service role key not found in vault. Auto-refresh skipped.';
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

-- Schedule morning refresh (17:00 UTC)
SELECT cron.schedule(
    'auto-refresh-morning',
    '0 17 * * *',
    $$SELECT call_auto_refresh_games()$$
);

-- Schedule afternoon refresh (21:00 UTC)
SELECT cron.schedule(
    'auto-refresh-afternoon',
    '0 21 * * *',
    $$SELECT call_auto_refresh_games()$$
);
```

### 2026-01-29: Auto Refresh Timestamp Fields

**Required for:** PRD - Automatic Server-Side Odds & Score Refresh (auto_refresh_games Edge Function)

```sql
-- Add auto-refresh timestamp fields to events table
ALTER TABLE events
ADD COLUMN IF NOT EXISTS last_auto_odds_refresh TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS last_auto_score_refresh TIMESTAMPTZ;
```

### 2026-01-29: Audit Events Table

**Required for:** Phase - Server Authority & Legal Acknowledgment (Audit Trail & Dispute Resolution)

```sql
-- Create audit_events table for comprehensive audit logging
CREATE TABLE IF NOT EXISTS audit_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bookie_id UUID REFERENCES bookies(id) ON DELETE CASCADE NOT NULL,
    actor_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    entity_type TEXT NOT NULL,
    entity_id UUID NOT NULL,
    action_type TEXT NOT NULL,
    previous_state JSONB,
    new_state JSONB NOT NULL,
    reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for fast lookups by entity (bookie_id, entity_type, entity_id)
CREATE INDEX IF NOT EXISTS idx_audit_events_entity ON audit_events(bookie_id, entity_type, entity_id);

-- Index for timeline queries (bookie_id, created_at)
CREATE INDEX IF NOT EXISTS idx_audit_events_timeline ON audit_events(bookie_id, created_at);

-- Enable RLS
ALTER TABLE audit_events ENABLE ROW LEVEL SECURITY;

-- RLS Policy: Bookies can only SELECT their own audit events
CREATE POLICY audit_events_select_own ON audit_events
    FOR SELECT
    USING (bookie_id IN (SELECT id FROM bookies WHERE auth_user_id = auth.uid()));

-- No INSERT/UPDATE/DELETE policies - Edge Functions use service role
```

### 2026-01-27: Bets accepted_at Column

**Required for:** Phase - Server Authority & Legal Acknowledgment (accept_bet Edge Function)

```sql
-- Add accepted_at column to bets table for tracking when bets are accepted by bookies
ALTER TABLE bets ADD COLUMN IF NOT EXISTS accepted_at TIMESTAMPTZ;
```

### 2026-01-27: Idempotency Keys Table

**Required for:** Phase - Server Authority & Legal Acknowledgment (Edge Functions)

```sql
-- Create idempotency_keys table for Edge Functions deduplication
CREATE TABLE IF NOT EXISTS idempotency_keys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    key TEXT NOT NULL,
    operation TEXT NOT NULL,
    response TEXT NOT NULL,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '24 hours'),
    UNIQUE(key, operation)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_idempotency_keys_key_operation ON idempotency_keys(key, operation);
CREATE INDEX IF NOT EXISTS idx_idempotency_keys_expires_at ON idempotency_keys(expires_at);

-- NO RLS - Service role access only from Edge Functions
```

### 2026-01-27: User Agreements Table

**Required for:** Phase - Server Authority & Legal Acknowledgment (ToS)

```sql
-- Create user_agreements table for storing legal acknowledgments
CREATE TABLE IF NOT EXISTS user_agreements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('bookie', 'player')),
    version TEXT NOT NULL,
    accepted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ip_address TEXT,
    user_agent TEXT
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_user_agreements_user_id ON user_agreements(user_id);
CREATE INDEX IF NOT EXISTS idx_user_agreements_version ON user_agreements(version);

-- Enable RLS
ALTER TABLE user_agreements ENABLE ROW LEVEL SECURITY;

-- RLS Policies: Users can only SELECT their own, INSERT their own, no UPDATE/DELETE
CREATE POLICY user_agreements_select_own ON user_agreements
    FOR SELECT USING (user_id = auth.uid());

CREATE POLICY user_agreements_insert_own ON user_agreements
    FOR INSERT WITH CHECK (user_id = auth.uid());
```

### 2026-01-25: Player Invite System

**Required for:** Phase 4 - Player Invites feature

```sql
-- Add invite columns to players table
ALTER TABLE players
ADD COLUMN IF NOT EXISTS invite_code TEXT,
ADD COLUMN IF NOT EXISTS invite_code_generated_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS invite_code_expires_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS claimed_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS auth_user_id UUID;
```

### 2026-01-25: Fix Players RLS Policy

**Required for:** Allow bookies to sync players

```sql
-- Drop old restrictive policy
DROP POLICY IF EXISTS "Bookies can manage their own players" ON players;

-- Create policy that validates bookie exists
CREATE POLICY "Bookies can manage their own players"
ON players FOR ALL
USING (
  bookie_id IN (SELECT id FROM bookies)
)
WITH CHECK (
  bookie_id IN (SELECT id FROM bookies)
);
```

### 2026-01-25: Add ticket_id to Bets

**Required for:** Ticket grouping feature

```sql
ALTER TABLE bets
ADD COLUMN IF NOT EXISTS ticket_id UUID;
```

### 2026-01-25: Create Markets Table

**Required for:** Game detail view with multiple markets

```sql
CREATE TABLE IF NOT EXISTS markets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bookie_id UUID NOT NULL REFERENCES bookies(id),
    event_id UUID NOT NULL REFERENCES events(id),
    type TEXT NOT NULL,
    side_a TEXT NOT NULL,
    side_b TEXT NOT NULL,
    odds_a INTEGER NOT NULL,
    odds_b INTEGER NOT NULL,
    version INTEGER DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE markets ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Bookies can manage their own markets" ON markets;

CREATE POLICY "Bookies can manage their own markets"
ON markets FOR ALL
USING (bookie_id IN (SELECT id FROM bookies))
WITH CHECK (bookie_id IN (SELECT id FROM bookies));
```

---

## Future Migrations (Not Yet Needed)

### Settlement Tables

```sql
-- settlement_periods table
CREATE TABLE IF NOT EXISTS settlement_periods (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bookie_id UUID NOT NULL REFERENCES bookies(id),
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    status TEXT DEFAULT 'open',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- player_settlements table
CREATE TABLE IF NOT EXISTS player_settlements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bookie_id UUID NOT NULL REFERENCES bookies(id),
    settlement_period_id UUID REFERENCES settlement_periods(id),
    player_id UUID REFERENCES players(id),
    amount DECIMAL,
    status TEXT DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

---

## Notes

- Always test migrations on a dev/staging environment first
- RLS policies use `bookie_id IN (SELECT id FROM bookies)` pattern for multi-tenant isolation
- The app skips tables that don't exist (see console: "Skipping X - table not yet in database schema")
