-- ============================================================================
-- Ledger V2: Validate Hash Chain
-- Migration: 018_ledger_v2_validate_chain.sql
-- Description: Read-only RPC function to verify the tamper-evident hash chain
--              for any (bookie_id, player_id) pair. Recomputes hashes and
--              compares against stored values to detect mutations.
-- ============================================================================

-- ============================================================================
-- VALIDATE_LEDGER_CHAIN: RPC function for on-demand chain verification
-- ============================================================================
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
    -- Iterate all ledger entries for this chain in insertion order
    FOR v_entry IN
        SELECT id, bookie_id, player_id, amount, type, created_at, prev_hash, entry_hash
          FROM ledger_entries
         WHERE bookie_id = p_bookie_id
           AND player_id = p_player_id
         ORDER BY created_at ASC
    LOOP
        v_entries_checked := v_entries_checked + 1;

        -- Verify prev_hash links correctly
        IF v_entry.prev_hash IS DISTINCT FROM v_prev_hash THEN
            RETURN jsonb_build_object(
                'valid', false,
                'entries_checked', v_entries_checked,
                'first_invalid_entry_id', v_entry.id,
                'error_message', format('prev_hash mismatch at entry %s: expected %s, got %s',
                    v_entry.id, coalesce(v_prev_hash, 'NULL'), coalesce(v_entry.prev_hash, 'NULL'))
            );
        END IF;

        -- Recompute expected hash using same formula as compute_ledger_hash trigger
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

        -- Verify entry_hash matches recomputed hash
        IF v_entry.entry_hash IS DISTINCT FROM v_expected_hash THEN
            RETURN jsonb_build_object(
                'valid', false,
                'entries_checked', v_entries_checked,
                'first_invalid_entry_id', v_entry.id,
                'error_message', format('Hash mismatch at entry %s', v_entry.id)
            );
        END IF;

        -- Advance chain
        v_prev_hash := v_entry.entry_hash;
    END LOOP;

    -- All entries valid
    RETURN jsonb_build_object(
        'valid', true,
        'entries_checked', v_entries_checked
    );
END;
$$;

-- ============================================================================
-- COMMENTS
-- ============================================================================
COMMENT ON FUNCTION validate_ledger_chain IS 'Validates the tamper-evident hash chain for a (bookie_id, player_id) ledger. Returns { valid, entries_checked, first_invalid_entry_id, error_message }.';
