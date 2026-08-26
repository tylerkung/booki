-- ============================================================================
-- 043 — Give the ledger hash chain a deterministic order
--
-- THE BUG: neither end of the chain had a tiebreak.
--
--   the trigger      ORDER BY created_at DESC LIMIT 1   (pick predecessor)
--   the validator    ORDER BY created_at ASC            (walk the chain)
--
-- created_at is not unique. Settling a slate writes many entries inside one
-- clock tick, so both orderings are arbitrary among ties and NEED NOT AGREE.
-- Two consequences, both observed on this database:
--
--   1. FALSE ALARMS. The validator walks tied entries in a different order
--      than the trigger chained them and reports a break. Three of six ledgers
--      currently fail validation, including a single-entry ledger, which
--      cannot have a link problem at all.
--
--   2. A REAL FORK. Two entries written in the same tick can both read the same
--      "most recent" predecessor and chain onto it, so the structure stops
--      being a chain. That is the actual weakness: a tamper-evident log whose
--      order is ambiguous cannot evidence much.
--
-- THE FIX: one total order, (created_at, id), used by both. id is a UUID and
-- unique, so ties are broken the same way everywhere, forever.
--
-- SCOPE: this corrects the behaviour from here on. Entries already chained
-- under the ambiguous order are NOT re-chained — ledger_entries is immutable
-- by design and rewriting history to make a validator happy is precisely the
-- thing an audit log exists to prevent. Existing ledgers may therefore continue
-- to report invalid; that is a known, dated condition rather than a live fault,
-- and rebuilding them is a separate deliberate operation.
-- ============================================================================

-- NOTE THE NAME. The trigger created in migration 017 executes
-- compute_ledger_hash(); defining a similarly-named new function would leave
-- the trigger pointing at the old body and the fix would silently do nothing.
CREATE OR REPLACE FUNCTION compute_ledger_hash()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_prev_hash TEXT;
BEGIN
    -- (created_at, id) — the same total order the validator uses. Ordering by
    -- created_at alone let concurrent inserts share a predecessor.
    SELECT entry_hash INTO v_prev_hash
      FROM ledger_entries
     WHERE bookie_id = NEW.bookie_id
       AND player_id = NEW.player_id
       AND (created_at, id) < (NEW.created_at, NEW.id)
     ORDER BY created_at DESC, id DESC
     LIMIT 1
       FOR UPDATE;

    NEW.prev_hash := v_prev_hash;
    NEW.entry_hash := encode(
        sha256(
            concat(
                coalesce(v_prev_hash, ''),
                NEW.bookie_id::text,
                NEW.player_id::text,
                NEW.amount::text,
                NEW.type,
                NEW.created_at::text,
                NEW.id::text
            )::bytea
        ),
        'hex'
    );
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION validate_ledger_chain(
    p_bookie_id UUID,
    p_player_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_entry RECORD;
    v_prev_hash TEXT := NULL;
    v_expected_hash TEXT;
    v_entries_checked INTEGER := 0;
BEGIN
    FOR v_entry IN
        SELECT id, bookie_id, player_id, amount, type, created_at, prev_hash, entry_hash
          FROM ledger_entries
         WHERE bookie_id = p_bookie_id
           AND player_id = p_player_id
         -- Same total order as the trigger. This is the whole fix.
         ORDER BY created_at ASC, id ASC
    LOOP
        v_entries_checked := v_entries_checked + 1;

        IF v_entry.prev_hash IS DISTINCT FROM v_prev_hash THEN
            RETURN jsonb_build_object(
                'valid', false,
                'entries_checked', v_entries_checked,
                'first_invalid_entry_id', v_entry.id,
                'error_message', 'prev_hash mismatch at entry ' || v_entry.id
                    || ': expected ' || coalesce(v_prev_hash, 'NULL')
                    || ', got ' || coalesce(v_entry.prev_hash, 'NULL')
            );
        END IF;

        v_expected_hash := encode(
            sha256(
                concat(
                    coalesce(v_prev_hash, ''),
                    v_entry.bookie_id::text,
                    v_entry.player_id::text,
                    v_entry.amount::text,
                    v_entry.type,
                    v_entry.created_at::text,
                    v_entry.id::text
                )::bytea
            ),
            'hex'
        );

        IF v_entry.entry_hash IS DISTINCT FROM v_expected_hash THEN
            RETURN jsonb_build_object(
                'valid', false,
                'entries_checked', v_entries_checked,
                'first_invalid_entry_id', v_entry.id,
                'error_message', 'Hash mismatch at entry ' || v_entry.id
            );
        END IF;

        v_prev_hash := v_entry.entry_hash;
    END LOOP;

    RETURN jsonb_build_object(
        'valid', true,
        'entries_checked', v_entries_checked,
        'first_invalid_entry_id', NULL,
        'error_message', NULL
    );
END;
$$;

DO $$
BEGIN
    RAISE NOTICE 'ledger chain now ordered by (created_at, id) at BOTH ends';
    RAISE NOTICE 'entries written before this migration are not re-chained and may still report invalid';
END $$;

-- Confirm the trigger still points at the function this migration replaced,
-- rather than assuming the name was right.
DO $$
DECLARE
    n INT;
BEGIN
    SELECT count(*) INTO n
      FROM pg_trigger t
      JOIN pg_proc p ON p.oid = t.tgfoid
     WHERE t.tgname = 'compute_ledger_hash_trigger'
       AND p.proname = 'compute_ledger_hash';
    IF n <> 1 THEN
        RAISE EXCEPTION 'compute_ledger_hash_trigger is not bound to compute_ledger_hash (found %)', n;
    END IF;
    RAISE NOTICE 'trigger verified bound to the updated function';
END $$;
