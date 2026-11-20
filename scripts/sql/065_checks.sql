-- Behavior of claim_bet_submission / peek_bet_submission on the local fixture.
-- Raises if a check fails. Does not touch the seeded Colorado pair
-- (defc7465 / 51bd1346): every row this file writes uses the test065- prefix.

-- Replay returns the original ticket even when the second call carries a
-- different ticket id, and it inserts nothing.
DO $$
DECLARE
    v jsonb;
    n int;
    payload jsonb := '{"operation":"submit_bets","player_id":"33333333-3333-4333-8333-333333333333","bookie_id":"22222222-2222-4222-8222-222222222222","bets":[{"event_id":"test065-event","market_id":"1050ea8a-0000-4000-8000-0000001050ea","side":"a","odds":-110,"stake":"1.00"}]}'::jsonb;
BEGIN
    v := claim_bet_submission(
        'submit_bets',
        'test065-replay',
        '11111111-1111-4111-8111-111111111111',
        '33333333-3333-4333-8333-333333333333',
        '22222222-2222-4222-8222-222222222222',
        payload,
        jsonb_build_array(jsonb_build_object(
            'event_id', 'test065-event',
            'ticket_id', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
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
    IF v->>'replayed' <> 'false' THEN
        RAISE EXCEPTION 'first claim was a replay';
    END IF;
    IF v->'response'->'bets'->0->>'ticket_id' <> 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1' THEN
        RAISE EXCEPTION 'first claim ticket %', v->'response'->'bets'->0->>'ticket_id';
    END IF;

    v := claim_bet_submission(
        'submit_bets',
        'test065-replay',
        '11111111-1111-4111-8111-111111111111',
        '33333333-3333-4333-8333-333333333333',
        '22222222-2222-4222-8222-222222222222',
        payload,
        jsonb_build_array(jsonb_build_object(
            'event_id', 'test065-event',
            'ticket_id', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2',
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
    IF v->>'replayed' <> 'true' THEN
        RAISE EXCEPTION 'second claim was not a replay';
    END IF;
    IF v->'response'->'bets'->0->>'ticket_id' <> 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1' THEN
        RAISE EXCEPTION 'replay returned ticket %', v->'response'->'bets'->0->>'ticket_id';
    END IF;
    SELECT count(*) INTO n FROM bets WHERE idempotency_key = 'test065-replay';
    IF n <> 1 THEN
        RAISE EXCEPTION 'replay left % bets', n;
    END IF;
    SELECT count(DISTINCT ticket_id) INTO n FROM bets WHERE idempotency_key = 'test065-replay';
    IF n <> 1 THEN
        RAISE EXCEPTION 'replay left % tickets', n;
    END IF;
END $$;

-- Same key, different payload: raise, write nothing.
DO $$
DECLARE
    n int;
    payload jsonb := '{"operation":"submit_bets","player_id":"33333333-3333-4333-8333-333333333333","bookie_id":"22222222-2222-4222-8222-222222222222","bets":[{"event_id":"test065-event","market_id":"1050ea8a-0000-4000-8000-0000001050ea","side":"a","odds":-110,"stake":"5.00"}]}'::jsonb;
BEGIN
    PERFORM claim_bet_submission(
        'submit_bets',
        'test065-replay',
        '11111111-1111-4111-8111-111111111111',
        '33333333-3333-4333-8333-333333333333',
        '22222222-2222-4222-8222-222222222222',
        payload,
        jsonb_build_array(jsonb_build_object(
            'event_id', 'test065-event',
            'ticket_id', 'cccccccc-cccc-4ccc-8ccc-ccccccccccc3',
            'market', 'spread',
            'market_id', '1050ea8a-0000-4000-8000-0000001050ea',
            'side', 'Colorado +3',
            'odds', -110,
            'stake', 5,
            'status', 'accepted',
            'is_parlay', false,
            'parlay_legs', 1
        )),
        '{}'::jsonb
    );
    RAISE EXCEPTION 'different payload was accepted';
EXCEPTION
    WHEN SQLSTATE 'P0422' THEN
        SELECT count(*) INTO n FROM bets WHERE idempotency_key = 'test065-replay';
        IF n <> 1 THEN
            RAISE EXCEPTION 'mismatch wrote bets, count %', n;
        END IF;
        IF EXISTS (SELECT 1 FROM bets WHERE ticket_id = 'cccccccc-cccc-4ccc-8ccc-ccccccccccc3') THEN
            RAISE EXCEPTION 'mismatch inserted the rejected ticket';
        END IF;
END $$;

-- Peek agrees: a miss, a replay, and a mismatch.
DO $$
DECLARE
    v jsonb;
    payload jsonb := '{"operation":"submit_bet","player_id":"33333333-3333-4333-8333-333333333333","bookie_id":"22222222-2222-4222-8222-222222222222","event_id":"test065-event","market_id":"1050ea8a-0000-4000-8000-0000001050ea","side":"a","odds":-110,"stake":"2.00"}'::jsonb;
BEGIN
    v := peek_bet_submission(
        'submit_bet', 'test065-peek',
        '11111111-1111-4111-8111-111111111111',
        '33333333-3333-4333-8333-333333333333',
        payload
    );
    IF v->>'found' <> 'false' THEN
        RAISE EXCEPTION 'peek found a key that was not stored';
    END IF;

    PERFORM claim_bet_submission(
        'submit_bet', 'test065-peek',
        '11111111-1111-4111-8111-111111111111',
        '33333333-3333-4333-8333-333333333333',
        '22222222-2222-4222-8222-222222222222',
        payload,
        jsonb_build_array(jsonb_build_object(
            'event_id', 'test065-event',
            'ticket_id', 'dddddddd-dddd-4ddd-8ddd-ddddddddddd4',
            'market', 'spread',
            'market_id', '1050ea8a-0000-4000-8000-0000001050ea',
            'side', 'a',
            'odds', -110,
            'stake', 2,
            'status', 'accepted',
            'is_parlay', false,
            'parlay_legs', 1
        )),
        '{}'::jsonb
    );

    v := peek_bet_submission(
        'submit_bet', 'test065-peek',
        '11111111-1111-4111-8111-111111111111',
        '33333333-3333-4333-8333-333333333333',
        payload
    );
    IF v->>'found' <> 'true' OR v->>'replayed' <> 'true' THEN
        RAISE EXCEPTION 'peek did not replay: %', v;
    END IF;
    IF v->'response'->'bet'->>'ticket_id' <> 'dddddddd-dddd-4ddd-8ddd-ddddddddddd4' THEN
        RAISE EXCEPTION 'peek returned the wrong bet';
    END IF;

    BEGIN
        PERFORM peek_bet_submission(
            'submit_bet', 'test065-peek',
            '11111111-1111-4111-8111-111111111111',
            '33333333-3333-4333-8333-333333333333',
            jsonb_set(payload, '{stake}', '"9.00"')
        );
        RAISE EXCEPTION 'peek accepted a different payload';
    EXCEPTION
        WHEN SQLSTATE 'P0422' THEN
            NULL;
    END;
END $$;

-- A batch and a parlay share one key across rows and still replay as one submit.
DO $$
DECLARE
    n int;
    v jsonb;
    payload jsonb := '{"operation":"submit_bets","bets":[1,2]}'::jsonb;
BEGIN
    PERFORM claim_bet_submission(
        'submit_bets', 'test065-batch',
        '11111111-1111-4111-8111-111111111111',
        '33333333-3333-4333-8333-333333333333',
        '22222222-2222-4222-8222-222222222222',
        payload,
        jsonb_build_array(
            jsonb_build_object('event_id','test065-event','ticket_id','e1e1e1e1-e1e1-41e1-81e1-e1e1e1e1e1e1','market','h2h','market_id','1050ea8a-0000-4000-8000-0000001050ea','side','a','odds',-110,'stake',1,'status','accepted','is_parlay',false,'parlay_legs',1),
            jsonb_build_object('event_id','test065-event-b','ticket_id','e2e2e2e2-e2e2-42e2-82e2-e2e2e2e2e2e2','market','h2h','market_id','1050ea8a-0000-4000-8000-0000001050ea','side','b','odds',120,'stake',1,'status','accepted','is_parlay',false,'parlay_legs',1)
        ),
        jsonb_build_object('failed', jsonb_build_array(jsonb_build_object('index', 2, 'error', 'line_changed')))
    );
    SELECT count(*) INTO n FROM bets WHERE idempotency_key = 'test065-batch';
    IF n <> 2 THEN
        RAISE EXCEPTION 'batch inserted % bets', n;
    END IF;
    v := claim_bet_submission(
        'submit_bets', 'test065-batch',
        '11111111-1111-4111-8111-111111111111',
        '33333333-3333-4333-8333-333333333333',
        '22222222-2222-4222-8222-222222222222',
        payload,
        jsonb_build_array(jsonb_build_object('event_id','test065-event','ticket_id','ffffffff-ffff-4fff-8fff-ffffffffffff','market','h2h','market_id','1050ea8a-0000-4000-8000-0000001050ea','side','a','odds',-110,'stake',1,'status','accepted','is_parlay',false,'parlay_legs',1)),
        '{}'::jsonb
    );
    IF v->>'replayed' <> 'true' THEN
        RAISE EXCEPTION 'batch replay missed';
    END IF;
    IF jsonb_array_length(v->'response'->'bets') <> 2 THEN
        RAISE EXCEPTION 'batch replay dropped a bet';
    END IF;
    IF jsonb_array_length(v->'response'->'failed') <> 1 THEN
        RAISE EXCEPTION 'batch replay dropped the failed entry';
    END IF;
    SELECT count(*) INTO n FROM bets WHERE idempotency_key = 'test065-batch';
    IF n <> 2 THEN
        RAISE EXCEPTION 'batch replay inserted, count %', n;
    END IF;
END $$;

DO $$
DECLARE
    n int;
    tickets int;
    payload jsonb := '{"operation":"submit_parlay","stake":"1.00","combined_odds":150,"legs":[]}'::jsonb;
BEGIN
    PERFORM claim_bet_submission(
        'submit_parlay', 'test065-parlay',
        '11111111-1111-4111-8111-111111111111',
        '33333333-3333-4333-8333-333333333333',
        '22222222-2222-4222-8222-222222222222',
        payload,
        jsonb_build_array(
            jsonb_build_object('event_id','test065-event','ticket_id','abababab-abab-4aba-8aba-abababababab','market','h2h','market_id','1050ea8a-0000-4000-8000-0000001050ea','side','Home','odds',-110,'stake',1,'status','accepted','is_parlay',true,'parlay_legs',2),
            jsonb_build_object('event_id','test065-event-b','ticket_id','abababab-abab-4aba-8aba-abababababab','market','h2h','market_id','1050ea8a-0000-4000-8000-0000001050eb','side','Away','odds',-120,'stake',1,'status','accepted','is_parlay',true,'parlay_legs',2)
        ),
        '{}'::jsonb
    );
    SELECT count(*), count(DISTINCT ticket_id) INTO n, tickets
    FROM bets WHERE idempotency_key = 'test065-parlay';
    IF n <> 2 OR tickets <> 1 THEN
        RAISE EXCEPTION 'parlay rows % tickets %', n, tickets;
    END IF;
END $$;

-- Another player's identical key is a different submit.
DO $$
DECLARE
    n int;
    payload jsonb := '{"operation":"submit_bets","player_id":"44444444-4444-4444-8444-444444444444","bookie_id":"22222222-2222-4222-8222-222222222222","bets":[{"stake":"1.00"}]}'::jsonb;
BEGIN
    PERFORM claim_bet_submission(
        'submit_bets', 'test065-replay',
        '11111111-1111-4111-8111-111111111112',
        '44444444-4444-4444-8444-444444444444',
        '22222222-2222-4222-8222-222222222222',
        payload,
        jsonb_build_array(jsonb_build_object(
            'event_id', 'test065-event',
            'ticket_id', '12121212-1212-4121-8121-121212121212',
            'market', 'spread',
            'market_id', '1050ea8a-0000-4000-8000-0000001050ea',
            'side', 'a',
            'odds', -110,
            'stake', 1,
            'status', 'accepted',
            'is_parlay', false,
            'parlay_legs', 1
        )),
        '{}'::jsonb
    );
    SELECT count(*) INTO n
    FROM bets
    WHERE idempotency_key = 'test065-replay'
      AND player_id = '44444444-4444-4444-8444-444444444444';
    IF n <> 1 THEN
        RAISE EXCEPTION 'other player did not get their own ticket, count %', n;
    END IF;
    SELECT count(*) INTO n FROM idempotency_keys WHERE key = 'test065-replay' AND operation = 'submit_bets';
    IF n <> 2 THEN
        RAISE EXCEPTION 'expected two player-scoped key rows, got %', n;
    END IF;
END $$;

-- A legacy row (null player_id, null payload) replays and does not insert.
DO $$
DECLARE
    v jsonb;
    n int;
    legacy_bet uuid := '13131313-1313-4131-8131-131313131313';
BEGIN
    INSERT INTO bets (
        id, bookie_id, player_id, event_id, ticket_id, market, side, odds, stake, status
    ) VALUES (
        legacy_bet,
        '22222222-2222-4222-8222-222222222222',
        '33333333-3333-4333-8333-333333333333',
        'test065-event',
        '14141414-1414-4141-8141-141414141414',
        'spread', 'Colorado +3', -110, 1, 'accepted'
    );
    INSERT INTO idempotency_keys (key, operation, response, user_id)
    VALUES (
        'test065-legacy',
        'submit_bets',
        '{"success":true,"bets":[{"id":"13131313-1313-4131-8131-131313131313","ticket_id":"14141414-1414-4141-8141-141414141414"}]}',
        '11111111-1111-4111-8111-111111111111'
    );

    v := claim_bet_submission(
        'submit_bets', 'test065-legacy',
        '11111111-1111-4111-8111-111111111111',
        '33333333-3333-4333-8333-333333333333',
        '22222222-2222-4222-8222-222222222222',
        '{"operation":"submit_bets","stake":"1.00"}'::jsonb,
        jsonb_build_array(jsonb_build_object(
            'event_id', 'test065-event',
            'ticket_id', '15151515-1515-4151-8151-151515151515',
            'market', 'spread',
            'side', 'Colorado +3',
            'odds', -110,
            'stake', 1,
            'status', 'accepted',
            'is_parlay', false,
            'parlay_legs', 1
        )),
        '{}'::jsonb
    );
    IF v->>'replayed' <> 'true' THEN
        RAISE EXCEPTION 'legacy key was not replayed';
    END IF;
    IF v->'response'->'bets'->0->>'id' <> legacy_bet::text THEN
        RAISE EXCEPTION 'legacy replay returned %', v->'response';
    END IF;
    SELECT count(*) INTO n FROM bets WHERE ticket_id = '15151515-1515-4151-8151-151515151515';
    IF n <> 0 THEN
        RAISE EXCEPTION 'legacy replay inserted a second ticket';
    END IF;
    IF EXISTS (
        SELECT 1 FROM idempotency_keys
        WHERE key = 'test065-legacy' AND player_id IS NOT NULL
    ) THEN
        RAISE EXCEPTION 'legacy replay rewrote the stored key';
    END IF;
END $$;

-- The old function's insert still conflicts for the same user, and a
-- different user can store the same submit key. Non-submit keys stay global.
DO $$
BEGIN
    INSERT INTO idempotency_keys (key, operation, response, user_id)
    VALUES ('test065-old', 'submit_bets', '{"success":true}', '11111111-1111-4111-8111-111111111111');
    BEGIN
        INSERT INTO idempotency_keys (key, operation, response, user_id)
        VALUES ('test065-old', 'submit_bets', '{"success":true}', '11111111-1111-4111-8111-111111111111');
        RAISE EXCEPTION 'same user stored a submit key twice';
    EXCEPTION
        WHEN unique_violation THEN
            NULL;
    END;

    INSERT INTO idempotency_keys (key, operation, response, user_id)
    VALUES ('test065-old', 'submit_bets', '{"success":true}', '11111111-1111-4111-8111-111111111112');

    INSERT INTO idempotency_keys (key, operation, response, user_id)
    VALUES ('test065-settle', 'settle_bet', '{}', '11111111-1111-4111-8111-111111111111');
    BEGIN
        INSERT INTO idempotency_keys (key, operation, response, user_id)
        VALUES ('test065-settle', 'settle_bet', '{}', '11111111-1111-4111-8111-111111111112');
        RAISE EXCEPTION 'non-submit key was not globally unique';
    EXCEPTION
        WHEN unique_violation THEN
            NULL;
    END;
END $$;

-- The seeded duplicate was not rewritten.
DO $$
DECLARE
    n int;
BEGIN
    SELECT count(*) INTO n
    FROM bets
    WHERE id IN (
        '55c3ae26-0000-4000-8000-000000055c3a',
        '569a7dbd-0000-4000-8000-000000569a7d'
    )
      AND idempotency_key IS NULL
      AND odds = -110
      AND stake = 1;
    IF n <> 2 THEN
        RAISE EXCEPTION 'seeded bets were rewritten (% still intact)', n;
    END IF;
    IF EXISTS (
        SELECT 1 FROM idempotency_keys
        WHERE key = '0845800d-0000-4000-8000-000000084580'
          AND (player_id IS NOT NULL OR request_payload IS NOT NULL)
    ) THEN
        RAISE EXCEPTION 'seeded key was backfilled';
    END IF;
END $$;
