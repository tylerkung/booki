-- ============================================================================
-- Migration 034: Fix settle_bet_tx audit_events column/value arity mismatch
-- ============================================================================
--
-- BUG
-- ---
-- Both `INSERT INTO audit_events` statements inside `settle_bet_tx`
-- (migration 015) declare eight target columns:
--
--     (bookie_id, actor_user_id, entity_type, entity_id,
--      action_type, previous_state, new_state, created_at)
--
-- but supply only seven expressions -- `created_at` has no corresponding
-- value. Postgres rejects this at function-execution time with:
--
--     42601: INSERT has more target columns than expressions
--
-- Because the audit inserts are step 6 of an atomic settlement, the whole
-- transaction rolls back. Settlement therefore fails for EVERY bet: the bet
-- is never marked settled, no ledger entry is written, and the member's
-- balance never moves.
--
-- Surfaced by the stress suite (tests/suites/06-settlement.js and
-- 11-concurrent-settle.js). Verified as the only arity mismatch across all
-- 31 prior migrations.
--
-- FIX
-- ---
-- Supply `v_now` as the eighth expression in both statements, rather than
-- dropping `created_at` and letting it default to NOW(). The function already
-- stamps the ledger entry and the settlement_events row with `v_now`, so
-- using it here keeps every row written by a single settlement on one
-- consistent timestamp -- which the audit trail and the ledger hash chain
-- both depend on for correct ordering.
--
-- No schema change. This is a CREATE OR REPLACE of the function body only;
-- migration 015 is left untouched as applied history.
-- ============================================================================

CREATE OR REPLACE FUNCTION settle_bet_tx(
    p_bet_id UUID,
    p_actor_user_id UUID,
    p_idempotency_key TEXT,
    p_mode TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_bet RECORD;
    v_payout DECIMAL(15, 2);
    v_description TEXT;
    v_now TIMESTAMPTZ := NOW();
    v_ledger_entry_id UUID;
    v_settlement_event_id UUID;
BEGIN
    -- ----------------------------------------------------------------
    -- 1. Fetch and validate the bet (lock row for update)
    -- ----------------------------------------------------------------
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

    IF v_bet.grade_result IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Bet must be graded before settling');
    END IF;

    IF v_bet.status = 'settled' THEN
        RETURN jsonb_build_object('success', false, 'error', 'Bet has already been settled');
    END IF;

    IF v_bet.status <> 'graded' THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', format('Bet cannot be settled (current status: %s)', v_bet.status)
        );
    END IF;

    -- ----------------------------------------------------------------
    -- 2. Calculate payout (matches TypeScript settle_bet exactly)
    -- ----------------------------------------------------------------
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

    -- ----------------------------------------------------------------
    -- 3. Update bet status to 'settled'
    -- ----------------------------------------------------------------
    -- Temporarily disable immutability on dependent tables for this tx
    -- (bets table doesn't have immutability trigger, so this is fine)
    UPDATE bets
       SET status = 'settled',
           updated_at = v_now
     WHERE id = p_bet_id;

    -- ----------------------------------------------------------------
    -- 4. Insert ledger entry
    -- ----------------------------------------------------------------
    INSERT INTO ledger_entries (bookie_id, player_id, bet_id, amount, type, description, created_at)
    VALUES (v_bet.bookie_id, v_bet.player_id, p_bet_id, v_payout, 'settlement', v_description, v_now)
    RETURNING id INTO v_ledger_entry_id;

    -- ----------------------------------------------------------------
    -- 5. Insert settlement_events row
    -- ----------------------------------------------------------------
    INSERT INTO settlement_events (bookie_id, bet_id, settlement_version, mode, actor_user_id, idempotency_key, ledger_entry_ids, created_at)
    VALUES (v_bet.bookie_id, p_bet_id, 1, p_mode, p_actor_user_id, p_idempotency_key, ARRAY[v_ledger_entry_id], v_now)
    RETURNING id INTO v_settlement_event_id;

    -- ----------------------------------------------------------------
    -- 6. Insert audit events (bet settle + ledger create)
    -- ----------------------------------------------------------------
    INSERT INTO audit_events (bookie_id, actor_user_id, entity_type, entity_id, action_type, previous_state, new_state, created_at)
    VALUES (
        v_bet.bookie_id,
        p_actor_user_id,
        'bet',
        p_bet_id,
        'settle',
        jsonb_build_object('status', 'graded', 'grade_result', v_bet.grade_result),
        jsonb_build_object('status', 'settled', 'grade_result', v_bet.grade_result),
        v_now
    );

    INSERT INTO audit_events (bookie_id, actor_user_id, entity_type, entity_id, action_type, previous_state, new_state, created_at)
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

    -- ----------------------------------------------------------------
    -- 7. Return success with bet + ledger entry data
    -- ----------------------------------------------------------------
    RETURN jsonb_build_object(
        'success', true,
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

COMMENT ON FUNCTION settle_bet_tx IS 'Atomic settlement: updates bet, creates ledger entry, records settlement event, and emits audit events in a single transaction. v033: fixed audit_events arity mismatch that rolled back every settlement.';
