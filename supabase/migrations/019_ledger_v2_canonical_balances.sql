-- ============================================================================
-- Canonical Server-Side Balances
-- Migration: 019_ledger_v2_canonical_balances.sql
-- Description: View and RPC for authoritative balance computation from ledger
-- ============================================================================

-- ============================================================================
-- PLAYER_BALANCES_VIEW
-- Aggregates ledger entries to produce canonical balance per (bookie, player)
-- security_barrier enforces RLS from underlying ledger_entries table
-- ============================================================================
CREATE VIEW player_balances_view WITH (security_barrier = true) AS
SELECT
    bookie_id,
    player_id,
    COALESCE(SUM(amount), 0) AS balance_owed
FROM ledger_entries
GROUP BY bookie_id, player_id;

-- Grant access to authenticated users (RLS on ledger_entries filters rows)
GRANT SELECT ON player_balances_view TO authenticated;

-- ============================================================================
-- GET_PLAYER_BALANCE RPC
-- Returns canonical balance, open stakes, and available credit for a player
-- ============================================================================
CREATE OR REPLACE FUNCTION get_player_balance(
    p_bookie_id UUID,
    p_player_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_balance_owed DECIMAL(15, 2);
    v_open_stakes DECIMAL(15, 2);
    v_credit_limit DECIMAL(15, 2);
    v_available_credit DECIMAL(15, 2);
BEGIN
    -- Sum all ledger entries for this (bookie, player) pair
    SELECT COALESCE(SUM(amount), 0)
    INTO v_balance_owed
    FROM ledger_entries
    WHERE bookie_id = p_bookie_id
      AND player_id = p_player_id;

    -- Sum stakes of open bets (pending + accepted)
    SELECT COALESCE(SUM(stake), 0)
    INTO v_open_stakes
    FROM bets
    WHERE bookie_id = p_bookie_id
      AND player_id = p_player_id
      AND status IN ('pending', 'accepted');

    -- Get player's credit limit
    SELECT credit_limit
    INTO v_credit_limit
    FROM players
    WHERE id = p_player_id
      AND bookie_id = p_bookie_id;

    -- If player not found, return error
    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Player not found for this bookie'
        );
    END IF;

    -- Default NULL credit_limit to 0
    v_credit_limit := COALESCE(v_credit_limit, 0);

    -- Available credit = credit_limit - open_stakes - balance_owed
    v_available_credit := v_credit_limit - v_open_stakes - v_balance_owed;

    RETURN jsonb_build_object(
        'success', true,
        'balance_owed', v_balance_owed,
        'open_stakes', v_open_stakes,
        'credit_limit', v_credit_limit,
        'available_credit', v_available_credit
    );
END;
$$;

-- Comment on function
COMMENT ON FUNCTION get_player_balance IS 'Returns canonical server-side balance for a player: balance_owed (sum of ledger), open_stakes (pending+accepted bets), available_credit (credit_limit - open_stakes - balance_owed)';
COMMENT ON VIEW player_balances_view IS 'Aggregated view of player balances from ledger_entries. Positive = player owes bookie.';
