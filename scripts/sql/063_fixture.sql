-- Minimal pre-063 ledger. Peer-local only. Historical duplicate settlements
-- are inserted here, before migration 063, and must survive it unchanged.
--
-- Known QA shapes (prefixes only; production seq numbers are not reproduced):
--   e4df12ed  76ers ML -124, $5, two active settlements of -4.03
--   297c5d53  Wolves ML -178, $5, two active settlements of -2.81

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE SCHEMA IF NOT EXISTS auth;
CREATE TABLE IF NOT EXISTS auth.users (
    id UUID PRIMARY KEY
);

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
        CREATE ROLE service_role NOLOGIN BYPASSRLS;
    END IF;
END $$;

CREATE TABLE bookies (
    id UUID PRIMARY KEY,
    auth_user_id UUID NOT NULL REFERENCES auth.users(id),
    name TEXT NOT NULL,
    email TEXT,
    subscription_status TEXT NOT NULL DEFAULT 'trial',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE players (
    id UUID PRIMARY KEY,
    bookie_id UUID NOT NULL REFERENCES bookies(id),
    auth_user_id UUID,
    name TEXT NOT NULL,
    email TEXT,
    credit_limit DECIMAL(15, 2) NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE bets (
    id UUID PRIMARY KEY,
    bookie_id UUID NOT NULL REFERENCES bookies(id),
    player_id UUID NOT NULL REFERENCES players(id),
    event_id TEXT NOT NULL,
    ticket_id UUID NOT NULL,
    market TEXT,
    side TEXT NOT NULL,
    odds INT NOT NULL,
    stake DECIMAL(15, 2) NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    grade_result TEXT,
    is_parlay BOOLEAN NOT NULL DEFAULT FALSE,
    parlay_legs INT NOT NULL DEFAULT 1,
    accepted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE ledger_entries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bookie_id UUID NOT NULL REFERENCES bookies(id),
    player_id UUID NOT NULL REFERENCES players(id),
    bet_id UUID REFERENCES bets(id),
    amount DECIMAL(15, 2) NOT NULL,
    type TEXT NOT NULL,
    description TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    prev_hash TEXT,
    entry_hash TEXT,
    seq BIGSERIAL
);

CREATE TABLE settlement_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bookie_id UUID NOT NULL REFERENCES bookies(id),
    bet_id UUID NOT NULL REFERENCES bets(id),
    settlement_version INT NOT NULL DEFAULT 1,
    mode TEXT NOT NULL CHECK (mode IN ('manual', 'auto')),
    actor_user_id UUID REFERENCES auth.users(id),
    idempotency_key TEXT,
    ledger_entry_ids UUID[] NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_settlement_events_bet_version UNIQUE (bet_id, settlement_version)
);

CREATE TABLE audit_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bookie_id UUID NOT NULL REFERENCES bookies(id),
    actor_user_id UUID REFERENCES auth.users(id),
    entity_type TEXT NOT NULL,
    entity_id UUID NOT NULL,
    action_type TEXT NOT NULL,
    previous_state JSONB,
    new_state JSONB NOT NULL,
    reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE OR REPLACE FUNCTION prevent_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'Mutation of % is not allowed. This table is immutable.', TG_TABLE_NAME;
    RETURN NULL;
END;
$$;

CREATE TRIGGER prevent_mutation_ledger_entries
    BEFORE UPDATE OR DELETE ON ledger_entries
    FOR EACH ROW EXECUTE FUNCTION prevent_mutation();

CREATE TRIGGER prevent_mutation_settlement_events
    BEFORE UPDATE OR DELETE ON settlement_events
    FOR EACH ROW EXECUTE FUNCTION prevent_mutation();

CREATE TRIGGER prevent_mutation_audit_events
    BEFORE UPDATE OR DELETE ON audit_events
    FOR EACH ROW EXECUTE FUNCTION prevent_mutation();

-- Same chain as migration 044, so a settlement insert can fill entry_hash.
CREATE OR REPLACE FUNCTION compute_ledger_hash()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_prev_hash TEXT;
BEGIN
    SELECT entry_hash INTO v_prev_hash
      FROM ledger_entries
     WHERE bookie_id = NEW.bookie_id
       AND player_id = NEW.player_id
     ORDER BY seq DESC
     LIMIT 1
       FOR UPDATE;
    NEW.prev_hash := v_prev_hash;
    NEW.entry_hash := encode(
        sha256(
            convert_to(
                concat(
                    coalesce(v_prev_hash, ''),
                    NEW.bookie_id::text,
                    NEW.player_id::text,
                    NEW.amount::text,
                    NEW.type,
                    NEW.created_at::text,
                    NEW.id::text
                ),
                'UTF8'
            )
        ),
        'hex'
    );
    RETURN NEW;
END;
$$;

CREATE TRIGGER compute_ledger_hash_trigger
    BEFORE INSERT ON ledger_entries
    FOR EACH ROW EXECUTE FUNCTION compute_ledger_hash();

ALTER TABLE ledger_entries ALTER COLUMN entry_hash SET NOT NULL;

INSERT INTO auth.users (id) VALUES ('11111111-1111-4111-8111-111111111111');

INSERT INTO bookies (id, auth_user_id, name, email)
VALUES (
    '22222222-2222-4222-8222-222222222222',
    '11111111-1111-4111-8111-111111111111',
    'Test Organizer',
    'organizer@example.com'
);

INSERT INTO players (id, bookie_id, name)
VALUES (
    '33333333-3333-4333-8333-333333333333',
    '22222222-2222-4222-8222-222222222222',
    'Member'
);

INSERT INTO bets (
    id, bookie_id, player_id, event_id, ticket_id, market, side, odds, stake,
    status, grade_result, is_parlay, parlay_legs
) VALUES
    ('e4df12ed-0000-4000-8000-000000000076',
     '22222222-2222-4222-8222-222222222222',
     '33333333-3333-4333-8333-333333333333',
     'evt-76ers', 'a1000000-0000-4000-8000-000000000076',
     'moneyline', '76ers ML', -124, 5, 'settled', 'win', false, 1),
    ('297c5d53-0000-4000-8000-000000000297',
     '22222222-2222-4222-8222-222222222222',
     '33333333-3333-4333-8333-333333333333',
     'evt-wolves', 'a1000000-0000-4000-8000-000000000297',
     'moneyline', 'Wolves ML', -178, 5, 'settled', 'win', false, 1),
    ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
     '22222222-2222-4222-8222-222222222222',
     '33333333-3333-4333-8333-333333333333',
     'evt-seq', 'a1000000-0000-4000-8000-0000000000a1',
     'moneyline', 'Seq ML', -124, 5, 'graded', 'win', false, 1),
    ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2',
     '22222222-2222-4222-8222-222222222222',
     '33333333-3333-4333-8333-333333333333',
     'evt-con', 'a1000000-0000-4000-8000-0000000000a2',
     'moneyline', 'Concurrent ML', -110, 10, 'graded', 'win', false, 1),
    ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3',
     '22222222-2222-4222-8222-222222222222',
     '33333333-3333-4333-8333-333333333333',
     'evt-dir', 'a1000000-0000-4000-8000-0000000000a3',
     'moneyline', 'Direct ML', 100, 5, 'graded', 'win', false, 1),
    ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
     '22222222-2222-4222-8222-222222222222',
     '33333333-3333-4333-8333-333333333333',
     'evt-p1', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
     'moneyline', 'Leg A', -110, 10, 'graded', 'win', true, 2),
    ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2',
     '22222222-2222-4222-8222-222222222222',
     '33333333-3333-4333-8333-333333333333',
     'evt-p2', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
     'moneyline', 'Leg B', -110, 10, 'graded', 'win', true, 2),
    ('dddddddd-dddd-4ddd-8ddd-ddddddddddd1',
     '22222222-2222-4222-8222-222222222222',
     '33333333-3333-4333-8333-333333333333',
     'evt-e1', 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
     'moneyline', 'Early loss', -360, 100, 'graded', 'loss', true, 3),
    ('dddddddd-dddd-4ddd-8ddd-ddddddddddd2',
     '22222222-2222-4222-8222-222222222222',
     '33333333-3333-4333-8333-333333333333',
     'evt-e2', 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
     'moneyline', 'Still open', -344, 100, 'accepted', NULL, true, 3),
    ('dddddddd-dddd-4ddd-8ddd-ddddddddddd3',
     '22222222-2222-4222-8222-222222222222',
     '33333333-3333-4333-8333-333333333333',
     'evt-e3', 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
     'moneyline', 'Void leg', -217, 100, 'void', 'void', true, 3),
    ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4',
     '22222222-2222-4222-8222-222222222222',
     '33333333-3333-4333-8333-333333333333',
     'evt-andrews', 'a1000000-0000-4000-8000-0000000000a4',
     'player_receptions', 'Mark Andrews Over 2.5', -151, 50, 'graded', 'win', false, 1),
    ('ffffffff-ffff-4fff-8fff-ffffffffff01',
     '22222222-2222-4222-8222-222222222222',
     '33333333-3333-4333-8333-333333333333',
     'evt-c1', 'ffffffff-ffff-4fff-8fff-ffffffffffff',
     'moneyline', 'Race A', -110, 10, 'graded', 'win', true, 2),
    ('ffffffff-ffff-4fff-8fff-ffffffffff02',
     '22222222-2222-4222-8222-222222222222',
     '33333333-3333-4333-8333-333333333333',
     'evt-c2', 'ffffffff-ffff-4fff-8fff-ffffffffffff',
     'moneyline', 'Race B', -110, 10, 'graded', 'win', true, 2);

-- Two active settlements each. No settlement_events row for the second,
-- which is how the live path paid twice: the ledger insert succeeded and
-- the version-1 settlement_events insert did not.
INSERT INTO ledger_entries (
    id, bookie_id, player_id, bet_id, amount, type, description, created_at
) VALUES
    ('11111111-0000-4000-8000-000000000051',
     '22222222-2222-4222-8222-222222222222',
     '33333333-3333-4333-8333-333333333333',
     'e4df12ed-0000-4000-8000-000000000076',
     -4.03, 'settlement', 'Bet won', '2026-02-26 18:00:00+00'),
    ('11111111-0000-4000-8000-000000000059',
     '22222222-2222-4222-8222-222222222222',
     '33333333-3333-4333-8333-333333333333',
     'e4df12ed-0000-4000-8000-000000000076',
     -4.03, 'settlement', 'Bet won', '2026-02-26 18:30:00+00'),
    ('11111111-0000-4000-8000-000000000067',
     '22222222-2222-4222-8222-222222222222',
     '33333333-3333-4333-8333-333333333333',
     '297c5d53-0000-4000-8000-000000000297',
     -2.81, 'settlement', 'Bet won', '2026-02-26 19:00:00+00'),
    ('11111111-0000-4000-8000-000000000174',
     '22222222-2222-4222-8222-222222222222',
     '33333333-3333-4333-8333-333333333333',
     '297c5d53-0000-4000-8000-000000000297',
     -2.81, 'settlement', 'Bet won', '2026-02-26 19:30:00+00');
