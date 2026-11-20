BEGIN;
SELECT claim_bet_submission(
    'submit_bets',
    'test065-concurrent',
    '11111111-1111-4111-8111-111111111111',
    '33333333-3333-4333-8333-333333333333',
    '22222222-2222-4222-8222-222222222222',
    '{"operation":"submit_bets","player_id":"33333333-3333-4333-8333-333333333333","bookie_id":"22222222-2222-4222-8222-222222222222","bets":[{"event_id":"test065-event","market_id":"1050ea8a-0000-4000-8000-0000001050ea","side":"a","odds":-110,"stake":"1.00"}]}'::jsonb,
    jsonb_build_array(jsonb_build_object(
        'event_id', 'test065-event',
        'ticket_id', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa10',
        'market', 'spread',
        'market_id', '1050ea8a-0000-4000-8000-0000001050ea',
        'side', 'Colorado +3',
        'odds', -110,
        'stake', 1,
        'status', 'accepted',
        'is_parlay', false,
        'parlay_legs', 1
    )),
    '{}'::jsonb
);
SELECT pg_sleep(2);
COMMIT;
