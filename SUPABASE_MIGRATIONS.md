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
