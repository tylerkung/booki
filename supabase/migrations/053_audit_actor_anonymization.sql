-- ============================================================================
-- Allow FK-driven anonymization of audit_events.actor_user_id
-- Migration: 053_audit_actor_anonymization.sql
--
-- THE BUG
-- -------
-- Deleting an auth user fails outright:
--
--     P0001: Mutation of audit_events is not allowed. This table is immutable.
--
-- audit_events.actor_user_id is declared
--
--     REFERENCES auth.users(id) ON DELETE SET NULL
--
-- so removing a user makes Postgres UPDATE the referencing rows. The
-- immutability trigger from migration 015 blocks every UPDATE on the table,
-- including that one -- so the schema's own ON DELETE SET NULL can never
-- execute. The trigger and the foreign key contradict each other, and the
-- trigger wins.
--
-- WHO THIS BREAKS
-- ---------------
-- Every member. delete_account only calls delete_bookie_data() when the user
-- is an organizer; that RPC disables the triggers and clears the audit rows,
-- which is why organizer deletion works and hid this. A member has no bookie,
-- so nothing removes their audit rows, and claim_invite emits an audit event
-- for every single member at join time. The result is that "Delete Account"
-- returns "Failed to delete account" for all of them -- a shipped, user-facing
-- failure on a flow the App Store requires to work.
--
-- THE FIX
-- -------
-- Permit exactly one mutation: actor_user_id going from a value to NULL, with
-- every other column unchanged. That is the anonymization the FK already
-- declares, and it is the correct trade -- an audit trail records WHAT
-- happened, and that record stays byte-for-byte intact. Only the identity of a
-- deleted account is dropped, which is the thing a deletion request is
-- actually asking for.
--
-- Everything else still raises: any other column change, actor_user_id being
-- changed to a DIFFERENT user, re-populating a NULL actor, and every DELETE.
-- ledger_entries and settlement_events share this trigger function and are
-- deliberately untouched -- they keep the absolute prohibition, because their
-- hash chain depends on it.
-- ============================================================================

CREATE OR REPLACE FUNCTION prevent_mutation()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_TABLE_NAME = 'audit_events'
       AND TG_OP = 'UPDATE'
       AND OLD.actor_user_id IS NOT NULL
       AND NEW.actor_user_id IS NULL
       -- Compare every OTHER column as JSON, so this cannot be used as cover
       -- for editing the record itself. If anything besides actor_user_id
       -- differs, the row is not an anonymization and falls through to the
       -- exception below.
       AND (to_jsonb(NEW) - 'actor_user_id') = (to_jsonb(OLD) - 'actor_user_id')
    THEN
        RETURN NEW;
    END IF;

    RAISE EXCEPTION 'Mutation of % is not allowed. This table is immutable.', TG_TABLE_NAME;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION prevent_mutation IS
  'Blocks UPDATE and DELETE on immutable financial tables. Single exception: '
  'audit_events.actor_user_id may go from a value to NULL with all other '
  'columns unchanged, which is the ON DELETE SET NULL the foreign key already '
  'declares. Without it, deleting any auth user that has ever produced an '
  'audit event fails -- which was every member, via claim_invite.';

-- ---------------------------------------------------------------------------
-- Assert the exception works and is narrow. Written so a failure leaves
-- nothing behind: the whole probe runs inside one block and rolls its own
-- inserted row back by exception. The SQL editor does not wrap a script in a
-- transaction, so anything that writes must clean up after itself.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_bookie UUID;
    v_id     UUID;
    v_ok     BOOLEAN;
BEGIN
    SELECT id INTO v_bookie FROM bookies LIMIT 1;
    IF v_bookie IS NULL THEN
        RAISE NOTICE '053: no bookies present, skipping behavioural assertions';
        RETURN;
    END IF;

    INSERT INTO audit_events (bookie_id, actor_user_id, entity_type, entity_id,
                              action_type, new_state)
    VALUES (v_bookie, NULL, 'migration_probe', gen_random_uuid(),
            'probe', '{}'::jsonb)
    RETURNING id INTO v_id;

    -- 1. a non-anonymizing UPDATE must still be refused
    BEGIN
        UPDATE audit_events SET action_type = 'tampered' WHERE id = v_id;
        v_ok := FALSE;
    EXCEPTION WHEN OTHERS THEN
        v_ok := TRUE;
    END;
    IF NOT v_ok THEN
        RAISE EXCEPTION '053: immutability regression -- audit_events accepted an edit';
    END IF;

    -- 2. DELETE must still be refused
    BEGIN
        DELETE FROM audit_events WHERE id = v_id;
        v_ok := FALSE;
    EXCEPTION WHEN OTHERS THEN
        v_ok := TRUE;
    END;
    IF NOT v_ok THEN
        RAISE EXCEPTION '053: immutability regression -- audit_events accepted a delete';
    END IF;

    -- Roll the probe row back. RAISE inside a nested block aborts the whole
    -- DO body, undoing the INSERT above.
    RAISE EXCEPTION 'rollback_probe';
EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = 'rollback_probe' THEN
        RAISE NOTICE '053: assertions passed, probe row rolled back';
    ELSE
        RAISE;
    END IF;
END $$;
