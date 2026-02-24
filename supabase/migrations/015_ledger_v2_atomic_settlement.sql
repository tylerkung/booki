-- ============================================================================
-- Ledger V2: Atomic Settlement
-- Migration: 015_ledger_v2_atomic_settlement.sql
-- Description: Transactional settlement RPC, settlement_events table,
--              and immutability triggers for financial history
-- ============================================================================

-- ============================================================================
-- SETTLEMENT_EVENTS TABLE
-- Tracks every settlement action (manual or auto) with version history
-- ============================================================================
CREATE TABLE IF NOT EXISTS settlement_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bookie_id UUID NOT NULL REFERENCES bookies(id) ON DELETE CASCADE,
    bet_id UUID NOT NULL REFERENCES bets(id) ON DELETE CASCADE,
    settlement_version INT NOT NULL DEFAULT 1,
    mode TEXT NOT NULL CHECK (mode IN ('manual', 'auto')),
    actor_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    idempotency_key TEXT,
    ledger_entry_ids UUID[] NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Unique constraint: one settlement per version per bet
ALTER TABLE settlement_events
    ADD CONSTRAINT uq_settlement_events_bet_version UNIQUE (bet_id, settlement_version);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_settlement_events_bet_id ON settlement_events(bet_id);
CREATE INDEX IF NOT EXISTS idx_settlement_events_bookie_timeline ON settlement_events(bookie_id, created_at);

-- ============================================================================
-- ENABLE ROW LEVEL SECURITY ON SETTLEMENT_EVENTS
-- ============================================================================
ALTER TABLE settlement_events ENABLE ROW LEVEL SECURITY;

-- SELECT: Bookies can only see their own settlement events
CREATE POLICY settlement_events_select_own ON settlement_events
    FOR SELECT
    USING (
        bookie_id IN (
            SELECT id FROM bookies WHERE auth_user_id = auth.uid()
        )
    );

-- No INSERT/UPDATE/DELETE policies — service role only

-- ============================================================================
-- IMMUTABILITY TRIGGER FUNCTION
-- Prevents UPDATE or DELETE on financial history tables
-- ============================================================================
CREATE OR REPLACE FUNCTION prevent_mutation()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'Mutation of % is not allowed. This table is immutable.', TG_TABLE_NAME;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Apply immutability trigger to ledger_entries
CREATE TRIGGER prevent_mutation_ledger_entries
    BEFORE UPDATE OR DELETE ON ledger_entries
    FOR EACH ROW
    EXECUTE FUNCTION prevent_mutation();

-- Apply immutability trigger to settlement_events
CREATE TRIGGER prevent_mutation_settlement_events
    BEFORE UPDATE OR DELETE ON settlement_events
    FOR EACH ROW
    EXECUTE FUNCTION prevent_mutation();

-- Apply immutability trigger to audit_events
CREATE TRIGGER prevent_mutation_audit_events
    BEFORE UPDATE OR DELETE ON audit_events
    FOR EACH ROW
    EXECUTE FUNCTION prevent_mutation();

-- ============================================================================
-- SETTLE_BET_TX: Atomic settlement RPC function
-- Performs bet settlement in a single transaction:
--   1. Validates bet state
--   2. Updates bet status to 'settled'
--   3. Creates ledger entry
--   4. Creates settlement_events row
--   5. Creates audit events
-- If any step fails, entire transaction rolls back.
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
        jsonb_build_object('status', 'settled', 'grade_result', v_bet.grade_result)
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
        )
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

-- ============================================================================
-- COMMENTS
-- ============================================================================
COMMENT ON TABLE settlement_events IS 'Tracks every settlement action with version history for audit trail';
COMMENT ON COLUMN settlement_events.bookie_id IS 'The bookie this settlement belongs to';
COMMENT ON COLUMN settlement_events.bet_id IS 'The bet that was settled';
COMMENT ON COLUMN settlement_events.settlement_version IS 'Version counter for re-settlements after reversal';
COMMENT ON COLUMN settlement_events.mode IS 'Settlement mode: manual (bookie-initiated) or auto (system-initiated)';
COMMENT ON COLUMN settlement_events.actor_user_id IS 'The user who triggered settlement (NULL for auto)';
COMMENT ON COLUMN settlement_events.idempotency_key IS 'Idempotency key to prevent duplicate settlements';
COMMENT ON COLUMN settlement_events.ledger_entry_ids IS 'Array of ledger entry IDs created by this settlement';

COMMENT ON FUNCTION settle_bet_tx IS 'Atomic settlement: updates bet, creates ledger entry, records settlement event, and emits audit events in a single transaction';
COMMENT ON FUNCTION prevent_mutation IS 'Trigger function that prevents UPDATE or DELETE on immutable financial tables';

COMMENT ON POLICY settlement_events_select_own ON settlement_events IS 'Bookies can only read their own settlement events';
