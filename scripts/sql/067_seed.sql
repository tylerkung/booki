-- Events and open futures picks for the local 067 test.
-- Applied after the 063 fixture and migration 063, and before migration 067.
-- Does not insert a ledger row.

CREATE TABLE IF NOT EXISTS events (
    id UUID PRIMARY KEY,
    bookie_id UUID,
    name TEXT NOT NULL,
    sport TEXT NOT NULL DEFAULT 'Basketball',
    league TEXT,
    start_time TIMESTAMPTZ NOT NULL,
    status TEXT NOT NULL DEFAULT 'scheduled',
    home_team TEXT NOT NULL,
    away_team TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO auth.users (id) VALUES ('11111111-1111-4111-8111-111111111112');

INSERT INTO bookies (id, auth_user_id, name, email)
VALUES (
    '22222222-2222-4222-8222-222222222223',
    '11111111-1111-4111-8111-111111111112',
    'Second Organizer',
    'second@example.com'
);

INSERT INTO players (id, bookie_id, name)
VALUES (
    '33333333-3333-4333-8333-333333333334',
    '22222222-2222-4222-8222-222222222223',
    'Other Member'
);

INSERT INTO events (id, name, sport, league, start_time, status, home_team, away_team)
VALUES
    ('67000000-0000-4000-8000-000000000001',
     'NBA Championship', 'Basketball', 'NBA', '2026-06-01 00:00:00+00', 'scheduled',
     'NBA Championship', 'Outright'),
    ('67000000-0000-4000-8000-000000000002',
     'Cancelled Future', 'Basketball', 'NBA', '2026-06-02 00:00:00+00', 'scheduled',
     'Cancelled Future', 'Outright'),
    ('67000000-0000-4000-8000-000000000003',
     'Race Future', 'Basketball', 'NBA', '2026-06-03 00:00:00+00', 'scheduled',
     'Race Future', 'Outright'),
    ('67000000-0000-4000-8000-000000000004',
     'Knicks at Celtics', 'Basketball', 'NBA', '2026-06-04 00:00:00+00', 'scheduled',
     'Celtics', 'Knicks');

-- No market_id column on this fixture. Matching has to use bets.side.
INSERT INTO bets (
    id, bookie_id, player_id, event_id, ticket_id, market, side, odds, stake,
    status, grade_result, is_parlay, parlay_legs
) VALUES
    -- Exact name, +12000. The stuck-pick shape, with no market row.
    ('67000000-0000-4000-8000-000000000010',
     '22222222-2222-4222-8222-222222222222',
     '33333333-3333-4333-8333-333333333333',
     '67000000-0000-4000-8000-000000000001',
     '67000000-0000-4000-8000-000000000010',
     'outright', 'Golden State Warriors', 12000, 10, 'accepted', NULL, false, 1),
    -- Odds stuffed into the side. Still the Warriors.
    ('67000000-0000-4000-8000-000000000012',
     '22222222-2222-4222-8222-222222222222',
     '33333333-3333-4333-8333-333333333333',
     '67000000-0000-4000-8000-000000000001',
     '67000000-0000-4000-8000-000000000012',
     'futures', 'Golden State Warriors +12000', 500, 2, 'accepted', NULL, false, 1),
    -- A shorter name is a different selection.
    ('67000000-0000-4000-8000-000000000014',
     '22222222-2222-4222-8222-222222222222',
     '33333333-3333-4333-8333-333333333333',
     '67000000-0000-4000-8000-000000000001',
     '67000000-0000-4000-8000-000000000014',
     'outright', 'Warriors', 200, 3, 'accepted', NULL, false, 1),
    -- Other book, other team.
    ('67000000-0000-4000-8000-000000000011',
     '22222222-2222-4222-8222-222222222223',
     '33333333-3333-4333-8333-333333333334',
     '67000000-0000-4000-8000-000000000001',
     '67000000-0000-4000-8000-000000000011',
     'outright', 'Boston Celtics', -110, 5, 'accepted', NULL, false, 1),
    -- Declined picks are not settled.
    ('67000000-0000-4000-8000-000000000013',
     '22222222-2222-4222-8222-222222222222',
     '33333333-3333-4333-8333-333333333333',
     '67000000-0000-4000-8000-000000000001',
     '67000000-0000-4000-8000-000000000013',
     'outright', 'Golden State Warriors', 12000, 9, 'declined', NULL, false, 1),
    -- Futures leg loses, so the multi settles now and the open leg is closed.
    ('67000000-0000-4000-8000-000000000020',
     '22222222-2222-4222-8222-222222222222',
     '33333333-3333-4333-8333-333333333333',
     '67000000-0000-4000-8000-000000000001',
     '67000000-0000-4000-8000-0000000000a1',
     'outright', 'Boston Celtics', 300, 25, 'accepted', NULL, true, 2),
    ('67000000-0000-4000-8000-000000000021',
     '22222222-2222-4222-8222-222222222222',
     '33333333-3333-4333-8333-333333333333',
     '67000000-0000-4000-8000-000000000004',
     '67000000-0000-4000-8000-0000000000a1',
     'moneyline', 'Celtics', -110, 25, 'accepted', NULL, true, 2),
    -- Futures leg wins and the other leg is still open: the ticket waits.
    ('67000000-0000-4000-8000-000000000030',
     '22222222-2222-4222-8222-222222222222',
     '33333333-3333-4333-8333-333333333333',
     '67000000-0000-4000-8000-000000000001',
     '67000000-0000-4000-8000-0000000000a2',
     'outright', 'Golden State Warriors', 400, 15, 'accepted', NULL, true, 2),
    ('67000000-0000-4000-8000-000000000031',
     '22222222-2222-4222-8222-222222222222',
     '33333333-3333-4333-8333-333333333333',
     '67000000-0000-4000-8000-000000000004',
     '67000000-0000-4000-8000-0000000000a2',
     'moneyline', 'Knicks', -110, 15, 'accepted', NULL, true, 2),
    ('67000000-0000-4000-8000-000000000040',
     '22222222-2222-4222-8222-222222222222',
     '33333333-3333-4333-8333-333333333333',
     '67000000-0000-4000-8000-000000000002',
     '67000000-0000-4000-8000-000000000040',
     'outright', 'Anyone', 100, 8, 'accepted', NULL, false, 1),
    ('67000000-0000-4000-8000-000000000050',
     '22222222-2222-4222-8222-222222222222',
     '33333333-3333-4333-8333-333333333333',
     '67000000-0000-4000-8000-000000000003',
     '67000000-0000-4000-8000-000000000050',
     'outright', 'Team A', 100, 4, 'accepted', NULL, false, 1);
