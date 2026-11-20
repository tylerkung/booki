-- Pre-065 schema plus the prop-snapshot columns from 062, so claim_bet_submission
-- can insert. Peer-local only. The Colorado duplicate is inserted here, before
-- migration 065, and must survive it unchanged.
--
-- Known QA shape (prefixes only; production timestamps are reproduced):
--   key 0845800d stored against ticket defc7465 / bet 55c3ae26
--   ticket 51bd1346 / bet 569a7dbd 1.397s later, same market, -110, $1

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
    name TEXT NOT NULL
);

CREATE TABLE players (
    id UUID PRIMARY KEY,
    bookie_id UUID NOT NULL REFERENCES bookies(id),
    auth_user_id UUID REFERENCES auth.users(id),
    name TEXT NOT NULL
);

CREATE TABLE bets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bookie_id UUID NOT NULL REFERENCES bookies(id),
    player_id UUID NOT NULL REFERENCES players(id),
    event_id TEXT NOT NULL,
    ticket_id UUID NOT NULL,
    market TEXT,
    market_id UUID,
    side TEXT NOT NULL,
    odds INT NOT NULL,
    stake DECIMAL(15, 2) NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    grade_result TEXT,
    is_parlay BOOLEAN NOT NULL DEFAULT FALSE,
    parlay_legs INT NOT NULL DEFAULT 1,
    policy_violation_reason TEXT,
    accepted_at TIMESTAMPTZ,
    stat_key TEXT,
    subject_player_id INTEGER,
    prop_line NUMERIC,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE idempotency_keys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    key TEXT NOT NULL,
    operation TEXT NOT NULL,
    response TEXT NOT NULL,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '24 hours'),
    UNIQUE (key, operation)
);

INSERT INTO auth.users (id) VALUES
    ('11111111-1111-4111-8111-111111111111'),
    ('11111111-1111-4111-8111-111111111112'),
    ('11111111-1111-4111-8111-1111111111bb');

INSERT INTO bookies (id, auth_user_id, name) VALUES
    ('22222222-2222-4222-8222-222222222222', '11111111-1111-4111-8111-1111111111bb', 'QA Book');

INSERT INTO players (id, bookie_id, auth_user_id, name) VALUES
    ('33333333-3333-4333-8333-333333333333', '22222222-2222-4222-8222-222222222222', '11111111-1111-4111-8111-111111111111', 'Colorado member'),
    ('44444444-4444-4444-8444-444444444444', '22222222-2222-4222-8222-222222222222', '11111111-1111-4111-8111-111111111112', 'Other member');

INSERT INTO bets (
    id, bookie_id, player_id, event_id, ticket_id, market, market_id, side,
    odds, stake, status, is_parlay, parlay_legs, created_at
) VALUES
    (
        '55c3ae26-0000-4000-8000-000000055c3a',
        '22222222-2222-4222-8222-222222222222',
        '33333333-3333-4333-8333-333333333333',
        'event-colorado',
        'defc7465-0000-4000-8000-000000defc74',
        'spread',
        '1050ea8a-0000-4000-8000-0000001050ea',
        'Colorado +3',
        -110, 1, 'accepted', false, 1,
        '2026-11-20 12:08:09.632-08'
    ),
    (
        '569a7dbd-0000-4000-8000-000000569a7d',
        '22222222-2222-4222-8222-222222222222',
        '33333333-3333-4333-8333-333333333333',
        'event-colorado',
        '51bd1346-0000-4000-8000-00000051bd13',
        'spread',
        '1050ea8a-0000-4000-8000-0000001050ea',
        'Colorado +3',
        -110, 1, 'accepted', false, 1,
        '2026-11-20 12:08:11.029-08'
    );

INSERT INTO idempotency_keys (key, operation, response, user_id, created_at) VALUES (
    '0845800d-0000-4000-8000-000000084580',
    'submit_bets',
    '{"success":true,"bets":[{"id":"55c3ae26-0000-4000-8000-000000055c3a","ticket_id":"defc7465-0000-4000-8000-000000defc74","player_id":"33333333-3333-4333-8333-333333333333","market_id":"1050ea8a-0000-4000-8000-0000001050ea","odds":-110,"stake":1,"side":"Colorado +3"}]}',
    '11111111-1111-4111-8111-111111111111',
    '2026-11-20 12:08:09.700-08'
);
