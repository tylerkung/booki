-- ============================================================================
-- RPC to delete all bookie data in a single atomic transaction
-- Temporarily disables immutability triggers so audit/ledger/settlement
-- tables can be cleaned up during account deletion.
-- Migration: 025_delete_bookie_data_rpc.sql
-- ============================================================================

CREATE OR REPLACE FUNCTION delete_bookie_data(target_bookie_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Disable immutability triggers
    ALTER TABLE audit_events DISABLE TRIGGER prevent_mutation_audit_events;
    ALTER TABLE settlement_events DISABLE TRIGGER prevent_mutation_settlement_events;
    ALTER TABLE ledger_entries DISABLE TRIGGER prevent_mutation_ledger_entries;

    -- Delete in FK order
    DELETE FROM audit_events WHERE bookie_id = target_bookie_id;
    DELETE FROM settlement_events WHERE bookie_id = target_bookie_id;
    DELETE FROM ledger_entries WHERE bookie_id = target_bookie_id;
    DELETE FROM bets WHERE bookie_id = target_bookie_id;
    DELETE FROM invites WHERE bookie_id = target_bookie_id;
    DELETE FROM players WHERE bookie_id = target_bookie_id;
    DELETE FROM bookies WHERE id = target_bookie_id;

    -- Re-enable immutability triggers
    ALTER TABLE audit_events ENABLE TRIGGER prevent_mutation_audit_events;
    ALTER TABLE settlement_events ENABLE TRIGGER prevent_mutation_settlement_events;
    ALTER TABLE ledger_entries ENABLE TRIGGER prevent_mutation_ledger_entries;
END;
$$;

COMMENT ON FUNCTION delete_bookie_data IS 'Atomically deletes all bookie data including immutable tables. Called by delete_account edge function.';
