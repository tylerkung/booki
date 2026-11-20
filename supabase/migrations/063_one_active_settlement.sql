-- ============================================================================
-- One active settlement per bet and per parlay ticket
-- Migration: 063_one_active_settlement.sql
--
-- THE BUG
-- -------
-- A pick can be paid twice. refresh_live_scores and the catch-up settler in
-- auto_refresh_games each insert a ledger row of type 'settlement' for the
-- same bet. Nothing in the ledger says that is illegal: there is no unique
-- key on (bet_id, settlement).
--
-- Confirmed on production data from 2026-02-26 (left untouched by this
-- migration — correcting them is a separate decision):
--
--   bet e4df12ed…  76ers ML -124, $5. Paid $8.06 instead of $4.03.
--                  ledger seq 59 and seq 51.
--   bet 297c5d53…  Wolves ML -178, $5. Paid $5.62 instead of $2.81.
--                  ledger seq 174 and seq 67.
--
-- How the window opens: refresh_live_scores updates the bet with
-- grade_details and settled_amount. Those columns do not exist, so PostgREST
-- returns 400 for the whole PATCH. The function ignores that error and
-- inserts the ledger row anyway. The bet stays 'accepted'. About 30 minutes
-- later the catch-up settler grades it and inserts a second settlement.
-- The same split — status update in one request, ledger insert in another —
-- is how a parlay ticket gets paid twice. The live parlay insert also omits
-- bet_id, and the settlement_events insert that follows is wrapped in a
-- try/catch, so the unique (bet_id, settlement_version) key never stops it.
--
-- Two related RPC bugs, fixed in the same functions:
--
--   settle_bet_tx always writes settlement_version = 1. settlement_events
--   has UNIQUE (bet_id, settlement_version), and the version-1 row is
--   immutable, so a legitimate re-settle after override_grade_tx fails.
--
--   override_grade_tx accepts an idempotency key and never reads it. A
--   replay reverses the settlement again. It also re-applies an override
--   when grade_result is already the requested outcome.
--
-- WHY A TRIGGER, NOT A PARTIAL UNIQUE INDEX
-- ------------------------------------------
-- A plain UNIQUE (bet_id) WHERE type = 'settlement' does not build: the two
-- bets above (and any other historical pair) already violate it. This
-- migration must not UPDATE, DELETE, or rewrite those rows to make an index
-- fit. Their hash chain is the audit trail.
--
-- A partial index that skips rows created before this migration, or that
-- skips the two known bet ids, would build. It would also reject the next
-- legitimate settlement after a reversal. A reversal is a NEW row of type
-- 'reversal'; the original settlement row stays type = 'settlement' forever,
-- because prevent_mutation refuses every update of ledger_entries (migration
-- 053 keeps that absolute). An index cannot see "this settlement has a later
-- reversal". Excluding the two known ids would also miss any other pair.
--
-- A BEFORE INSERT trigger can. It counts settlement rows minus reversal rows
-- for the TICKET, not for one leg. A single is a one-bet ticket. A parlay is
-- every leg that shares ticket_id, and the ledger row hangs off whichever
-- leg was used as the anchor — still one row for the ticket. Keying the
-- guard on bet_id would allow one settlement per leg, which is a second
-- payout of the same ticket. settle_bet_tx refuses a parlay leg for that
-- reason; the ticket is paid once, through settle_parlay_tx, with the key
-- auto_settle_parlay_<ticket>_v<version> (v1 on the first auto settlement).
-- One or more active settlements on the ticket → reject the new row. Zero,
-- which is the state after override_grade_tx / reverse_settlement_tx, →
-- allow it. Existing pairs are not inserted, so they do not have to satisfy
-- the rule, and the migration still applies. New writers, including
-- grade_player_props (which still inserts the ledger itself) and a bookie
-- session that hits the ledger_entries INSERT policy, go through the trigger.
--
-- The trigger locks the ticket (advisory lock, then every leg in id order)
-- before it counts, so two concurrent inserts cannot both observe zero.
-- settle_bet_tx and settle_parlay_tx take that same lock before they lock
-- any bet row, and they return the existing ledger row instead of inserting
-- when one is already active. The trigger is what makes a direct insert fail.
-- The RPC is what makes the settlers idempotent.
--
-- This file writes no ledger, bet, or settlement_events rows.
-- Re-running it only replaces functions and recreates the trigger.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Shared lock and count. The count is the definition of "active":
-- settlement rows minus reversal rows on bets that share the ticket.
-- A settlement with a NULL bet_id cannot be tied to a ticket; the live
-- parlay path used to write those. They stay. The duplicate-detection query
-- in scripts/sql/062_duplicate_settlements.sql does not see them; the
-- companion query for bet_id IS NULL is in the PR description.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION settlement_ticket_lock(p_ticket_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF p_ticket_id IS NULL THEN
        RAISE EXCEPTION 'settlement requires a ticket_id'
            USING ERRCODE = '23502';
    END IF;

    -- hashtext is 32 bits. A collision only queues two tickets behind one
    -- lock; the count that follows is still filtered to this ticket.
    PERFORM pg_advisory_xact_lock(
        hashtext('booki-active-settlement:' || p_ticket_id::text)::bigint
    );
END;
$$;

CREATE OR REPLACE FUNCTION active_settlement_count(p_ticket_id UUID)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT (
        COUNT(*) FILTER (WHERE le.type = 'settlement')
        - COUNT(*) FILTER (WHERE le.type = 'reversal')
    )::integer
    FROM ledger_entries le
    JOIN bets b ON b.id = le.bet_id
    WHERE b.ticket_id = p_ticket_id
      AND le.type IN ('settlement', 'reversal');
$$;

-- Closes every leg on the ticket except a void. An early loss closes the
-- legs that have not been played. A void leg keeps status 'void'.
CREATE OR REPLACE FUNCTION mark_ticket_settled(
    p_ticket_id UUID,
    p_now TIMESTAMPTZ
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE bets
       SET status = 'settled',
           updated_at = p_now
     WHERE ticket_id = p_ticket_id
       AND status IS DISTINCT FROM 'settled'
       AND status IS DISTINCT FROM 'void';
END;
$$;

-- Helpers are called from the SECURITY DEFINER RPCs and the trigger, which
-- run as the migration owner. They are not part of the HTTP API.
REVOKE ALL ON FUNCTION settlement_ticket_lock(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION active_settlement_count(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION mark_ticket_settled(uuid, timestamptz) FROM PUBLIC;
DO $$
BEGIN
    EXECUTE format(
        'GRANT EXECUTE ON FUNCTION settlement_ticket_lock(uuid) TO %I',
        current_user
    );
    EXECUTE format(
        'GRANT EXECUTE ON FUNCTION active_settlement_count(uuid) TO %I',
        current_user
    );
    EXECUTE format(
        'GRANT EXECUTE ON FUNCTION mark_ticket_settled(uuid, timestamptz) TO %I',
        current_user
    );
END;
$$;

-- ---------------------------------------------------------------------------
-- The guarantee. Insert-only: it does not look at rows already stored, so
-- the historical pairs do not stop this migration.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION reject_duplicate_active_settlement()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_ticket_id UUID;
    v_active integer;
    v_bet_active integer;
BEGIN
    IF NEW.type IS DISTINCT FROM 'settlement' THEN
        RETURN NEW;
    END IF;

    IF NEW.bet_id IS NULL THEN
        RAISE EXCEPTION
            'settlement ledger entry requires bet_id so it can be tied to one ticket'
            USING ERRCODE = '23502';
    END IF;

    SELECT ticket_id
      INTO v_ticket_id
      FROM bets
     WHERE id = NEW.bet_id;

    IF v_ticket_id IS NULL THEN
        RAISE EXCEPTION 'settlement bet % is not on a ticket', NEW.bet_id
            USING ERRCODE = '23503';
    END IF;

    PERFORM settlement_ticket_lock(v_ticket_id);

    -- Same order as the RPCs: id ascending. Take the advisory lock first.
    PERFORM 1
      FROM bets
     WHERE ticket_id = v_ticket_id
     ORDER BY id
       FOR UPDATE;

    -- Per bet, then per ticket. A parlay ledger row hangs off one leg, so a
    -- bet-only check would still allow a second payout on a different leg.
    SELECT count(*) FILTER (WHERE type = 'settlement')
         - count(*) FILTER (WHERE type = 'reversal')
      INTO v_bet_active
      FROM ledger_entries
     WHERE bet_id = NEW.bet_id
       AND type IN ('settlement', 'reversal');

    v_active := active_settlement_count(v_ticket_id);

    IF v_bet_active >= 1 THEN
        RAISE EXCEPTION 'active settlement already exists for bet %', NEW.bet_id
            USING ERRCODE = '23505';
    END IF;

    IF v_active >= 1 THEN
        RAISE EXCEPTION 'active settlement already exists for ticket %', v_ticket_id
            USING ERRCODE = '23505';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS reject_duplicate_active_settlement ON ledger_entries;
CREATE TRIGGER reject_duplicate_active_settlement
    BEFORE INSERT ON ledger_entries
    FOR EACH ROW
    WHEN (NEW.type = 'settlement')
    EXECUTE FUNCTION reject_duplicate_active_settlement();

COMMENT ON FUNCTION reject_duplicate_active_settlement() IS
    'Rejects a second active settlement for a bet and for a parlay ticket. Active = settlement rows minus reversal rows. Covers every insert, including settleReadyParlays from refresh_live_scores, auto_refresh_games, and grade_player_props. Does not modify existing rows. A reversal brings the count back to zero and a new settlement is allowed.';

-- ---------------------------------------------------------------------------
-- settlement_events today is unique on (bet_id, settlement_version) only.
-- The auto parlay key is auto_settle_parlay_<ticket>_v1, shared by
-- refresh_live_scores, auto_refresh_games, and grade_player_props because
-- all three call settleReadyParlays. A second insert of that key must fail
-- even if the ledger trigger were bypassed.
--
-- NULL keys stay allowed more than once: a unique index does not equate
-- NULLs, and older rows often have no key. This statement does not update
-- or delete any row. If two existing rows share a non-null key, CREATE
-- INDEX fails and no ledger row is changed. Re-run is safe: the objects
-- above are CREATE OR REPLACE or DROP TRIGGER + CREATE, and the index uses
-- IF NOT EXISTS once it has been built.
-- A re-settle after a reversal uses the next version of the key. The v1
-- row is immutable and stays.
-- ---------------------------------------------------------------------------

CREATE UNIQUE INDEX IF NOT EXISTS uq_settlement_events_idempotency_key
    ON settlement_events (idempotency_key)
    WHERE idempotency_key IS NOT NULL;

-- ---------------------------------------------------------------------------
-- settle_bet_tx. Same four arguments as migration 034.
-- If an active settlement already exists, return that ledger row and post
-- nothing. Otherwise version is max(settlement_version) + 1, so a re-settle
-- after an override is version 2, 3, ... rather than a second version 1.
-- Status is accepted (auto-grade just wrote grade_result) or graded (manual).
-- Parlay legs are settled by settle_parlay_tx; calling this on a leg returns
-- the ticket's existing settlement when there is one, and an error otherwise.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION settle_bet_tx(
    p_bet_id UUID,
    p_actor_user_id UUID,
    p_idempotency_key TEXT,
    p_mode TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_ticket_id UUID;
    v_bet RECORD;
    v_active integer;
    v_existing RECORD;
    v_payout DECIMAL(15, 2);
    v_description TEXT;
    v_now TIMESTAMPTZ := NOW();
    v_ledger_entry_id UUID;
    v_settlement_event_id UUID;
    v_version integer;
    v_ledger_json JSONB;
    v_key TEXT;
BEGIN
    IF p_mode IS NULL OR p_mode NOT IN ('manual', 'auto') THEN
        RETURN jsonb_build_object('success', false, 'error', 'Invalid settlement mode');
    END IF;

    SELECT ticket_id
      INTO v_ticket_id
      FROM bets
     WHERE id = p_bet_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'Bet not found');
    END IF;

    PERFORM settlement_ticket_lock(v_ticket_id);

    PERFORM 1
      FROM bets
     WHERE ticket_id = v_ticket_id
     ORDER BY id
       FOR UPDATE;

    SELECT id, bookie_id, player_id, event_id, ticket_id,
           market, side, odds, stake, status, grade_result,
           accepted_at, created_at, updated_at, is_parlay
      INTO v_bet
      FROM bets
     WHERE id = p_bet_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'Bet not found');
    END IF;

    v_active := active_settlement_count(v_ticket_id);

    IF v_active >= 1 THEN
        -- Earliest settlement on the ticket. For a normal retry there is
        -- one. For a historical double payment there are two and this is
        -- the first; nothing new is posted either way.
        SELECT le.id, le.bookie_id, le.player_id, le.bet_id, le.amount,
               le.type, le.description, le.created_at
          INTO v_existing
          FROM ledger_entries le
          JOIN bets b ON b.id = le.bet_id
         WHERE b.ticket_id = v_ticket_id
           AND le.type = 'settlement'
         ORDER BY le.seq ASC
         LIMIT 1;

        IF NOT FOUND THEN
            RAISE EXCEPTION
                'active settlement count for ticket % is % but no settlement row is visible',
                v_ticket_id, v_active;
        END IF;

        SELECT id
          INTO v_settlement_event_id
          FROM settlement_events
         WHERE bet_id = v_existing.bet_id
         ORDER BY settlement_version ASC
         LIMIT 1;

        -- Close the live-score window for a single: the ledger exists and the
        -- status update was the call that failed. A parlay does not close
        -- legs that are still accepted. This writes bets, not the ledger.
        PERFORM mark_ticket_settled(v_ticket_id, v_now);

        v_ledger_json := jsonb_build_object(
            'id', v_existing.id,
            'bookie_id', v_existing.bookie_id,
            'player_id', v_existing.player_id,
            'bet_id', v_existing.bet_id,
            'amount', v_existing.amount,
            'type', v_existing.type,
            'description', v_existing.description,
            'created_at', v_existing.created_at
        );

        RETURN jsonb_build_object(
            'success', true,
            'idempotent', true,
            'bet', jsonb_build_object(
                'id', v_bet.id,
                'bookie_id', v_bet.bookie_id,
                'player_id', v_bet.player_id,
                'event_id', v_bet.event_id,
                'ticket_id', v_bet.ticket_id,
                'market', v_bet.market,
                'side', v_bet.side,
                'odds', v_bet.odds,
                'stake', v_bet.stake,
                'status', 'settled',
                'grade_result', v_bet.grade_result,
                'accepted_at', v_bet.accepted_at,
                'created_at', v_bet.created_at,
                'updated_at', v_now
            ),
            'ledger_entry', v_ledger_json,
            'settlement_event_id', v_settlement_event_id
        );
    END IF;

    IF v_bet.is_parlay THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Parlay legs settle with the ticket via settle_parlay_tx'
        );
    END IF;

    IF v_bet.grade_result IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Bet must be graded before settling');
    END IF;

    IF v_bet.status NOT IN ('graded', 'accepted') THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', format('Bet cannot be settled (current status: %s)', v_bet.status)
        );
    END IF;

    CASE v_bet.grade_result
        WHEN 'win' THEN
            IF v_bet.odds > 0 THEN
                v_payout := -(v_bet.stake * (v_bet.odds / 100.0));
            ELSE
                v_payout := -(v_bet.stake * (100.0 / abs(v_bet.odds)));
            END IF;
            v_description := 'Bet won';
        WHEN 'loss' THEN
            v_payout := v_bet.stake;
            v_description := 'Bet lost';
        WHEN 'push' THEN
            v_payout := 0;
            v_description := 'Bet pushed';
        WHEN 'void' THEN
            v_payout := 0;
            v_description := 'Bet voided';
        ELSE
            v_payout := 0;
            v_description := format('Bet %s', v_bet.grade_result);
    END CASE;

    SELECT COALESCE(MAX(settlement_version), 0) + 1
      INTO v_version
      FROM settlement_events
     WHERE bet_id = p_bet_id;

    -- settlement_events.idempotency_key is unique. Version 1 keeps the
    -- caller's key. A re-settle after a reversal must not reuse it.
    v_key := p_idempotency_key;
    IF v_version > 1 AND v_key IS NOT NULL AND EXISTS (
        SELECT 1 FROM settlement_events WHERE idempotency_key = v_key
    ) THEN
        v_key := v_key || '_v' || v_version::text;
    END IF;

    INSERT INTO ledger_entries (bookie_id, player_id, bet_id, amount, type, description, created_at)
    VALUES (v_bet.bookie_id, v_bet.player_id, p_bet_id, v_payout, 'settlement', v_description, v_now)
    RETURNING id INTO v_ledger_entry_id;

    PERFORM mark_ticket_settled(v_ticket_id, v_now);

    INSERT INTO settlement_events (
        bookie_id, bet_id, settlement_version, mode, actor_user_id,
        idempotency_key, ledger_entry_ids, created_at
    )
    VALUES (
        v_bet.bookie_id, p_bet_id, v_version, p_mode, p_actor_user_id,
        v_key, ARRAY[v_ledger_entry_id], v_now
    )
    RETURNING id INTO v_settlement_event_id;

    INSERT INTO audit_events (
        bookie_id, actor_user_id, entity_type, entity_id, action_type,
        previous_state, new_state, created_at
    )
    VALUES (
        v_bet.bookie_id,
        p_actor_user_id,
        'bet',
        p_bet_id,
        'settle',
        jsonb_build_object('status', v_bet.status, 'grade_result', v_bet.grade_result),
        jsonb_build_object(
            'status', 'settled',
            'grade_result', v_bet.grade_result,
            'settlement_version', v_version
        ),
        v_now
    );

    INSERT INTO audit_events (
        bookie_id, actor_user_id, entity_type, entity_id, action_type,
        previous_state, new_state, created_at
    )
    VALUES (
        v_bet.bookie_id,
        p_actor_user_id,
        'ledger_entry',
        v_ledger_entry_id,
        'create',
        NULL,
        jsonb_build_object(
            'id', v_ledger_entry_id,
            'bookie_id', v_bet.bookie_id,
            'player_id', v_bet.player_id,
            'bet_id', p_bet_id,
            'amount', v_payout,
            'type', 'settlement',
            'description', v_description
        ),
        v_now
    );

    RETURN jsonb_build_object(
        'success', true,
        'idempotent', false,
        'settlement_version', v_version,
        'bet', jsonb_build_object(
            'id', v_bet.id,
            'bookie_id', v_bet.bookie_id,
            'player_id', v_bet.player_id,
            'event_id', v_bet.event_id,
            'ticket_id', v_bet.ticket_id,
            'market', v_bet.market,
            'side', v_bet.side,
            'odds', v_bet.odds,
            'stake', v_bet.stake,
            'status', 'settled',
            'grade_result', v_bet.grade_result,
            'accepted_at', v_bet.accepted_at,
            'created_at', v_bet.created_at,
            'updated_at', v_now
        ),
        'ledger_entry', jsonb_build_object(
            'id', v_ledger_entry_id,
            'bookie_id', v_bet.bookie_id,
            'player_id', v_bet.player_id,
            'bet_id', p_bet_id,
            'amount', v_payout,
            'type', 'settlement',
            'description', v_description,
            'created_at', v_now
        ),
        'settlement_event_id', v_settlement_event_id
    );
END;
$$;

COMMENT ON FUNCTION settle_bet_tx(uuid, uuid, text, text) IS
    'Atomic settlement of one single. Returns the existing active ledger entry and posts nothing when the ticket already has one. Refuses a parlay leg. settlement_version is max+1. v063.';

-- ---------------------------------------------------------------------------
-- settle_parlay_tx. One transaction for the ticket. Locks every leg, and if
-- an active settlement already exists returns it and writes nothing.
-- Otherwise it decides from the locked legs (a loss settles immediately,
-- void and push legs are dropped and the rest repriced), writes one ledger
-- row and one settlement_events row, and closes every leg except voids.
-- p_amount and p_description are ignored: the locked legs are the decision.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION settle_parlay_tx(
    p_ticket_id UUID,
    p_actor_user_id UUID,
    p_idempotency_key TEXT,
    p_mode TEXT,
    p_amount NUMERIC,
    p_description TEXT,
    p_audit_details JSONB DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_anchor UUID;
    v_bookie_id UUID;
    v_player_id UUID;
    v_active integer;
    v_existing RECORD;
    v_amount DECIMAL(15, 2);
    v_stake DECIMAL(15, 2);
    v_decimal NUMERIC;
    v_profit DECIMAL(15, 2);
    v_description TEXT;
    v_outcome TEXT;
    v_loss integer;
    v_open integer;
    v_wins integer;
    v_now TIMESTAMPTZ := NOW();
    v_ledger_entry_id UUID;
    v_settlement_event_id UUID;
    v_version integer;
    v_leg_count integer;
    v_ledger_json JSONB;
    v_key TEXT;
BEGIN
    IF p_ticket_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Missing ticket_id');
    END IF;

    IF p_mode IS NULL OR p_mode NOT IN ('manual', 'auto') THEN
        RETURN jsonb_build_object('success', false, 'error', 'Invalid settlement mode');
    END IF;

    PERFORM settlement_ticket_lock(p_ticket_id);

    PERFORM 1
      FROM bets
     WHERE ticket_id = p_ticket_id
     ORDER BY id
       FOR UPDATE;

    SELECT count(*) INTO v_leg_count FROM bets WHERE ticket_id = p_ticket_id;
    IF v_leg_count = 0 THEN
        RETURN jsonb_build_object('success', false, 'error', 'No bets found for ticket_id');
    END IF;

    SELECT id, bookie_id, player_id, stake
      INTO v_anchor, v_bookie_id, v_player_id, v_stake
      FROM bets
     WHERE ticket_id = p_ticket_id
     ORDER BY id
     LIMIT 1;

    IF EXISTS (
        SELECT 1
          FROM bets
         WHERE ticket_id = p_ticket_id
           AND (bookie_id IS DISTINCT FROM v_bookie_id
                OR player_id IS DISTINCT FROM v_player_id)
    ) THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'All parlay legs must belong to the same organizer and member'
        );
    END IF;

    v_active := active_settlement_count(p_ticket_id);

    IF v_active >= 1 THEN
        SELECT le.id, le.bookie_id, le.player_id, le.bet_id, le.amount,
               le.type, le.description, le.created_at
          INTO v_existing
          FROM ledger_entries le
          JOIN bets b ON b.id = le.bet_id
         WHERE b.ticket_id = p_ticket_id
           AND le.type = 'settlement'
         ORDER BY le.seq ASC
         LIMIT 1;

        IF NOT FOUND THEN
            RAISE EXCEPTION
                'active settlement count for ticket % is % but no settlement row is visible',
                p_ticket_id, v_active;
        END IF;

        SELECT id
          INTO v_settlement_event_id
          FROM settlement_events
         WHERE bet_id = v_existing.bet_id
         ORDER BY settlement_version ASC
         LIMIT 1;

        -- Finish any leg that was still open. Do not turn a void into settled,
        -- and do not write another ledger row.
        PERFORM mark_ticket_settled(p_ticket_id, v_now);

        v_ledger_json := jsonb_build_object(
            'id', v_existing.id,
            'bookie_id', v_existing.bookie_id,
            'player_id', v_existing.player_id,
            'bet_id', v_existing.bet_id,
            'amount', v_existing.amount,
            'type', v_existing.type,
            'description', v_existing.description,
            'created_at', v_existing.created_at
        );

        RETURN jsonb_build_object(
            'success', true,
            'idempotent', true,
            'already_settled', true,
            'action', 'settled',
            'ledger_entry', v_ledger_json,
            'settlement_event_id', v_settlement_event_id,
            'legs_settled', v_leg_count
        );
    END IF;

    -- Same rules as decideParlay, applied to the rows just locked.
    SELECT
        count(*) FILTER (WHERE standing = 'loss'),
        count(*) FILTER (WHERE standing = 'open'),
        count(*) FILTER (WHERE standing = 'win')
      INTO v_loss, v_open, v_wins
      FROM (
        SELECT CASE
                 WHEN status = 'void' OR grade_result = 'void' THEN 'void'
                 WHEN grade_result = 'push' OR status = 'push' THEN 'push'
                 WHEN grade_result = 'loss' THEN 'loss'
                 WHEN grade_result = 'win' THEN 'win'
                 ELSE 'open'
               END AS standing
          FROM bets
         WHERE ticket_id = p_ticket_id
      ) s;

    IF v_loss = 0 AND v_open > 0 THEN
        RETURN jsonb_build_object(
            'success', true,
            'action', 'wait',
            'idempotent', false,
            'already_settled', false,
            'detail', 'legs still open and none have lost'
        );
    END IF;

    IF v_loss = 0 AND v_wins = 0 AND v_open = 0 AND v_leg_count > 0
       AND NOT EXISTS (
           SELECT 1 FROM bets
            WHERE ticket_id = p_ticket_id
              AND (grade_result IS NOT NULL OR status IN ('void', 'graded', 'settled'))
       ) THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Parlay has no graded legs'
        );
    END IF;

    IF v_loss > 0 THEN
        v_outcome := 'loss';
        v_amount := ROUND(v_stake, 2);
        v_description := format('Multi-Pick lost (%s legs)', v_leg_count);
    ELSIF v_wins = 0 THEN
        v_outcome := 'void';
        v_amount := 0;
        v_description := format('Multi-Pick voided (%s legs, stake refunded)', v_leg_count);
    ELSE
        SELECT COALESCE(exp(sum(ln(factor))), 1)
          INTO v_decimal
          FROM (
            SELECT CASE
                     WHEN odds > 0 THEN 1 + odds / 100.0
                     WHEN odds < 0 THEN 1 + 100.0 / abs(odds)
                     ELSE 1
                   END AS factor
              FROM bets
             WHERE ticket_id = p_ticket_id
               AND grade_result = 'win'
               AND status IS DISTINCT FROM 'void'
               AND grade_result IS DISTINCT FROM 'void'
          ) priced;
        v_profit := ROUND(v_stake * v_decimal - v_stake, 2);
        v_amount := ROUND(-v_profit, 2);
        v_outcome := 'win';
        v_description := format('Multi-Pick won (%s of %s legs)', v_wins, v_leg_count);
    END IF;

    SELECT COALESCE(MAX(settlement_version), 0) + 1
      INTO v_version
      FROM settlement_events
     WHERE bet_id = v_anchor;

    -- First auto settlement keeps auto_settle_parlay_<ticket>_v1, which is
    -- the key settleReadyParlays already uses. A re-settle after a reversal
    -- stores the next version instead of writing a second v1 row.
    v_key := NULLIF(btrim(COALESCE(p_idempotency_key, '')), '');
    IF v_key IS NULL THEN
        v_key := format('auto_settle_parlay_%s_v%s', p_ticket_id, v_version);
    ELSIF v_version > 1 AND v_key = format('auto_settle_parlay_%s_v1', p_ticket_id) THEN
        v_key := format('auto_settle_parlay_%s_v%s', p_ticket_id, v_version);
    ELSIF v_version > 1 AND EXISTS (
        SELECT 1 FROM settlement_events WHERE idempotency_key = v_key
    ) THEN
        v_key := v_key || '_v' || v_version::text;
    END IF;

    INSERT INTO ledger_entries (bookie_id, player_id, bet_id, amount, type, description, created_at)
    VALUES (v_bookie_id, v_player_id, v_anchor, v_amount, 'settlement', v_description, v_now)
    RETURNING id INTO v_ledger_entry_id;

    PERFORM mark_ticket_settled(p_ticket_id, v_now);

    INSERT INTO settlement_events (
        bookie_id, bet_id, settlement_version, mode, actor_user_id,
        idempotency_key, ledger_entry_ids, created_at
    )
    VALUES (
        v_bookie_id, v_anchor, v_version, p_mode, p_actor_user_id,
        v_key, ARRAY[v_ledger_entry_id], v_now
    )
    RETURNING id INTO v_settlement_event_id;

    INSERT INTO audit_events (
        bookie_id, actor_user_id, entity_type, entity_id, action_type,
        previous_state, new_state, created_at
    )
    VALUES (
        v_bookie_id,
        p_actor_user_id,
        'bet',
        v_anchor,
        'settle',
        jsonb_build_object('ticket_id', p_ticket_id, 'leg_count', v_leg_count),
        jsonb_build_object(
            'status', 'settled',
            'ticket_id', p_ticket_id,
            'amount', v_amount,
            'description', v_description,
            'ledger_entry_id', v_ledger_entry_id,
            'settlement_version', v_version,
            'legs_settled', v_leg_count
        ) || COALESCE(p_audit_details, '{}'::jsonb),
        v_now
    );

    RETURN jsonb_build_object(
        'success', true,
        'idempotent', false,
        'already_settled', false,
        'action', 'settled',
        'outcome', v_outcome,
        'settlement_version', v_version,
        'legs_settled', v_leg_count,
        'ledger_entry', jsonb_build_object(
            'id', v_ledger_entry_id,
            'bookie_id', v_bookie_id,
            'player_id', v_player_id,
            'bet_id', v_anchor,
            'amount', v_amount,
            'type', 'settlement',
            'description', v_description,
            'created_at', v_now
        ),
        'settlement_event_id', v_settlement_event_id
    );
END;
$$;

COMMENT ON FUNCTION settle_parlay_tx(uuid, uuid, text, text, numeric, text, jsonb) IS
    'One transaction per parlay ticket. Decides from the locked legs, posts one ledger row, and closes every leg except voids. A second call returns the active settlement. v063.';

-- Not granted to anon/authenticated. The edge functions call it as service_role.
-- The migration owner (postgres, in the SQL editor) keeps EXECUTE so the
-- function can be re-checked by hand. REVOKE FROM PUBLIC also removes the
-- owner's default grant, so it is granted back explicitly.
REVOKE ALL ON FUNCTION settle_parlay_tx(uuid, uuid, text, text, numeric, text, jsonb) FROM PUBLIC;
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
        RAISE EXCEPTION 'service_role is missing; refusing to leave settle_parlay_tx with no caller';
    END IF;
    GRANT EXECUTE ON FUNCTION settle_parlay_tx(uuid, uuid, text, text, numeric, text, jsonb) TO service_role;
    EXECUTE format(
        'GRANT EXECUTE ON FUNCTION settle_parlay_tx(uuid, uuid, text, text, numeric, text, jsonb) TO %I',
        current_user
    );
END;
$$;

-- ---------------------------------------------------------------------------
-- override_grade_tx. Same arguments as migration 016.
-- The idempotency key is stored on the override audit row and a replay
-- returns that result. When grade_result is already the requested outcome,
-- the call changes nothing — it does not reverse a settlement to re-write
-- the same grade.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION override_grade_tx(
    p_bet_id UUID,
    p_actor_user_id UUID,
    p_new_outcome TEXT,
    p_reason TEXT,
    p_idempotency_key TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_bet RECORD;
    v_original_entry RECORD;
    v_reversal_amount DECIMAL(15, 2);
    v_reversal_description TEXT;
    v_now TIMESTAMPTZ := NOW();
    v_reversal_entry_id UUID;
    v_settlement_reversed BOOLEAN := false;
    v_previous_grade_result TEXT;
    v_previous_status TEXT;
    v_prior JSONB;
    v_response JSONB;
    v_ticket_id UUID;
BEGIN
    IF p_new_outcome NOT IN ('win', 'loss', 'push', 'void') THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', format('Invalid new_outcome: %s. Must be one of: win, loss, push, void', p_new_outcome)
        );
    END IF;

    SELECT ticket_id
      INTO v_ticket_id
      FROM bets
     WHERE id = p_bet_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'Bet not found');
    END IF;

    -- A reversal and a settlement on this ticket must not interleave.
    PERFORM settlement_ticket_lock(v_ticket_id);

    SELECT id, bookie_id, player_id, event_id, ticket_id,
           market, side, odds, stake, status, grade_result,
           accepted_at, created_at, updated_at
      INTO v_bet
      FROM bets
     WHERE id = p_bet_id
       FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'Bet not found');
    END IF;

    IF p_idempotency_key IS NOT NULL AND btrim(p_idempotency_key) <> '' THEN
        SELECT new_state
          INTO v_prior
          FROM audit_events
         WHERE entity_type = 'bet'
           AND entity_id = p_bet_id
           AND action_type = 'override'
           AND new_state->>'idempotency_key' = p_idempotency_key
         ORDER BY created_at DESC
         LIMIT 1;

        IF FOUND AND v_prior ? 'response' THEN
            RETURN (v_prior->'response') || jsonb_build_object('idempotent', true);
        END IF;
    END IF;

    IF v_bet.grade_result IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Bet has not been graded yet. Only graded bets can have their grade overridden.'
        );
    END IF;

    -- Already the requested grade. Do not reverse, do not write an audit row.
    IF v_bet.grade_result = p_new_outcome THEN
        RETURN jsonb_build_object(
            'success', true,
            'noop', true,
            'idempotent', false,
            'bet', jsonb_build_object(
                'id', v_bet.id,
                'bookie_id', v_bet.bookie_id,
                'player_id', v_bet.player_id,
                'event_id', v_bet.event_id,
                'ticket_id', v_bet.ticket_id,
                'market', v_bet.market,
                'side', v_bet.side,
                'odds', v_bet.odds,
                'stake', v_bet.stake,
                'status', v_bet.status,
                'grade_result', v_bet.grade_result,
                'accepted_at', v_bet.accepted_at,
                'created_at', v_bet.created_at,
                'updated_at', v_bet.updated_at
            ),
            'settlement_reversed', false,
            'reversal_entry', NULL
        );
    END IF;

    v_previous_grade_result := v_bet.grade_result;
    v_previous_status := v_bet.status;

    IF v_bet.status = 'settled' THEN
        SELECT id, amount, type, description
          INTO v_original_entry
          FROM ledger_entries
         WHERE bet_id = p_bet_id
           AND type = 'settlement'
         ORDER BY created_at DESC, seq DESC
         LIMIT 1;

        IF NOT FOUND THEN
            RETURN jsonb_build_object('success', false, 'error', 'Settlement ledger entry not found for this bet');
        END IF;

        v_reversal_amount := -1 * v_original_entry.amount;
        v_reversal_description := format('Settlement reversal for grade override: %s', p_reason);

        INSERT INTO ledger_entries (bookie_id, player_id, bet_id, amount, type, description, created_at)
        VALUES (v_bet.bookie_id, v_bet.player_id, p_bet_id, v_reversal_amount, 'reversal', v_reversal_description, v_now)
        RETURNING id INTO v_reversal_entry_id;

        INSERT INTO audit_events (
            bookie_id, actor_user_id, entity_type, entity_id, action_type,
            previous_state, new_state, created_at
        )
        VALUES (
            v_bet.bookie_id,
            p_actor_user_id,
            'bet',
            p_bet_id,
            'reverse',
            jsonb_build_object('status', 'settled', 'grade_result', v_previous_grade_result),
            jsonb_build_object('status', 'graded', 'grade_result', v_previous_grade_result),
            v_now
        );

        INSERT INTO audit_events (
            bookie_id, actor_user_id, entity_type, entity_id, action_type,
            previous_state, new_state, created_at
        )
        VALUES (
            v_bet.bookie_id,
            p_actor_user_id,
            'ledger_entry',
            v_reversal_entry_id,
            'create',
            NULL,
            jsonb_build_object(
                'id', v_reversal_entry_id,
                'bookie_id', v_bet.bookie_id,
                'player_id', v_bet.player_id,
                'bet_id', p_bet_id,
                'amount', v_reversal_amount,
                'type', 'reversal',
                'description', v_reversal_description
            ),
            v_now
        );

        v_settlement_reversed := true;
    ELSIF v_bet.status <> 'graded' THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', format('Bet cannot have grade overridden (current status: %s). Must be graded or settled.', v_bet.status)
        );
    END IF;

    UPDATE bets
       SET grade_result = p_new_outcome,
           status = 'graded',
           updated_at = v_now
     WHERE id = p_bet_id;

    v_response := jsonb_build_object(
        'success', true,
        'noop', false,
        'idempotent', false,
        'bet', jsonb_build_object(
            'id', v_bet.id,
            'bookie_id', v_bet.bookie_id,
            'player_id', v_bet.player_id,
            'event_id', v_bet.event_id,
            'ticket_id', v_bet.ticket_id,
            'market', v_bet.market,
            'side', v_bet.side,
            'odds', v_bet.odds,
            'stake', v_bet.stake,
            'status', 'graded',
            'grade_result', p_new_outcome,
            'accepted_at', v_bet.accepted_at,
            'created_at', v_bet.created_at,
            'updated_at', v_now
        ),
        'settlement_reversed', v_settlement_reversed,
        'reversal_entry', CASE
            WHEN v_settlement_reversed THEN jsonb_build_object(
                'id', v_reversal_entry_id,
                'bookie_id', v_bet.bookie_id,
                'player_id', v_bet.player_id,
                'bet_id', p_bet_id,
                'amount', v_reversal_amount,
                'type', 'reversal',
                'description', v_reversal_description,
                'created_at', v_now
            )
            ELSE NULL
        END
    );

    INSERT INTO audit_events (
        bookie_id, actor_user_id, entity_type, entity_id, action_type,
        previous_state, new_state, created_at
    )
    VALUES (
        v_bet.bookie_id,
        p_actor_user_id,
        'bet',
        p_bet_id,
        'override',
        jsonb_build_object('status', v_previous_status, 'grade_result', v_previous_grade_result),
        jsonb_build_object(
            'status', 'graded',
            'grade_result', p_new_outcome,
            'idempotency_key', p_idempotency_key,
            'settlement_reversed', v_settlement_reversed,
            'response', v_response
        ),
        v_now
    );

    RETURN v_response;
END;
$$;

COMMENT ON FUNCTION override_grade_tx(uuid, uuid, text, text, text) IS
    'Atomic grade override. Replays of the same idempotency key return the stored result. A grade that already equals the target is a no-op and does not reverse the settlement. v063.';

-- ---------------------------------------------------------------------------
-- The migration applied. It did not write a ledger row; this only checks
-- that the objects exist so a partial run is obvious on re-run.
-- ---------------------------------------------------------------------------

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
          FROM pg_trigger
         WHERE tgname = 'reject_duplicate_active_settlement'
           AND NOT tgisinternal
    ) THEN
        RAISE EXCEPTION 'reject_duplicate_active_settlement trigger is missing';
    END IF;

    IF to_regprocedure('public.settle_bet_tx(uuid,uuid,text,text)') IS NULL THEN
        RAISE EXCEPTION 'settle_bet_tx is missing';
    END IF;

    IF to_regprocedure('public.settle_parlay_tx(uuid,uuid,text,text,numeric,text,jsonb)') IS NULL THEN
        RAISE EXCEPTION 'settle_parlay_tx is missing';
    END IF;

    IF to_regprocedure('public.override_grade_tx(uuid,uuid,text,text,text)') IS NULL THEN
        RAISE EXCEPTION 'override_grade_tx is missing';
    END IF;

    IF to_regprocedure('public.active_settlement_count(uuid)') IS NULL THEN
        RAISE EXCEPTION 'active_settlement_count is missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
         WHERE schemaname = 'public'
           AND indexname = 'uq_settlement_events_idempotency_key'
    ) THEN
        RAISE EXCEPTION 'uq_settlement_events_idempotency_key is missing';
    END IF;
END;
$$;
