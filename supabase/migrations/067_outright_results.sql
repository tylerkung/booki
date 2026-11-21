-- ============================================================================
-- One result for a future, then one settlement per pick
-- Migration: 067_outright_results.sql
--
-- THE BUG
-- -------
-- An outright has no score and no winner column. gradeBet leaves it open,
-- and the score jobs skip it. sync_games still marked the event final three
-- hours after start_time, which stopped the odds refresh mid-series. The
-- one open futures pick (Warriors +12000, c2aa18ec) has no market row,
-- because the row it pointed at was deleted. Nothing in this file
-- settles that pick or any other existing row. The owner records the winner
-- after this is applied, through settle_outright_tx.
--
-- WHAT THIS ADDS
-- --------------
-- outright_results: one row per event. The winning selection is the team
-- name, compared to bets.side. void means every pick on the event is a void.
-- There is no dead-heat payout.
--
-- settle_outright_tx grades every open outright pick on that event, in every
-- book, then pays singles through settle_bet_tx (key outright_settle_<bet>_v1)
-- and futures legs inside a multi through settle_parlay_tx (key
-- auto_settle_parlay_<ticket>_v1, the same key the cron uses). Both RPCs are
-- the migration 063 path. A second call with the same winner returns without
-- a second ledger row. A different winner is refused and changes nothing.
--
-- The event becomes final here, not on the clock. Requires settle_bet_tx and
-- settle_parlay_tx (migration 063). This file inserts no bet and no ledger row.
-- Re-running it replaces the functions and does not touch outright_results rows.
-- ============================================================================

CREATE TABLE IF NOT EXISTS outright_results (
    event_id UUID PRIMARY KEY REFERENCES events(id),
    winning_selection TEXT,
    void BOOLEAN NOT NULL DEFAULT FALSE,
    recorded_by UUID,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT outright_results_winner_or_void CHECK (
        (void AND winning_selection IS NULL)
        OR (NOT void AND winning_selection IS NOT NULL AND btrim(winning_selection) <> '')
    )
);

COMMENT ON TABLE outright_results IS
    'One futures result for every book. winning_selection is the team name matched to bets.side. void settles every pick on the event as a void. Organizers cannot write this table.';

ALTER TABLE outright_results ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE outright_results FROM PUBLIC;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
        EXECUTE 'REVOKE ALL ON TABLE outright_results FROM anon';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
        EXECUTE 'REVOKE ALL ON TABLE outright_results FROM authenticated';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
        -- The edge function calls the RPC. It does not need a table grant,
        -- and a grant here would not open the table: RLS is on and there is
        -- no policy. service_role bypasses RLS. The revoke above is what
        -- keeps the anon key from reading every book's result.
        EXECUTE 'GRANT SELECT ON TABLE outright_results TO service_role';
    END IF;
END $$;

-- Same comparison the edge-function tests lock in _shared/outright.ts and
-- outright_match_vectors.json. Accents and punctuation fold. A trailing
-- price in either " +12000" or "(+2000)" form is not part of the name.
-- A shorter nickname is not a match.

CREATE OR REPLACE FUNCTION normalize_outright_selection(p_value TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v TEXT := coalesce(p_value, '');
BEGIN
    -- æ/ß expand to two letters. translate is one character to one character.
    v := regexp_replace(v, '[Ææ]', 'ae', 'g');
    v := regexp_replace(v, 'ß', 'ss', 'g');
    v := lower(translate(
        v,
        'ÁÀÂÄÃÅĀĂĄáàâäãåāăąÉÈÊËĒĔĖĘéèêëēĕėęÍÌÎÏĪĬĮíìîïīĭįÓÒÔÖÕŌŎŐóòôöõōŏőÚÙÛÜŪŬŮŰúùûüūŭůűÝŸýÿÑñÇçČčĆćŠšŽžØøŁłĐđŹź',
        'AAAAAAAAAaaaaaaaaaEEEEEEEEeeeeeeeeIIIIIIIiiiiiiiOOOOOOOOooooooooUUUUUUUUuuuuuuuuYYyyNnCcCcCcSsZzOoLlDdZz'
    ));
    -- A trailing price in parentheses, or a signed price of at least three
    -- digits. "+1" and "-1" stay, so they do not collapse into each other.
    v := regexp_replace(v, '\s*\(\s*[+-][0-9]+(\.[0-9]+)?\s*\)\s*$', '');
    v := regexp_replace(v, '\s+[+-][0-9]{3,}(\.[0-9]+)?\s*$', '');
    v := regexp_replace(v, '([^0-9])\+([0-9])', '\1plus\2', 'g');
    v := regexp_replace(v, '([^0-9])-([0-9])', '\1minus\2', 'g');
    v := regexp_replace(v, '[^a-z0-9]+', ' ', 'g');
    RETURN btrim(regexp_replace(v, '\s+', ' ', 'g'));
END;
$$;

CREATE OR REPLACE FUNCTION outright_side_key(p_value TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT normalize_outright_selection(p_value);
$$;

CREATE OR REPLACE FUNCTION outright_selection_matches(p_side TEXT, p_winner TEXT)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT outright_side_key(p_side) <> ''
       AND outright_side_key(p_side) = outright_side_key(p_winner);
$$;

-- current_user inside a SECURITY DEFINER function is the owner, so it cannot
-- tell anon from postgres. The role GUC is the SET ROLE PostgREST performed
-- and stays visible here. A direct psql session has role 'none'.
DROP FUNCTION IF EXISTS assert_futures_settler();

CREATE OR REPLACE FUNCTION assert_futures_settler(p_function TEXT)
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_role TEXT := btrim(coalesce(current_setting('role', true), ''));
    v_name TEXT := COALESCE(NULLIF(btrim(p_function), ''), 'futures settler');
BEGIN
    IF v_role IN ('', 'none') THEN
        IF session_user IN ('postgres', 'service_role') THEN
            RETURN;
        END IF;
    ELSIF v_role IN ('postgres', 'service_role') THEN
        RETURN;
    END IF;

    RAISE EXCEPTION '% is restricted to service_role', v_name
        USING ERRCODE = '42501';
END;
$$;

DROP FUNCTION IF EXISTS settle_outright_tx(uuid, text, boolean, uuid);

CREATE OR REPLACE FUNCTION settle_outright_tx(
    p_event_id UUID,
    p_winning_selection TEXT,
    p_void BOOLEAN,
    p_actor_user_id UUID,
    p_force BOOLEAN DEFAULT FALSE,
    p_dry_run BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_event RECORD;
    v_existing RECORD;
    v_bet RECORD;
    v_ticket UUID;
    v_settle JSONB;
    v_outcome TEXT;
    v_winner TEXT;
    v_void BOOLEAN;
    v_force BOOLEAN := COALESCE(p_force, FALSE);
    v_dry BOOLEAN := COALESCE(p_dry_run, FALSE);
    v_now TIMESTAMPTZ := NOW();
    v_idempotent BOOLEAN := FALSE;
    v_known BOOLEAN := FALSE;
    v_singles_settled INTEGER := 0;
    v_singles_already INTEGER := 0;
    v_voided INTEGER := 0;
    v_parlays_settled INTEGER := 0;
    v_parlays_waiting INTEGER := 0;
    v_graded INTEGER := 0;
    v_wins INTEGER := 0;
    v_losses INTEGER := 0;
    v_by_side JSONB := '[]'::jsonb;
    v_unmatched JSONB := '[]'::jsonb;
BEGIN
    PERFORM assert_futures_settler('settle_outright_tx');

    v_void := COALESCE(p_void, FALSE);
    v_winner := NULLIF(btrim(COALESCE(p_winning_selection, '')), '');

    IF p_event_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Missing event_id');
    END IF;

    IF v_void AND v_winner IS NOT NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'A voided future has no winner');
    END IF;

    IF NOT v_void AND v_winner IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'A winning selection is required');
    END IF;

    IF v_dry THEN
        SELECT id, away_team, home_team, status
          INTO v_event
          FROM events
         WHERE id = p_event_id;
    ELSE
        SELECT id, away_team, home_team, status
          INTO v_event
          FROM events
         WHERE id = p_event_id
         FOR UPDATE;
    END IF;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'Event not found');
    END IF;

    IF v_event.away_team IS DISTINCT FROM 'Outright' THEN
        RETURN jsonb_build_object('success', false, 'error', 'Event is not a future');
    END IF;

    SELECT event_id, winning_selection, void, recorded_by, recorded_at
      INTO v_existing
      FROM outright_results
     WHERE event_id = p_event_id
     FOR UPDATE;

    IF FOUND THEN
        IF v_existing.void IS DISTINCT FROM v_void
           OR outright_side_key(v_existing.winning_selection)
              IS DISTINCT FROM outright_side_key(v_winner)
        THEN
            RETURN jsonb_build_object(
                'success', false,
                'error', 'result_already_recorded',
                'winning_selection', v_existing.winning_selection,
                'void', v_existing.void
            );
        END IF;
        v_idempotent := TRUE;
    ELSIF NOT v_void AND NOT v_force THEN
        SELECT EXISTS (
            SELECT 1
              FROM bets
             WHERE lower(event_id) = lower(p_event_id::text)
               AND lower(btrim(coalesce(market, ''))) IN ('outright', 'futures')
               AND outright_selection_matches(side, v_winner)
            UNION ALL
            SELECT 1
              FROM markets
             WHERE lower(event_id::text) = lower(p_event_id::text)
               AND lower(coalesce(type, '')) = 'outright'
               AND outright_selection_matches(side_a, v_winner)
        ) INTO v_known;

        IF NOT v_known THEN
            RETURN jsonb_build_object(
                'success', false,
                'error', 'unknown_winner',
                'winning_selection', v_winner
            );
        END IF;
    END IF;

    SELECT
        COALESCE(sum(n) FILTER (WHERE outcome = 'win'), 0),
        COALESCE(sum(n) FILTER (WHERE outcome = 'loss'), 0),
        COALESCE(jsonb_agg(jsonb_build_object(
            'side', side, 'count', n, 'outcome', outcome
        ) ORDER BY side), '[]'::jsonb)
      INTO v_wins, v_losses, v_by_side
      FROM (
        SELECT side,
               count(*) AS n,
               CASE
                   WHEN v_void THEN 'void'
                   WHEN outright_selection_matches(side, v_winner) THEN 'win'
                   ELSE 'loss'
               END AS outcome
          FROM bets
         WHERE lower(event_id) = lower(p_event_id::text)
           AND lower(btrim(coalesce(market, ''))) IN ('outright', 'futures')
           AND status = 'accepted'
         GROUP BY side
      ) counted;

    SELECT COALESCE(jsonb_agg(side ORDER BY side), '[]'::jsonb)
      INTO v_unmatched
      FROM (
        SELECT DISTINCT side
          FROM bets
         WHERE lower(event_id) = lower(p_event_id::text)
           AND lower(btrim(coalesce(market, ''))) IN ('outright', 'futures')
           AND status = 'accepted'
           AND NOT v_void
           AND NOT outright_selection_matches(side, v_winner)
      ) unmatched;

    IF v_dry THEN
        RETURN jsonb_build_object(
            'success', true,
            'dry_run', true,
            'idempotent', v_idempotent,
            'event_id', p_event_id,
            'void', v_void,
            'winning_selection', CASE WHEN v_void THEN NULL ELSE v_winner END,
            'wins', v_wins,
            'losses', CASE WHEN v_void THEN 0 ELSE v_losses END,
            'by_side', v_by_side,
            'unmatched_sides', v_unmatched
        );
    END IF;

    IF NOT v_idempotent THEN
        INSERT INTO outright_results (event_id, winning_selection, void, recorded_by, recorded_at)
        VALUES (
            p_event_id,
            CASE WHEN v_void THEN NULL ELSE v_winner END,
            v_void,
            p_actor_user_id,
            v_now
        );
    END IF;

    -- Final means the result is recorded. The clock does not do this.
    UPDATE events
       SET status = 'final',
           updated_at = v_now
     WHERE id = p_event_id
       AND status IS DISTINCT FROM 'final';

    -- Lock the open picks in id order before grading any of them.
    -- The selection is bets.side. The market row may already have been
    -- deleted, so this function does not look one up.
    -- Accepted only. A pending pick was never taken; paying it is a loss
    -- the member did not agree to.
    PERFORM 1
      FROM bets
     WHERE lower(event_id) = lower(p_event_id::text)
       AND lower(btrim(coalesce(market, ''))) IN ('outright', 'futures')
       AND status = 'accepted'
     ORDER BY id
       FOR UPDATE;

    FOR v_bet IN
        SELECT id, is_parlay, side, status, grade_result, ticket_id
          FROM bets
         WHERE lower(event_id) = lower(p_event_id::text)
           AND lower(btrim(coalesce(market, ''))) IN ('outright', 'futures')
           AND status = 'accepted'
         ORDER BY id
    LOOP
        IF v_void THEN
            v_outcome := 'void';
        ELSIF outright_selection_matches(v_bet.side, v_winner) THEN
            v_outcome := 'win';
        ELSE
            v_outcome := 'loss';
        END IF;

        IF v_outcome = 'void' AND NOT COALESCE(v_bet.is_parlay, FALSE) THEN
            -- Same convention as a manual void: status void, no ledger row.
            UPDATE bets
               SET grade_result = NULL,
                   status = 'void',
                   updated_at = v_now
             WHERE id = v_bet.id;
            v_voided := v_voided + 1;
        ELSIF COALESCE(v_bet.is_parlay, FALSE) THEN
            -- A void leg stays 'void' so settle_parlay_tx drops it and
            -- reprices the rest. A win or loss is a graded leg.
            UPDATE bets
               SET grade_result = v_outcome,
                   status = CASE WHEN v_outcome = 'void' THEN 'void' ELSE 'graded' END,
                   updated_at = v_now
             WHERE id = v_bet.id;
        ELSE
            UPDATE bets
               SET grade_result = v_outcome,
                   status = 'graded',
                   updated_at = v_now
             WHERE id = v_bet.id;

            v_settle := settle_bet_tx(
                v_bet.id,
                p_actor_user_id,
                format('outright_settle_%s_v1', v_bet.id),
                'manual'
            );

            IF COALESCE((v_settle->>'success')::boolean, FALSE) IS NOT TRUE THEN
                RAISE EXCEPTION 'settle_bet_tx failed for %: %', v_bet.id, v_settle->>'error';
            END IF;

            IF COALESCE((v_settle->>'idempotent')::boolean, FALSE) THEN
                v_singles_already := v_singles_already + 1;
            ELSE
                v_singles_settled := v_singles_settled + 1;
            END IF;
        END IF;

        v_graded := v_graded + 1;
    END LOOP;

    -- Every ticket that has a futures leg on this event, including a leg
    -- that was graded on a previous run and is now void or settled. The
    -- cron key makes a later auto-settle a no-op. A ticket with an open
    -- other leg and no loss returns action 'wait' and posts nothing.
    FOR v_ticket IN
        SELECT DISTINCT ticket_id
          FROM bets
         WHERE lower(event_id) = lower(p_event_id::text)
           AND COALESCE(is_parlay, FALSE)
           AND lower(btrim(coalesce(market, ''))) IN ('outright', 'futures')
           AND status IN ('void', 'graded', 'settled')
    LOOP
        -- A pending leg on the ticket must stay pending. settle_parlay_tx
        -- closes every non-void leg when one leg has lost.
        IF EXISTS (
            SELECT 1 FROM bets
             WHERE ticket_id = v_ticket
               AND status = 'pending'
        ) THEN
            v_parlays_waiting := v_parlays_waiting + 1;
            CONTINUE;
        END IF;

        v_settle := settle_parlay_tx(
            v_ticket,
            p_actor_user_id,
            format('auto_settle_parlay_%s_v1', v_ticket),
            'manual',
            NULL,
            NULL,
            jsonb_build_object('source', 'settle_outright')
        );

        IF COALESCE((v_settle->>'success')::boolean, FALSE) IS NOT TRUE THEN
            RAISE EXCEPTION 'settle_parlay_tx failed for %: %', v_ticket, v_settle->>'error';
        END IF;

        IF v_settle->>'action' = 'wait' THEN
            v_parlays_waiting := v_parlays_waiting + 1;
        ELSIF v_settle->>'action' = 'settled'
              AND COALESCE((v_settle->>'idempotent')::boolean, FALSE) IS NOT TRUE
              AND COALESCE((v_settle->>'already_settled')::boolean, FALSE) IS NOT TRUE
        THEN
            v_parlays_settled := v_parlays_settled + 1;
        END IF;
    END LOOP;

    RETURN jsonb_build_object(
        'success', true,
        'idempotent', v_idempotent,
        'event_id', p_event_id,
        'void', v_void,
        'winning_selection', CASE WHEN v_void THEN NULL ELSE v_winner END,
        'singles_settled', v_singles_settled,
        'singles_already_settled', v_singles_already,
        'singles_voided', v_voided,
        'parlays_settled', v_parlays_settled,
        'parlays_waiting', v_parlays_waiting,
        'picks_graded', v_graded,
        'wins', v_wins,
        'losses', CASE WHEN v_void THEN 0 ELSE v_losses END,
        'by_side', v_by_side,
        'unmatched_sides', v_unmatched
    );
EXCEPTION
    WHEN deadlock_detected THEN
        RETURN jsonb_build_object('success', false, 'error', 'try_again');
END;
$$;

COMMENT ON FUNCTION settle_outright_tx(uuid, text, boolean, uuid, boolean, boolean) IS
    'Records one futures result and settles every accepted outright pick on that event. Pending picks are left alone. A void single becomes status void with no ledger row. Singles otherwise go through settle_bet_tx. Multis go through settle_parlay_tx. p_dry_run writes nothing. p_force allows a winner that matches no known selection. A repeat with the same winner posts nothing new. v067.';

-- One transaction for a manual single: the grade and the ledger row commit
-- together, or neither does. A void stays status void and writes no ledger
-- row, which is the convention grade_bet used before settlement was added.
CREATE OR REPLACE FUNCTION grade_and_settle_bet_tx(
    p_bet_id UUID,
    p_outcome TEXT,
    p_actor_user_id UUID,
    p_idempotency_key TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_bet RECORD;
    v_settle JSONB;
    v_now TIMESTAMPTZ := NOW();
    v_key TEXT;
BEGIN
    PERFORM assert_futures_settler('grade_and_settle_bet_tx');

    IF p_outcome IS NULL OR p_outcome NOT IN ('win', 'loss', 'push', 'void') THEN
        RETURN jsonb_build_object('success', false, 'error', 'Invalid outcome');
    END IF;

    SELECT id, bookie_id, player_id, event_id, ticket_id, market, side, odds,
           stake, status, grade_result, is_parlay, accepted_at, created_at
      INTO v_bet
      FROM bets
     WHERE id = p_bet_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'Bet not found');
    END IF;

    IF COALESCE(v_bet.is_parlay, FALSE) THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Parlay legs settle with the ticket via settle_parlay_tx'
        );
    END IF;

    IF lower(btrim(coalesce(v_bet.market, ''))) IN ('outright', 'futures') THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Futures are settled by settle_outright_tx'
        );
    END IF;

    IF v_bet.status = 'settled' THEN
        IF v_bet.grade_result IS DISTINCT FROM p_outcome THEN
            RETURN jsonb_build_object(
                'success', false,
                'error', 'outcome_conflict',
                'status', v_bet.status,
                'grade_result', v_bet.grade_result
            );
        END IF;
        RETURN jsonb_build_object(
            'success', true,
            'idempotent', true,
            'settled', true,
            'bet', to_jsonb(v_bet)
        );
    END IF;

    IF v_bet.status = 'void' THEN
        IF p_outcome IS DISTINCT FROM 'void' THEN
            RETURN jsonb_build_object(
                'success', false,
                'error', 'outcome_conflict',
                'status', v_bet.status,
                'grade_result', v_bet.grade_result
            );
        END IF;
        RETURN jsonb_build_object(
            'success', true,
            'idempotent', true,
            'settled', false,
            'voided', true,
            'bet', to_jsonb(v_bet)
        );
    END IF;

    IF v_bet.status = 'graded'
       AND v_bet.grade_result IS NOT NULL
       AND v_bet.grade_result IS DISTINCT FROM p_outcome THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'outcome_conflict',
            'status', v_bet.status,
            'grade_result', v_bet.grade_result
        );
    END IF;

    IF v_bet.status NOT IN ('accepted', 'graded') THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', format('Bet cannot be graded (current status: %s)', v_bet.status)
        );
    END IF;

    IF p_outcome = 'void' THEN
        UPDATE bets
           SET status = 'void',
               grade_result = NULL,
               updated_at = v_now
         WHERE id = p_bet_id;

        INSERT INTO audit_events (
            bookie_id, actor_user_id, entity_type, entity_id, action_type,
            previous_state, new_state, created_at
        ) VALUES (
            v_bet.bookie_id, p_actor_user_id, 'bet', p_bet_id, 'grade',
            jsonb_build_object('status', v_bet.status, 'grade_result', v_bet.grade_result),
            jsonb_build_object('status', 'void', 'grade_result', NULL),
            v_now
        );

        RETURN jsonb_build_object(
            'success', true,
            'idempotent', false,
            'settled', false,
            'voided', true,
            'bet', jsonb_build_object(
                'id', v_bet.id,
                'status', 'void',
                'grade_result', NULL,
                'bookie_id', v_bet.bookie_id,
                'player_id', v_bet.player_id,
                'event_id', v_bet.event_id,
                'ticket_id', v_bet.ticket_id,
                'market', v_bet.market,
                'side', v_bet.side,
                'odds', v_bet.odds,
                'stake', v_bet.stake
            )
        );
    END IF;

    UPDATE bets
       SET grade_result = p_outcome,
           status = 'graded',
           updated_at = v_now
     WHERE id = p_bet_id;

    INSERT INTO audit_events (
        bookie_id, actor_user_id, entity_type, entity_id, action_type,
        previous_state, new_state, created_at
    ) VALUES (
        v_bet.bookie_id, p_actor_user_id, 'bet', p_bet_id, 'grade',
        jsonb_build_object('status', v_bet.status, 'grade_result', v_bet.grade_result),
        jsonb_build_object('status', 'graded', 'grade_result', p_outcome),
        v_now
    );

    v_key := NULLIF(btrim(COALESCE(p_idempotency_key, '')), '');
    IF v_key IS NULL THEN
        v_key := format('manual_settle_%s_v1', p_bet_id);
    END IF;
    v_settle := settle_bet_tx(p_bet_id, p_actor_user_id, v_key, 'manual');

    IF COALESCE((v_settle->>'success')::boolean, FALSE) IS NOT TRUE THEN
        RAISE EXCEPTION 'settle_bet_tx failed for %: %', p_bet_id, v_settle->>'error';
    END IF;

    RETURN v_settle || jsonb_build_object(
        'settled', true,
        'voided', false,
        'idempotency_key', v_key
    );
EXCEPTION
    WHEN deadlock_detected THEN
        RETURN jsonb_build_object('success', false, 'error', 'try_again');
END;
$$;

COMMENT ON FUNCTION grade_and_settle_bet_tx(uuid, text, uuid, text) IS
    'Grades one single and settles it in the same transaction through settle_bet_tx. Uses p_idempotency_key when it is set, otherwise manual_settle_<bet>_v1. A void is status void with no ledger row. A different outcome on an already settled pick returns outcome_conflict and writes nothing. A deadlock returns try_again. v067.';

-- Undo one recorded futures result for every book. One transaction: reverse
-- each active settlement (singles and multi tickets), put this event's
-- futures picks back to accepted, restore the other legs of a multi, delete
-- the result row. A second call finds nothing to undo.
CREATE OR REPLACE FUNCTION reverse_outright_tx(
    p_event_id UUID,
    p_reason TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_event RECORD;
    v_bet RECORD;
    v_ticket UUID;
    v_entry RECORD;
    v_now TIMESTAMPTZ := NOW();
    v_reason TEXT := NULLIF(btrim(COALESCE(p_reason, '')), '');
    v_had_result BOOLEAN := FALSE;
    v_reversed INTEGER := 0;
    v_reopened INTEGER := 0;
    v_moved INTEGER := 0;
BEGIN
    PERFORM assert_futures_settler('reverse_outright_tx');

    IF p_event_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Missing event_id');
    END IF;
    IF v_reason IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'A reason is required');
    END IF;

    SELECT id, away_team, status
      INTO v_event
      FROM events
     WHERE id = p_event_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'Event not found');
    END IF;
    IF v_event.away_team IS DISTINCT FROM 'Outright' THEN
        RETURN jsonb_build_object('success', false, 'error', 'Event is not a future');
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM outright_results WHERE event_id = p_event_id
    ) INTO v_had_result;

    PERFORM 1
      FROM bets
     WHERE lower(event_id) = lower(p_event_id::text)
       AND lower(btrim(coalesce(market, ''))) IN ('outright', 'futures')
     ORDER BY id
       FOR UPDATE;

    FOR v_ticket IN
        SELECT DISTINCT ticket_id
          FROM bets
         WHERE lower(event_id) = lower(p_event_id::text)
           AND COALESCE(is_parlay, FALSE)
           AND lower(btrim(coalesce(market, ''))) IN ('outright', 'futures')
           AND status IN ('settled', 'graded', 'void')
    LOOP
        PERFORM 1
          FROM bets
         WHERE ticket_id = v_ticket
         ORDER BY id
           FOR UPDATE;

        WHILE active_settlement_count(v_ticket) >= 1 LOOP
            SELECT id, bookie_id, player_id, bet_id, amount
              INTO v_entry
              FROM ledger_entries le
             WHERE le.type = 'settlement'
               AND le.bet_id IN (SELECT id FROM bets WHERE ticket_id = v_ticket)
               AND NOT EXISTS (
                   SELECT 1 FROM ledger_entries r
                    WHERE r.bet_id = le.bet_id
                      AND r.type = 'reversal'
                      AND r.seq > le.seq
               )
             ORDER BY le.seq DESC
             LIMIT 1;

            IF NOT FOUND THEN
                EXIT;
            END IF;

            INSERT INTO ledger_entries (
                bookie_id, player_id, bet_id, amount, type, description, created_at
            ) VALUES (
                v_entry.bookie_id, v_entry.player_id, v_entry.bet_id,
                -v_entry.amount, 'reversal',
                format('Futures reversal: %s', v_reason), v_now
            );
            v_reversed := v_reversed + 1;
        END LOOP;

        UPDATE bets
           SET status = 'accepted',
               grade_result = NULL,
               updated_at = v_now
         WHERE ticket_id = v_ticket
           AND lower(event_id) = lower(p_event_id::text)
           AND lower(btrim(coalesce(market, ''))) IN ('outright', 'futures')
           AND status IN ('settled', 'graded', 'void');
        GET DIAGNOSTICS v_moved = ROW_COUNT;
        v_reopened := v_reopened + v_moved;

        -- A leg that already had its own grade goes back to graded so the
        -- multi can be repriced. A leg closed only because this future lost
        -- goes back to accepted.
        UPDATE bets
           SET status = CASE WHEN grade_result IS NULL THEN 'accepted' ELSE 'graded' END,
               updated_at = v_now
         WHERE ticket_id = v_ticket
           AND lower(coalesce(event_id, '')) IS DISTINCT FROM lower(p_event_id::text)
           AND status = 'settled';
    END LOOP;

    FOR v_bet IN
        SELECT id, bookie_id, player_id, ticket_id, status
          FROM bets
         WHERE lower(event_id) = lower(p_event_id::text)
           AND lower(btrim(coalesce(market, ''))) IN ('outright', 'futures')
           AND COALESCE(is_parlay, FALSE) = FALSE
           AND status IN ('settled', 'graded', 'void')
         ORDER BY id
    LOOP
        WHILE active_settlement_count(v_bet.ticket_id) >= 1 LOOP
            SELECT id, bookie_id, player_id, bet_id, amount
              INTO v_entry
              FROM ledger_entries le
             WHERE le.bet_id = v_bet.id
               AND le.type = 'settlement'
               AND NOT EXISTS (
                   SELECT 1 FROM ledger_entries r
                    WHERE r.bet_id = le.bet_id
                      AND r.type = 'reversal'
                      AND r.seq > le.seq
               )
             ORDER BY le.seq DESC
             LIMIT 1;

            IF NOT FOUND THEN
                EXIT;
            END IF;

            INSERT INTO ledger_entries (
                bookie_id, player_id, bet_id, amount, type, description, created_at
            ) VALUES (
                v_entry.bookie_id, v_entry.player_id, v_entry.bet_id,
                -v_entry.amount, 'reversal',
                format('Futures reversal: %s', v_reason), v_now
            );
            v_reversed := v_reversed + 1;
        END LOOP;

        UPDATE bets
           SET status = 'accepted',
               grade_result = NULL,
               updated_at = v_now
         WHERE id = v_bet.id;
        v_reopened := v_reopened + 1;
    END LOOP;

    DELETE FROM outright_results WHERE event_id = p_event_id;

    IF v_event.status = 'final' AND v_had_result THEN
        UPDATE events
           SET status = 'scheduled',
               updated_at = v_now
         WHERE id = p_event_id;
    END IF;

    IF NOT v_had_result AND v_reversed = 0 AND v_reopened = 0 THEN
        RETURN jsonb_build_object(
            'success', true,
            'idempotent', true,
            'event_id', p_event_id,
            'reversed', 0,
            'reopened', 0
        );
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'idempotent', false,
        'event_id', p_event_id,
        'reversed', v_reversed,
        'reopened', v_reopened
    );
EXCEPTION
    WHEN deadlock_detected THEN
        RETURN jsonb_build_object('success', false, 'error', 'try_again');
END;
$$;

COMMENT ON FUNCTION reverse_outright_tx(uuid, text) IS
    'Undoes one futures result for every book. Reverses active settlements, including a multi that was settled or is waiting, returns this event''s futures picks to accepted, and deletes the outright_results row. A second call changes nothing. service_role only. v067.';

REVOKE ALL ON FUNCTION normalize_outright_selection(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION outright_side_key(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION outright_selection_matches(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION assert_futures_settler(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION settle_outright_tx(uuid, text, boolean, uuid, boolean, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION grade_and_settle_bet_tx(uuid, text, uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION reverse_outright_tx(uuid, text) FROM PUBLIC;

-- Default privileges on this database grant EXECUTE to anon and authenticated
-- by name. REVOKE FROM PUBLIC does not remove those. Name them.
DO $$
DECLARE
    v_signature TEXT;
    v_signatures TEXT[] := ARRAY[
        'normalize_outright_selection(text)',
        'outright_side_key(text)',
        'outright_selection_matches(text, text)',
        'assert_futures_settler(text)',
        'settle_outright_tx(uuid, text, boolean, uuid, boolean, boolean)',
        'grade_and_settle_bet_tx(uuid, text, uuid, text)',
        'reverse_outright_tx(uuid, text)'
    ];
    v_role TEXT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
        RAISE EXCEPTION 'service_role is missing; refusing to leave settle_outright_tx with no caller';
    END IF;

    FOREACH v_signature IN ARRAY v_signatures LOOP
        EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC', v_signature);
        FOREACH v_role IN ARRAY ARRAY['anon', 'authenticated'] LOOP
            IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = v_role) THEN
                EXECUTE format('REVOKE ALL ON FUNCTION %s FROM %I', v_signature, v_role);
            END IF;
        END LOOP;
        EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO %I', v_signature, current_user);
    END LOOP;

    GRANT EXECUTE ON FUNCTION settle_outright_tx(uuid, text, boolean, uuid, boolean, boolean) TO service_role;
    GRANT EXECUTE ON FUNCTION grade_and_settle_bet_tx(uuid, text, uuid, text) TO service_role;
    GRANT EXECUTE ON FUNCTION reverse_outright_tx(uuid, text) TO service_role;
END $$;
