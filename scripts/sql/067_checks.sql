-- Behavior of settle_outright_tx. Fails with an exception.
-- The historical double-settlements from the 063 fixture must stay at two
-- rows each. This script settles only the futures rows seeded for 067.

DO $$
DECLARE
    v_actor UUID := '11111111-1111-4111-8111-111111111111';
    v_event UUID := '67000000-0000-4000-8000-000000000001';
    v_void_event UUID := '67000000-0000-4000-8000-000000000002';
    v_game UUID := '67000000-0000-4000-8000-000000000004';
    v_result JSONB;
    v_again JSONB;
    v_conflict JSONB;
    v_game_result JSONB;
    v_amount NUMERIC;
    v_count INTEGER;
    v_status TEXT;
    v_grade TEXT;
    v_key TEXT;
BEGIN
    IF (SELECT count(*) FROM ledger_entries
         WHERE bet_id = 'e4df12ed-0000-4000-8000-000000000076' AND type = 'settlement') <> 2 THEN
        RAISE EXCEPTION 'fixture lost an e4df12ed settlement before the test';
    END IF;

    IF NOT outright_selection_matches('St. Louis Blues', 'St Louis Blues')
       OR NOT outright_selection_matches('St Louis Blues (+2000)', 'St Louis Blues')
       OR NOT outright_selection_matches('Montréal Canadiens', 'Montreal Canadiens')
       OR NOT outright_selection_matches('Golden State Warriors +12000', 'Golden State Warriors')
       OR outright_selection_matches('Warriors', 'Golden State Warriors') THEN
        RAISE EXCEPTION 'name matcher disagreed: % / % / %',
            outright_side_key('St. Louis Blues'),
            outright_side_key('St Louis Blues (+2000)'),
            outright_side_key('Montréal Canadiens');
    END IF;

    v_result := settle_outright_tx(v_event, 'Not A Real Team', false, v_actor);
    IF v_result->>'error' <> 'unknown_winner' THEN
        RAISE EXCEPTION 'unknown winner should be refused, got %', v_result;
    END IF;
    IF (SELECT count(*) FROM outright_results) <> 0 THEN
        RAISE EXCEPTION 'unknown winner wrote a result';
    END IF;

    v_result := settle_outright_tx(v_event, 'Golden State Warriors', false, v_actor, false, true);
    IF COALESCE((v_result->>'dry_run')::boolean, false) IS NOT TRUE
       OR (v_result->>'wins')::int <> 3
       OR (v_result->>'losses')::int <> 3 THEN
        RAISE EXCEPTION 'dry run counts were %', v_result;
    END IF;
    IF (SELECT count(*) FROM outright_results) <> 0
       OR (SELECT count(*) FROM ledger_entries WHERE bet_id = '67000000-0000-4000-8000-000000000010') <> 0 THEN
        RAISE EXCEPTION 'dry run wrote rows';
    END IF;

    v_result := settle_outright_tx(v_event, 'Golden State Warriors', false, v_actor);
    IF COALESCE((v_result->>'success')::boolean, false) IS NOT TRUE THEN
        RAISE EXCEPTION 'first settle failed: %', v_result;
    END IF;
    IF (v_result->>'singles_settled')::int <> 4 THEN
        RAISE EXCEPTION 'expected 4 singles settled, got %', v_result;
    END IF;
    IF (v_result->>'parlays_settled')::int <> 1 THEN
        RAISE EXCEPTION 'expected the losing multi to settle, got %', v_result;
    END IF;
    IF (v_result->>'parlays_waiting')::int <> 1 THEN
        RAISE EXCEPTION 'expected the winning multi to wait, got %', v_result;
    END IF;

    SELECT amount INTO v_amount FROM ledger_entries
     WHERE bet_id = '67000000-0000-4000-8000-000000000010' AND type = 'settlement';
    IF v_amount <> -1200 THEN
        RAISE EXCEPTION 'Warriors +12000 on $10 should pay -1200, got %', v_amount;
    END IF;

    SELECT amount INTO v_amount FROM ledger_entries
     WHERE bet_id = '67000000-0000-4000-8000-000000000012' AND type = 'settlement';
    IF v_amount <> -10 THEN
        RAISE EXCEPTION 'odds-suffixed side should win -10, got %', v_amount;
    END IF;

    SELECT amount, bookie_id::text INTO v_amount, v_status FROM ledger_entries
     WHERE bet_id = '67000000-0000-4000-8000-000000000011' AND type = 'settlement';
    IF v_amount <> 5 OR v_status <> '22222222-2222-4222-8222-222222222223' THEN
        RAISE EXCEPTION 'other book should lose +5, got % bookie %', v_amount, v_status;
    END IF;

    SELECT amount INTO v_amount FROM ledger_entries
     WHERE bet_id = '67000000-0000-4000-8000-000000000014' AND type = 'settlement';
    IF v_amount <> 3 THEN
        RAISE EXCEPTION 'nickname Warriors must lose, got %', v_amount;
    END IF;

    SELECT idempotency_key INTO v_key FROM settlement_events
     WHERE bet_id = '67000000-0000-4000-8000-000000000010';
    IF v_key <> 'outright_settle_67000000-0000-4000-8000-000000000010_v1' THEN
        RAISE EXCEPTION 'single key was %', v_key;
    END IF;

    IF (SELECT count(*) FROM ledger_entries
         WHERE bet_id = '67000000-0000-4000-8000-000000000013') <> 0 THEN
        RAISE EXCEPTION 'declined pick was paid';
    END IF;
    SELECT status INTO v_status FROM bets WHERE id = '67000000-0000-4000-8000-000000000015';
    IF v_status <> 'pending'
       OR (SELECT count(*) FROM ledger_entries WHERE bet_id = '67000000-0000-4000-8000-000000000015') <> 0 THEN
        RAISE EXCEPTION 'pending pick was touched, status %', v_status;
    END IF;
    SELECT status INTO v_status FROM bets WHERE id = '67000000-0000-4000-8000-000000000013';
    IF v_status <> 'declined' THEN
        RAISE EXCEPTION 'declined pick status changed to %', v_status;
    END IF;

    SELECT count(*) INTO v_count FROM ledger_entries le
      JOIN bets b ON b.id = le.bet_id
     WHERE b.ticket_id = '67000000-0000-4000-8000-0000000000a1' AND le.type = 'settlement';
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'losing multi posted % ledger rows', v_count;
    END IF;
    SELECT le.amount, se.idempotency_key INTO v_amount, v_key
      FROM ledger_entries le
      JOIN bets b ON b.id = le.bet_id
      JOIN settlement_events se ON se.bet_id = le.bet_id
     WHERE b.ticket_id = '67000000-0000-4000-8000-0000000000a1' AND le.type = 'settlement';
    IF v_amount <> 25 OR v_key <> 'auto_settle_parlay_67000000-0000-4000-8000-0000000000a1_v1' THEN
        RAISE EXCEPTION 'losing multi amount % key %', v_amount, v_key;
    END IF;
    SELECT status INTO v_status FROM bets WHERE id = '67000000-0000-4000-8000-000000000021';
    IF v_status <> 'settled' THEN
        RAISE EXCEPTION 'early loss should close the unplayed leg, status %', v_status;
    END IF;

    SELECT count(*) INTO v_count FROM ledger_entries le
      JOIN bets b ON b.id = le.bet_id
     WHERE b.ticket_id = '67000000-0000-4000-8000-0000000000a2' AND le.type = 'settlement';
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'waiting multi posted a ledger row';
    END IF;
    SELECT status, grade_result INTO v_status, v_grade
      FROM bets WHERE id = '67000000-0000-4000-8000-000000000030';
    IF v_status <> 'graded' OR v_grade <> 'win' THEN
        RAISE EXCEPTION 'waiting futures leg is % / %', v_status, v_grade;
    END IF;
    SELECT status INTO v_status FROM bets WHERE id = '67000000-0000-4000-8000-000000000031';
    IF v_status <> 'accepted' THEN
        RAISE EXCEPTION 'open multi leg was closed while the ticket waits: %', v_status;
    END IF;

    SELECT status INTO v_status FROM events WHERE id = v_event;
    IF v_status <> 'final' THEN
        RAISE EXCEPTION 'recording the winner should mark the event final, got %', v_status;
    END IF;

    -- Same winner again. No second ledger row.
    v_again := settle_outright_tx(v_event, '  golden   state warriors ', false, v_actor);
    IF COALESCE((v_again->>'success')::boolean, false) IS NOT TRUE
       OR COALESCE((v_again->>'idempotent')::boolean, false) IS NOT TRUE THEN
        RAISE EXCEPTION 're-run was not idempotent: %', v_again;
    END IF;
    SELECT count(*) INTO v_count FROM ledger_entries
     WHERE bet_id = '67000000-0000-4000-8000-000000000010' AND type = 'settlement';
    IF v_count <> 1 THEN
        RAISE EXCEPTION 're-run posted % settlements for the Warriors single', v_count;
    END IF;

    v_conflict := settle_outright_tx(v_event, 'Boston Celtics', false, v_actor);
    IF v_conflict->>'error' <> 'result_already_recorded' THEN
        RAISE EXCEPTION 'a different winner should be refused, got %', v_conflict;
    END IF;
    SELECT grade_result INTO v_grade FROM bets WHERE id = '67000000-0000-4000-8000-000000000010';
    IF v_grade <> 'win' THEN
        RAISE EXCEPTION 'refused call changed the grade to %', v_grade;
    END IF;

    v_game_result := settle_outright_tx(v_game, 'Celtics', false, v_actor);
    IF v_game_result->>'error' <> 'Event is not a future' THEN
        RAISE EXCEPTION 'a game should be refused, got %', v_game_result;
    END IF;

    v_result := settle_outright_tx(v_void_event, NULL, true, v_actor);
    IF COALESCE((v_result->>'success')::boolean, false) IS NOT TRUE THEN
        RAISE EXCEPTION 'void failed: %', v_result;
    END IF;
    SELECT count(*) INTO v_count FROM ledger_entries
     WHERE bet_id = '67000000-0000-4000-8000-000000000040';
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'void single should have no ledger row, got %', v_count;
    END IF;
    SELECT status, grade_result INTO v_status, v_grade
      FROM bets WHERE id = '67000000-0000-4000-8000-000000000040';
    IF v_status <> 'void' OR v_grade IS NOT NULL THEN
        RAISE EXCEPTION 'voided single is % / %', v_status, v_grade;
    END IF;

    v_again := settle_outright_tx(v_void_event, NULL, true, v_actor);
    IF COALESCE((v_again->>'idempotent')::boolean, false) IS NOT TRUE THEN
        RAISE EXCEPTION 'void re-run was not idempotent: %', v_again;
    END IF;
    SELECT count(*) INTO v_count FROM ledger_entries
     WHERE bet_id = '67000000-0000-4000-8000-000000000040';
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'void re-run posted a ledger row';
    END IF;

    v_result := grade_and_settle_bet_tx(
        '67000000-0000-4000-8000-000000000070', 'void', v_actor, 'manual_settle_070');
    IF COALESCE((v_result->>'voided')::boolean, false) IS NOT TRUE THEN
        RAISE EXCEPTION 'manual void failed: %', v_result;
    END IF;
    SELECT status INTO v_status FROM bets WHERE id = '67000000-0000-4000-8000-000000000070';
    IF v_status <> 'void'
       OR (SELECT count(*) FROM ledger_entries WHERE bet_id = '67000000-0000-4000-8000-000000000070') <> 0 THEN
        RAISE EXCEPTION 'manual void wrote a ledger row or status %', v_status;
    END IF;

    v_result := grade_and_settle_bet_tx(
        '67000000-0000-4000-8000-000000000071', 'win', v_actor, 'manual_settle_071');
    IF COALESCE((v_result->>'success')::boolean, false) IS NOT TRUE THEN
        RAISE EXCEPTION 'manual win failed: %', v_result;
    END IF;
    SELECT idempotency_key, count(*) INTO v_key, v_count
      FROM settlement_events
     WHERE bet_id = '67000000-0000-4000-8000-000000000071'
     GROUP BY idempotency_key;
    IF v_count <> 1 OR v_key <> 'manual_settle_67000000-0000-4000-8000-000000000071_v1' THEN
        RAISE EXCEPTION 'manual settle key % count %', v_key, v_count;
    END IF;
    v_conflict := grade_and_settle_bet_tx(
        '67000000-0000-4000-8000-000000000071', 'loss', v_actor, 'manual_settle_071_again');
    IF v_conflict->>'error' <> 'outcome_conflict' THEN
        RAISE EXCEPTION 'regrade should conflict, got %', v_conflict;
    END IF;
    SELECT count(*) INTO v_count FROM ledger_entries
     WHERE bet_id = '67000000-0000-4000-8000-000000000071' AND type = 'settlement';
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'regrade posted % settlement rows', v_count;
    END IF;

    IF (SELECT count(*) FROM ledger_entries
         WHERE bet_id = 'e4df12ed-0000-4000-8000-000000000076' AND type = 'settlement') <> 2 THEN
        RAISE EXCEPTION 'e4df12ed settlements changed';
    END IF;
    IF (SELECT count(*) FROM ledger_entries
         WHERE bet_id = '297c5d53-0000-4000-8000-000000000297' AND type = 'settlement') <> 2 THEN
        RAISE EXCEPTION '297c5d53 settlements changed';
    END IF;
END $$;
