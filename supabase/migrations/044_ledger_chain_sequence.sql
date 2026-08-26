-- ============================================================================
-- 044 — Chain the ledger by an insertion sequence, not by timestamp
--
-- CORRECTS MIGRATION 043, which was wrong and made one case worse.
--
-- 043 tried to break created_at ties with the row id: the trigger looked for a
-- predecessor WHERE (created_at, id) < (NEW.created_at, NEW.id). Row ids are
-- random UUIDs, so a new entry whose id happens to sort BEFORE an existing
-- same-timestamp entry matches nothing and gets a NULL prev_hash in the middle
-- of the chain — about half the time. Verified: six separate inserts sharing a
-- created_at produced a NULL prev_hash on the second.
--
-- The deeper problem 043 missed: created_at defaults to now(), which in
-- PostgreSQL is TRANSACTION time. Every entry written inside one transaction —
-- settling a slate, settling a parlay's legs — shares it exactly. No tiebreak
-- built from random ids can order those, because insertion order and sort order
-- are unrelated.
--
-- A hash chain needs a total order that MATCHES INSERTION. That is what a
-- sequence is for.
--
--   seq BIGSERIAL   assigned by nextval at insert, strictly increasing,
--                   independent of clock and of transaction boundaries
--
-- Both ends now use it, so the trigger's predecessor and the validator's walk
-- are the same order by construction rather than by coincidence.
--
-- Existing rows get a seq in physical order. Their chains were already
-- ambiguous, so this neither repairs nor worsens them; entries are not
-- re-hashed, because ledger_entries is immutable and rewriting history to
-- satisfy a validator is what an audit log exists to prevent.
-- ============================================================================

ALTER TABLE ledger_entries
    ADD COLUMN IF NOT EXISTS seq BIGSERIAL;

COMMENT ON COLUMN ledger_entries.seq IS
    'Insertion order. The hash chain is built and validated in this order — NOT created_at, which is transaction time and identical for every entry written in one transaction.';

CREATE INDEX IF NOT EXISTS idx_ledger_entries_chain_seq
    ON ledger_entries (bookie_id, player_id, seq);

CREATE OR REPLACE FUNCTION compute_ledger_hash()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_prev_hash TEXT;
BEGIN
    -- NEW.seq is already populated: column defaults are evaluated before
    -- BEFORE ROW triggers fire.
    --
    -- No "< NEW.seq" filter is needed, and adding one is what broke 043: this
    -- is a BEFORE INSERT trigger, so NEW is not in the table yet and the most
    -- recent row by seq is necessarily its predecessor.
    SELECT entry_hash INTO v_prev_hash
      FROM ledger_entries
     WHERE bookie_id = NEW.bookie_id
       AND player_id = NEW.player_id
     ORDER BY seq DESC
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
         -- Same order the trigger chained in. This is the whole point.
         ORDER BY seq ASC
    LOOP
        v_entries_checked := v_entries_checked + 1;

        IF v_entry.prev_hash IS DISTINCT FROM v_prev_hash THEN
            RETURN jsonb_build_object(
                'valid', false, 'entries_checked', v_entries_checked,
                'first_invalid_entry_id', v_entry.id,
                'error_message', 'prev_hash mismatch at entry ' || v_entry.id
            );
        END IF;

        v_expected_hash := encode(
            sha256(
                concat(
                    coalesce(v_prev_hash, ''), v_entry.bookie_id::text,
                    v_entry.player_id::text, v_entry.amount::text, v_entry.type,
                    v_entry.created_at::text, v_entry.id::text
                )::bytea
            ), 'hex');

        IF v_entry.entry_hash IS DISTINCT FROM v_expected_hash THEN
            RETURN jsonb_build_object(
                'valid', false, 'entries_checked', v_entries_checked,
                'first_invalid_entry_id', v_entry.id,
                'error_message', 'Hash mismatch at entry ' || v_entry.id
            );
        END IF;

        v_prev_hash := v_entry.entry_hash;
    END LOOP;

    RETURN jsonb_build_object(
        'valid', true, 'entries_checked', v_entries_checked,
        'first_invalid_entry_id', NULL, 'error_message', NULL
    );
END;
$$;

DO $$
DECLARE
    n INT;
BEGIN
    SELECT count(*) INTO n
      FROM pg_trigger t JOIN pg_proc p ON p.oid = t.tgfoid
     WHERE t.tgname = 'compute_ledger_hash_trigger' AND p.proname = 'compute_ledger_hash';
    IF n <> 1 THEN
        RAISE EXCEPTION 'compute_ledger_hash_trigger is not bound to compute_ledger_hash';
    END IF;
    RAISE NOTICE 'ledger chain now ordered by seq at both ends';
END $$;
