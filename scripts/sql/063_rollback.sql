-- Drops the 063 guarantee. Does not touch ledger rows.
-- After this, re-apply the function bodies from:
--   supabase/migrations/034_fix_settle_bet_tx_audit_arity.sql
--   supabase/migrations/016_ledger_v2_reversal_rpcs.sql
-- so settle_bet_tx and override_grade_tx are the previous versions.
-- Do not re-run 015; it tries to create tables that already exist.

DROP TRIGGER IF EXISTS reject_duplicate_active_settlement ON ledger_entries;
DROP FUNCTION IF EXISTS reject_duplicate_active_settlement();
DROP INDEX IF EXISTS uq_settlement_events_idempotency_key;
DROP FUNCTION IF EXISTS settle_parlay_tx(uuid, uuid, text, text, numeric, text, jsonb);
DROP FUNCTION IF EXISTS mark_ticket_settled(uuid, timestamptz, boolean);
DROP FUNCTION IF EXISTS settlement_ticket_lock(uuid);
DROP FUNCTION IF EXISTS active_settlement_count(uuid);
