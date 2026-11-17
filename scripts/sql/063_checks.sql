-- Behavior after migration 063. Fails the script with an exception.
-- Assumes ledger_rows_before_063 was snapshotted before the migration.

DO $$
DECLARE
    v_changed integer;
    v_dupes integer;
BEGIN
    SELECT count(*) INTO v_changed
      FROM (
        SELECT id, bookie_id, player_id, bet_id, amount, type, description,
               created_at, prev_hash, entry_hash, seq
          FROM ledger_rows_before_063
        EXCEPT
        SELECT id, bookie_id, player_id, bet_id, amount, type, description,
               created_at, prev_hash, entry_hash, seq
          FROM ledger_entries
      ) d;
    IF v_changed <> 0 THEN
        RAISE EXCEPTION 'migration changed % existing ledger rows', v_changed;
    END IF;

    IF (SELECT count(*) FROM ledger_entries) <> (SELECT count(*) FROM ledger_rows_before_063) THEN
        RAISE EXCEPTION 'migration inserted or deleted ledger rows';
    END IF;

    SELECT count(*) INTO v_dupes
      FROM (
        SELECT bet_id
          FROM ledger_entries
         WHERE type IN ('settlement', 'reversal')
           AND bet_id IS NOT NULL
         GROUP BY bet_id
        HAVING count(*) FILTER (WHERE type = 'settlement')
             - count(*) FILTER (WHERE type = 'reversal') > 1
      ) d;
    IF v_dupes <> 2 THEN
        RAISE EXCEPTION 'expected 2 bets with more than one active settlement, found %', v_dupes;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM ledger_entries
         WHERE bet_id = 'e4df12ed-0000-4000-8000-000000000076'
           AND type = 'settlement'
        HAVING count(*) = 2
    ) THEN
        RAISE EXCEPTION '76ers duplicate pair is missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM ledger_entries
         WHERE bet_id = '297c5d53-0000-4000-8000-000000000297'
           AND type = 'settlement'
        HAVING count(*) = 2
    ) THEN
        RAISE EXCEPTION 'Wolves duplicate pair is missing';
    END IF;

    RAISE NOTICE 'PASS migration left both seeded duplicate settlements in place';
END $$;

-- Calling settle on a bet that already has two active settlements posts nothing.
DO $$
DECLARE
    v_before integer;
    v_after integer;
    v_result jsonb;
BEGIN
    SELECT count(*) INTO v_before
      FROM ledger_entries
     WHERE bet_id = 'e4df12ed-0000-4000-8000-000000000076'
       AND type = 'settlement';

    v_result := settle_bet_tx(
        'e4df12ed-0000-4000-8000-000000000076',
        '11111111-1111-4111-8111-111111111111',
        'again-76ers',
        'auto'
    );

    SELECT count(*) INTO v_after
      FROM ledger_entries
     WHERE bet_id = 'e4df12ed-0000-4000-8000-000000000076'
       AND type = 'settlement';

    IF (v_result->>'success')::boolean IS NOT TRUE OR (v_result->>'idempotent')::boolean IS NOT TRUE THEN
        RAISE EXCEPTION 'duplicate bet should return the existing settlement: %', v_result;
    END IF;
    IF v_after <> v_before THEN
        RAISE EXCEPTION 'settle on an existing duplicate posted another row (% -> %)', v_before, v_after;
    END IF;
    RAISE NOTICE 'PASS settle on e4df12ed posts nothing';
END $$;

-- Sequential double settle of a clean single: one ledger row, price -4.03, version 1.
DO $$
DECLARE
    v_first jsonb;
    v_second jsonb;
    v_count integer;
    v_version integer;
BEGIN
    v_first := settle_bet_tx(
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
        '11111111-1111-4111-8111-111111111111',
        'seq-1',
        'manual'
    );
    v_second := settle_bet_tx(
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
        '11111111-1111-4111-8111-111111111111',
        'seq-2',
        'auto'
    );

    IF (v_first->>'success')::boolean IS NOT TRUE OR (v_first->>'idempotent')::boolean IS TRUE THEN
        RAISE EXCEPTION 'first settle failed: %', v_first;
    END IF;
    IF (v_first->'ledger_entry'->>'amount')::numeric <> -4.03 THEN
        RAISE EXCEPTION 'expected -4.03 for $5 at -124, got %', v_first->'ledger_entry'->>'amount';
    END IF;
    IF (v_first->>'settlement_version')::integer <> 1 THEN
        RAISE EXCEPTION 'first settlement_version should be 1: %', v_first;
    END IF;
    IF (v_second->>'success')::boolean IS NOT TRUE OR (v_second->>'idempotent')::boolean IS NOT TRUE THEN
        RAISE EXCEPTION 'second settle should be idempotent: %', v_second;
    END IF;
    IF v_second->'ledger_entry'->>'id' IS DISTINCT FROM v_first->'ledger_entry'->>'id' THEN
        RAISE EXCEPTION 'second settle returned a different ledger row';
    END IF;

    SELECT count(*) INTO v_count
      FROM ledger_entries
     WHERE bet_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'
       AND type = 'settlement';
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'sequential double settle posted % ledger rows', v_count;
    END IF;

    SELECT max(settlement_version) INTO v_version
      FROM settlement_events
     WHERE bet_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1';
    IF v_version <> 1 THEN
        RAISE EXCEPTION 'expected settlement_version 1, got %', v_version;
    END IF;

    RAISE NOTICE 'PASS sequential double settle posts one ledger entry';
END $$;

-- Same grade is a no-op. A different grade reverses once. The same key does not reverse again.
-- Re-settle then posts version 2.
DO $$
DECLARE
    v_same jsonb;
    v_override jsonb;
    v_replay jsonb;
    v_resettle jsonb;
    v_settlements integer;
    v_reversals integer;
    v_active integer;
    v_version integer;
    v_audits integer;
BEGIN
    SELECT count(*) INTO v_audits
      FROM audit_events
     WHERE entity_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'
       AND action_type = 'override';

    v_same := override_grade_tx(
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
        '11111111-1111-4111-8111-111111111111',
        'win',
        'already win',
        'override-same'
    );
    IF (v_same->>'success')::boolean IS NOT TRUE OR (v_same->>'noop')::boolean IS NOT TRUE THEN
        RAISE EXCEPTION 'same-grade override should no-op: %', v_same;
    END IF;
    IF (SELECT count(*) FROM ledger_entries
         WHERE bet_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1' AND type = 'reversal') <> 0 THEN
        RAISE EXCEPTION 'same-grade override reversed the settlement';
    END IF;

    v_override := override_grade_tx(
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
        '11111111-1111-4111-8111-111111111111',
        'loss',
        'wrong grade',
        'override-loss'
    );
    IF (v_override->>'success')::boolean IS NOT TRUE
       OR (v_override->>'settlement_reversed')::boolean IS NOT TRUE THEN
        RAISE EXCEPTION 'override to loss should reverse: %', v_override;
    END IF;

    v_replay := override_grade_tx(
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
        '11111111-1111-4111-8111-111111111111',
        'loss',
        'wrong grade',
        'override-loss'
    );
    IF (v_replay->>'success')::boolean IS NOT TRUE OR (v_replay->>'idempotent')::boolean IS NOT TRUE THEN
        RAISE EXCEPTION 'override replay should honor the key: %', v_replay;
    END IF;

    SELECT count(*) INTO v_reversals
      FROM ledger_entries
     WHERE bet_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'
       AND type = 'reversal';
    IF v_reversals <> 1 THEN
        RAISE EXCEPTION 'override replay posted % reversals', v_reversals;
    END IF;

    SELECT count(*) INTO v_audits
      FROM audit_events
     WHERE entity_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'
       AND action_type = 'override';
    IF v_audits <> 1 THEN
        RAISE EXCEPTION 'expected one override audit, found %', v_audits;
    END IF;

    v_resettle := settle_bet_tx(
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
        '11111111-1111-4111-8111-111111111111',
        'seq-after-override',
        'manual'
    );
    IF (v_resettle->>'success')::boolean IS NOT TRUE OR (v_resettle->>'idempotent')::boolean IS TRUE THEN
        RAISE EXCEPTION 're-settle after override failed: %', v_resettle;
    END IF;
    IF (v_resettle->>'settlement_version')::integer <> 2 THEN
        RAISE EXCEPTION 're-settle should be version 2: %', v_resettle;
    END IF;
    IF (v_resettle->'ledger_entry'->>'amount')::numeric <> 5 THEN
        RAISE EXCEPTION 'loss re-settle should post the stake, got %', v_resettle->'ledger_entry'->>'amount';
    END IF;

    SELECT count(*) FILTER (WHERE type = 'settlement'),
           count(*) FILTER (WHERE type = 'reversal')
      INTO v_settlements, v_reversals
      FROM ledger_entries
     WHERE bet_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1';
    v_active := v_settlements - v_reversals;
    SELECT max(settlement_version) INTO v_version
      FROM settlement_events
     WHERE bet_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1';

    IF v_settlements <> 2 OR v_reversals <> 1 OR v_active <> 1 OR v_version <> 2 THEN
        RAISE EXCEPTION 'after re-settle expected 2 settlements, 1 reversal, active 1, version 2; got % % % %',
            v_settlements, v_reversals, v_active, v_version;
    END IF;

    RAISE NOTICE 'PASS override no-op, idempotent replay, and re-settle at version 2';
END $$;

-- A second direct insert is rejected. The seeded duplicates are not.
DO $$
BEGIN
    INSERT INTO ledger_entries (bookie_id, player_id, bet_id, amount, type, description)
    VALUES (
        '22222222-2222-4222-8222-222222222222',
        '33333333-3333-4333-8333-333333333333',
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3',
        5, 'settlement', 'first direct'
    );

    BEGIN
        INSERT INTO ledger_entries (bookie_id, player_id, bet_id, amount, type, description)
        VALUES (
            '22222222-2222-4222-8222-222222222222',
            '33333333-3333-4333-8333-333333333333',
            'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3',
            5, 'settlement', 'second direct'
        );
        RAISE EXCEPTION 'second direct settlement insert was allowed';
    EXCEPTION
        WHEN unique_violation THEN
            NULL;
    END;

    IF (SELECT count(*) FROM ledger_entries
         WHERE bet_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3' AND type = 'settlement') <> 1 THEN
        RAISE EXCEPTION 'direct-insert bet should have exactly one settlement';
    END IF;
    RAISE NOTICE 'PASS a second direct settlement insert is rejected';
END $$;

-- Parlay: one ledger row for the ticket, keyed v1. settle_bet_tx on either
-- leg posts nothing. A second insert on the other leg is rejected.
DO $$
DECLARE
    v_first jsonb;
    v_second jsonb;
    v_leg jsonb;
    v_rows integer;
    v_key text;
    v_anchor uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1';
BEGIN
    v_first := settle_parlay_tx(
        'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
        '11111111-1111-4111-8111-111111111111',
        'auto_settle_parlay_cccccccc-cccc-4ccc-8ccc-cccccccccccc_v1',
        'auto',
        -12.34,
        'Multi-Pick won (2 of 2 legs)',
        '{"outcome":"win"}'::jsonb
    );
    v_second := settle_parlay_tx(
        'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
        NULL,
        'auto_settle_parlay_cccccccc-cccc-4ccc-8ccc-cccccccccccc_v1',
        'auto',
        -99,
        'should not post',
        NULL
    );

    IF (v_first->>'success')::boolean IS NOT TRUE OR (v_first->>'idempotent')::boolean IS TRUE THEN
        RAISE EXCEPTION 'parlay settle failed: %', v_first;
    END IF;
    IF (v_first->>'settlement_version')::integer <> 1 THEN
        RAISE EXCEPTION 'parlay version should be 1: %', v_first;
    END IF;
    IF (v_first->'ledger_entry'->>'amount')::numeric <> -12.34 THEN
        RAISE EXCEPTION 'parlay amount not stored: %', v_first;
    END IF;
    IF v_first->'ledger_entry'->>'bet_id' IS DISTINCT FROM v_anchor::text THEN
        RAISE EXCEPTION 'parlay ledger should hang off the lowest leg id, got %', v_first->'ledger_entry'->>'bet_id';
    END IF;
    IF (v_second->>'idempotent')::boolean IS NOT TRUE THEN
        RAISE EXCEPTION 'second parlay settle should be idempotent: %', v_second;
    END IF;
    IF (v_second->'ledger_entry'->>'amount')::numeric <> -12.34 THEN
        RAISE EXCEPTION 'idempotent parlay returned a new amount: %', v_second;
    END IF;

    SELECT count(*) INTO v_rows
      FROM ledger_entries le
      JOIN bets b ON b.id = le.bet_id
     WHERE b.ticket_id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
       AND le.type = 'settlement';
    IF v_rows <> 1 THEN
        RAISE EXCEPTION 'parlay ticket has % settlement rows', v_rows;
    END IF;

    SELECT idempotency_key INTO v_key
      FROM settlement_events
     WHERE bet_id = v_anchor;
    IF v_key IS DISTINCT FROM 'auto_settle_parlay_cccccccc-cccc-4ccc-8ccc-cccccccccccc_v1' THEN
        RAISE EXCEPTION 'parlay key should be auto_settle_parlay_<ticket>_v1, got %', v_key;
    END IF;

    IF (SELECT count(*) FROM bets
         WHERE ticket_id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
           AND status = 'settled') <> 2 THEN
        RAISE EXCEPTION 'both parlay legs should be settled';
    END IF;

    v_leg := settle_bet_tx(
        'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2',
        NULL,
        'leg-b',
        'auto'
    );
    IF (v_leg->>'success')::boolean IS NOT TRUE OR (v_leg->>'idempotent')::boolean IS NOT TRUE THEN
        RAISE EXCEPTION 'settle_bet_tx on a parlay leg should not pay the leg: %', v_leg;
    END IF;
    SELECT count(*) INTO v_rows
      FROM ledger_entries le
      JOIN bets b ON b.id = le.bet_id
     WHERE b.ticket_id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
       AND le.type = 'settlement';
    IF v_rows <> 1 THEN
        RAISE EXCEPTION 'settle_bet_tx on a leg posted a second settlement';
    END IF;

    BEGIN
        INSERT INTO ledger_entries (bookie_id, player_id, bet_id, amount, type, description)
        VALUES (
            '22222222-2222-4222-8222-222222222222',
            '33333333-3333-4333-8333-333333333333',
            'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2',
            -1, 'settlement', 'second leg'
        );
        RAISE EXCEPTION 'settlement on the other parlay leg was allowed';
    EXCEPTION
        WHEN unique_violation THEN
            NULL;
    END;

    RAISE NOTICE 'PASS parlay ticket has one settlement; a per-leg insert is rejected';
END $$;

-- A loss can settle while another leg is still accepted. That leg stays open.
-- The guard is the ticket, so settle_bet_tx on the open leg does not pay it.
DO $$
DECLARE
    v_result jsonb;
    v_rows integer;
    v_open text;
BEGIN
    v_result := settle_parlay_tx(
        'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
        NULL,
        'auto_settle_parlay_eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee_v1',
        'auto',
        20,
        'Multi-Pick lost (2 legs)',
        NULL
    );
    IF (v_result->>'success')::boolean IS NOT TRUE THEN
        RAISE EXCEPTION 'early-loss parlay should settle: %', v_result;
    END IF;

    SELECT status INTO v_open
      FROM bets
     WHERE id = 'dddddddd-dddd-4ddd-8ddd-ddddddddddd2';
    IF v_open IS DISTINCT FROM 'accepted' THEN
        RAISE EXCEPTION 'open parlay leg was closed (status %)', v_open;
    END IF;

    IF (SELECT status FROM bets WHERE id = 'dddddddd-dddd-4ddd-8ddd-ddddddddddd1') IS DISTINCT FROM 'settled' THEN
        RAISE EXCEPTION 'graded losing leg should be settled';
    END IF;

    v_result := settle_bet_tx(
        'dddddddd-dddd-4ddd-8ddd-ddddddddddd2',
        NULL,
        'open-leg',
        'auto'
    );
    IF (v_result->>'idempotent')::boolean IS NOT TRUE THEN
        RAISE EXCEPTION 'open parlay leg must not be settled as a single: %', v_result;
    END IF;

    SELECT count(*) INTO v_rows
      FROM ledger_entries le
      JOIN bets b ON b.id = le.bet_id
     WHERE b.ticket_id = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'
       AND le.type = 'settlement';
    IF v_rows <> 1 THEN
        RAISE EXCEPTION 'early-loss ticket has % settlements', v_rows;
    END IF;

    RAISE NOTICE 'PASS early-loss parlay pays the ticket once and leaves the open leg open';
END $$;

-- The deterministic parlay key can be stored once. A second settlement_events
-- row with that key is rejected. A NULL key is not, so old rows are unaffected.
DO $$
DECLARE
    v_anchor uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1';
    v_bookie uuid := '22222222-2222-4222-8222-222222222222';
    v_ledger uuid;
BEGIN
    SELECT id INTO v_ledger
      FROM ledger_entries
     WHERE bet_id = v_anchor AND type = 'settlement'
     LIMIT 1;

    BEGIN
        INSERT INTO settlement_events (
            bookie_id, bet_id, settlement_version, mode, idempotency_key, ledger_entry_ids
        ) VALUES (
            v_bookie, v_anchor, 99, 'auto',
            'auto_settle_parlay_cccccccc-cccc-4ccc-8ccc-cccccccccccc_v1',
            ARRAY[v_ledger]
        );
        RAISE EXCEPTION 'duplicate idempotency key was inserted';
    EXCEPTION
        WHEN unique_violation THEN
            NULL;
    END;

    INSERT INTO settlement_events (
        bookie_id, bet_id, settlement_version, mode, idempotency_key, ledger_entry_ids
    ) VALUES (
        v_bookie, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3', 1, 'auto',
        NULL, ARRAY[v_ledger]
    );
    INSERT INTO settlement_events (
        bookie_id, bet_id, settlement_version, mode, idempotency_key, ledger_entry_ids
    ) VALUES (
        v_bookie, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3', 2, 'auto',
        NULL, ARRAY[v_ledger]
    );

    RAISE NOTICE 'PASS idempotency_key is unique when set, and NULL keys are not collapsed';
END $$;
