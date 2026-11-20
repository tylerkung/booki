-- Undo migration 065. Does not delete or update bet rows or idempotency
-- key rows. Dropping the columns added by 065 removes those values from
-- rows this migration's functions inserted; it does not remove the rows.
--
-- Restoring UNIQUE (key, operation) fails if two players have since stored
-- the same key string. Do not delete rows to force it. Leave the scoped
-- indexes in place instead.
--
-- One transaction. A failure restoring the old unique key undoes the drops
-- as well, so a half-applied rollback is not left behind.

BEGIN;

DROP FUNCTION IF EXISTS claim_bet_submission(text, text, uuid, uuid, uuid, jsonb, jsonb, jsonb);
DROP FUNCTION IF EXISTS peek_bet_submission(text, text, uuid, uuid, jsonb);
DROP FUNCTION IF EXISTS submit_idempotency_decision(idempotency_keys, jsonb);
DROP FUNCTION IF EXISTS find_submit_idempotency(text, text, uuid, uuid, boolean);

DROP INDEX IF EXISTS uq_idempotency_submit_player_op_key;
DROP INDEX IF EXISTS uq_idempotency_submit_user_op_key;
DROP INDEX IF EXISTS uq_idempotency_submit_op_key_null_user;
DROP INDEX IF EXISTS uq_idempotency_op_key_non_submit;
DROP INDEX IF EXISTS idx_bets_player_idempotency_key;

ALTER TABLE bets DROP COLUMN IF EXISTS idempotency_key;
ALTER TABLE idempotency_keys DROP COLUMN IF EXISTS request_payload;
ALTER TABLE idempotency_keys DROP COLUMN IF EXISTS bookie_id;
ALTER TABLE idempotency_keys DROP COLUMN IF EXISTS player_id;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint c
        JOIN pg_class t ON t.oid = c.conrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE n.nspname = 'public'
          AND t.relname = 'idempotency_keys'
          AND c.contype = 'u'
          AND c.conname = 'idempotency_keys_key_operation_key'
    ) THEN
        ALTER TABLE idempotency_keys
            ADD CONSTRAINT idempotency_keys_key_operation_key UNIQUE (key, operation);
    END IF;
END $$;

COMMIT;
