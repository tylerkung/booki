-- ============================================================================
-- Ledger V2: Reversal & Override RPC Functions
-- Migration: 016_ledger_v2_reversal_rpcs.sql
-- Description: Transactional RPC functions for settlement reversal and
--              grade override so these correction flows cannot produce
--              partial state.
-- ============================================================================

-- ============================================================================
-- REVERSE_SETTLEMENT_TX: Atomic settlement reversal RPC function
-- Performs settlement reversal in a single transaction:
--   1. Validates bet is settled
--   2. Finds most recent settlement ledger entry
--   3. Creates reversal ledger entry with negated amount
--   4. Updates bet status back to 'graded'
--   5. Creates audit events
-- If any step fails, entire transaction rolls back.
-- ============================================================================
CREATE OR REPLACE FUNCTION reverse_settlement_tx(
    p_bet_id UUID,
    p_actor_user_id UUID,
    p_reason TEXT,
    p_idempotency_key TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_bet RECORD;
    v_original_entry RECORD;
    v_reversal_amount DECIMAL(15, 2);
    v_reversal_description TEXT;
    v_now TIMESTAMPTZ := NOW();
    v_reversal_entry_id UUID;
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

    IF v_bet.status <> 'settled' THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', format('Bet cannot be reversed (current status: %s). Only settled bets can be reversed.', v_bet.status)
        );
    END IF;

    -- ----------------------------------------------------------------
    -- 2. Find the most recent settlement ledger entry
    -- ----------------------------------------------------------------
    SELECT id, amount, type, description
      INTO v_original_entry
      FROM ledger_entries
     WHERE bet_id = p_bet_id
       AND type = 'settlement'
     ORDER BY created_at DESC
     LIMIT 1;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'Settlement ledger entry not found for this bet');
    END IF;

    -- ----------------------------------------------------------------
    -- 3. Create reversal ledger entry with negated amount
    -- ----------------------------------------------------------------
    v_reversal_amount := -1 * v_original_entry.amount;
    v_reversal_description := format('Settlement reversal: %s', p_reason);

    INSERT INTO ledger_entries (bookie_id, player_id, bet_id, amount, type, description, created_at)
    VALUES (v_bet.bookie_id, v_bet.player_id, p_bet_id, v_reversal_amount, 'reversal', v_reversal_description, v_now)
    RETURNING id INTO v_reversal_entry_id;

    -- ----------------------------------------------------------------
    -- 4. Update bet status back to 'graded'
    -- ----------------------------------------------------------------
    UPDATE bets
       SET status = 'graded',
           updated_at = v_now
     WHERE id = p_bet_id;

    -- ----------------------------------------------------------------
    -- 5. Insert audit events (bet reversal + reversal ledger entry creation)
    -- ----------------------------------------------------------------
    INSERT INTO audit_events (bookie_id, actor_user_id, entity_type, entity_id, action_type, previous_state, new_state, created_at)
    VALUES (
        v_bet.bookie_id,
        p_actor_user_id,
        'bet',
        p_bet_id,
        'reverse',
        jsonb_build_object('status', 'settled', 'grade_result', v_bet.grade_result),
        jsonb_build_object('status', 'graded', 'grade_result', v_bet.grade_result),
        v_now
    );

    INSERT INTO audit_events (bookie_id, actor_user_id, entity_type, entity_id, action_type, previous_state, new_state, created_at)
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

    -- ----------------------------------------------------------------
    -- 6. Return success with bet + reversal entry data
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
            'status', 'graded',
            'grade_result', v_bet.grade_result,
            'accepted_at', v_bet.accepted_at,
            'created_at', v_bet.created_at,
            'updated_at', v_now
        ),
        'reversal_entry', jsonb_build_object(
            'id', v_reversal_entry_id,
            'bookie_id', v_bet.bookie_id,
            'player_id', v_bet.player_id,
            'bet_id', p_bet_id,
            'amount', v_reversal_amount,
            'type', 'reversal',
            'description', v_reversal_description,
            'created_at', v_now
        )
    );
END;
$$;

-- ============================================================================
-- OVERRIDE_GRADE_TX: Atomic grade override RPC function
-- Handles two cases:
--   A) Bet is 'settled': reverses settlement first, then overrides grade
--   B) Bet is 'graded': just overrides grade_result
-- If any step fails, entire transaction rolls back.
-- ============================================================================
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
BEGIN
    -- ----------------------------------------------------------------
    -- 1. Validate new_outcome
    -- ----------------------------------------------------------------
    IF p_new_outcome NOT IN ('win', 'loss', 'push', 'void') THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', format('Invalid new_outcome: %s. Must be one of: win, loss, push, void', p_new_outcome)
        );
    END IF;

    -- ----------------------------------------------------------------
    -- 2. Fetch and validate the bet (lock row for update)
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
        RETURN jsonb_build_object('success', false, 'error', 'Bet has not been graded yet. Only graded bets can have their grade overridden.');
    END IF;

    v_previous_grade_result := v_bet.grade_result;
    v_previous_status := v_bet.status;

    -- ----------------------------------------------------------------
    -- 3. If bet is settled, reverse the settlement first
    -- ----------------------------------------------------------------
    IF v_bet.status = 'settled' THEN
        -- Find the most recent settlement ledger entry
        SELECT id, amount, type, description
          INTO v_original_entry
          FROM ledger_entries
         WHERE bet_id = p_bet_id
           AND type = 'settlement'
         ORDER BY created_at DESC
         LIMIT 1;

        IF NOT FOUND THEN
            RETURN jsonb_build_object('success', false, 'error', 'Settlement ledger entry not found for this bet');
        END IF;

        -- Create reversal ledger entry
        v_reversal_amount := -1 * v_original_entry.amount;
        v_reversal_description := format('Settlement reversal for grade override: %s', p_reason);

        INSERT INTO ledger_entries (bookie_id, player_id, bet_id, amount, type, description, created_at)
        VALUES (v_bet.bookie_id, v_bet.player_id, p_bet_id, v_reversal_amount, 'reversal', v_reversal_description, v_now)
        RETURNING id INTO v_reversal_entry_id;

        -- Audit: settlement reversal
        INSERT INTO audit_events (bookie_id, actor_user_id, entity_type, entity_id, action_type, previous_state, new_state, created_at)
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

        -- Audit: reversal ledger entry creation
        INSERT INTO audit_events (bookie_id, actor_user_id, entity_type, entity_id, action_type, previous_state, new_state, created_at)
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

    -- ----------------------------------------------------------------
    -- 4. Update bet: grade_result to new outcome, status to 'graded'
    -- ----------------------------------------------------------------
    UPDATE bets
       SET grade_result = p_new_outcome,
           status = 'graded',
           updated_at = v_now
     WHERE id = p_bet_id;

    -- ----------------------------------------------------------------
    -- 5. Audit event for grade override
    -- ----------------------------------------------------------------
    INSERT INTO audit_events (bookie_id, actor_user_id, entity_type, entity_id, action_type, previous_state, new_state, created_at)
    VALUES (
        v_bet.bookie_id,
        p_actor_user_id,
        'bet',
        p_bet_id,
        'override',
        jsonb_build_object('status', v_previous_status, 'grade_result', v_previous_grade_result),
        jsonb_build_object('status', 'graded', 'grade_result', p_new_outcome),
        v_now
    );

    -- ----------------------------------------------------------------
    -- 6. Return success
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
END;
$$;

-- ============================================================================
-- COMMENTS
-- ============================================================================
COMMENT ON FUNCTION reverse_settlement_tx IS 'Atomic settlement reversal: creates reversal ledger entry, updates bet to graded, and emits audit events in a single transaction';
COMMENT ON FUNCTION override_grade_tx IS 'Atomic grade override: if settled, reverses settlement first; then updates grade_result and emits audit events in a single transaction';
