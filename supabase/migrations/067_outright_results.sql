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

-- Same comparison the edge-function tests lock in _shared/outright.ts.
-- A trailing American price is not part of the name. A shorter nickname is
-- not a match.

CREATE OR REPLACE FUNCTION normalize_outright_selection(p_value TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT regexp_replace(lower(btrim(coalesce(p_value, ''))), '\s+', ' ', 'g');
$$;

CREATE OR REPLACE FUNCTION outright_side_key(p_value TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT btrim(regexp_replace(
        normalize_outright_selection(p_value),
        '\s+[+-][0-9]+(\.[0-9]+)?$',
        ''
    ));
$$;

CREATE OR REPLACE FUNCTION outright_selection_matches(p_side TEXT, p_winner TEXT)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT outright_side_key(p_side) <> ''
       AND outright_side_key(p_side) = outright_side_key(p_winner);
$$;

CREATE OR REPLACE FUNCTION settle_outright_tx(
    p_event_id UUID,
    p_winning_selection TEXT,
    p_void BOOLEAN,
    p_actor_user_id UUID
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
    v_now TIMESTAMPTZ := NOW();
    v_idempotent BOOLEAN := FALSE;
    v_singles_settled INTEGER := 0;
    v_singles_already INTEGER := 0;
    v_parlays_settled INTEGER := 0;
    v_parlays_waiting INTEGER := 0;
    v_graded INTEGER := 0;
BEGIN
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

    SELECT id, away_team, home_team, status
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
    ELSE
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
    PERFORM 1
      FROM bets
     WHERE lower(event_id) = lower(p_event_id::text)
       AND lower(btrim(coalesce(market, ''))) IN ('outright', 'futures')
       AND status IN ('pending', 'accepted', 'graded', 'readyToGrade')
     ORDER BY id
       FOR UPDATE;

    FOR v_bet IN
        SELECT id, is_parlay, side, status, grade_result, ticket_id
          FROM bets
         WHERE lower(event_id) = lower(p_event_id::text)
           AND lower(btrim(coalesce(market, ''))) IN ('outright', 'futures')
           AND status IN ('pending', 'accepted', 'graded', 'readyToGrade')
         ORDER BY id
    LOOP
        IF v_void THEN
            v_outcome := 'void';
        ELSIF outright_selection_matches(v_bet.side, v_winner) THEN
            v_outcome := 'win';
        ELSE
            v_outcome := 'loss';
        END IF;

        IF v_bet.is_parlay THEN
            -- A void leg stays 'void' so settle_parlay_tx drops it and
            -- reprices the rest. A win or loss is a graded leg.
            UPDATE bets
               SET grade_result = v_outcome,
                   status = CASE WHEN v_outcome = 'void' THEN 'void' ELSE 'graded' END,
                   updated_at = v_now
             WHERE id = v_bet.id;
        ELSE
            -- settle_bet_tx accepts 'graded' or 'accepted' and rejects
            -- status 'void'. The void is the grade_result; the RPC posts 0
            -- and then marks the row settled.
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
           AND (grade_result IS NOT NULL OR status IN ('void', 'graded', 'settled'))
    LOOP
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
        'parlays_settled', v_parlays_settled,
        'parlays_waiting', v_parlays_waiting,
        'picks_graded', v_graded
    );
END;
$$;

COMMENT ON FUNCTION settle_outright_tx(uuid, text, boolean, uuid) IS
    'Records one futures result and settles every open outright pick on that event. Singles go through settle_bet_tx (outright_settle_<bet>_v1). Multis go through settle_parlay_tx (auto_settle_parlay_<ticket>_v1). A repeat with the same winner posts nothing new. A different winner is refused. v067.';

REVOKE ALL ON FUNCTION normalize_outright_selection(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION outright_side_key(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION outright_selection_matches(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION settle_outright_tx(uuid, text, boolean, uuid) FROM PUBLIC;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
        RAISE EXCEPTION 'service_role is missing; refusing to leave settle_outright_tx with no caller';
    END IF;

    GRANT EXECUTE ON FUNCTION settle_outright_tx(uuid, text, boolean, uuid) TO service_role;
    EXECUTE format(
        'GRANT EXECUTE ON FUNCTION normalize_outright_selection(text) TO %I',
        current_user
    );
    EXECUTE format(
        'GRANT EXECUTE ON FUNCTION outright_side_key(text) TO %I',
        current_user
    );
    EXECUTE format(
        'GRANT EXECUTE ON FUNCTION outright_selection_matches(text, text) TO %I',
        current_user
    );
    EXECUTE format(
        'GRANT EXECUTE ON FUNCTION settle_outright_tx(uuid, text, boolean, uuid) TO %I',
        current_user
    );
END $$;
