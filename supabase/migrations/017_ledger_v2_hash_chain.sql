-- ============================================================================
-- Ledger V2: Hash Chain
-- Migration: 017_ledger_v2_hash_chain.sql
-- Description: Tamper-evident hash chaining on ledger entries. Each entry
--              stores prev_hash (link to predecessor) and entry_hash
--              (SHA-256 of key fields). Any direct DB mutation is detectable.
-- ============================================================================

-- ============================================================================
-- ADD HASH CHAIN COLUMNS TO LEDGER_ENTRIES
-- ============================================================================
ALTER TABLE ledger_entries ADD COLUMN IF NOT EXISTS prev_hash TEXT;
ALTER TABLE ledger_entries ADD COLUMN IF NOT EXISTS entry_hash TEXT;

-- ============================================================================
-- COMPUTE_LEDGER_HASH: Trigger function for automatic hash computation
-- Fires BEFORE INSERT on ledger_entries.
-- Chain is scoped per (bookie_id, player_id) — each player under each bookie
-- has their own independent chain.
-- ============================================================================
CREATE OR REPLACE FUNCTION compute_ledger_hash()
RETURNS TRIGGER AS $$
DECLARE
    v_prev_hash TEXT;
BEGIN
    -- Look up most recent entry_hash for the same (bookie_id, player_id) chain.
    -- FOR UPDATE prevents race conditions with concurrent inserts.
    SELECT entry_hash INTO v_prev_hash
      FROM ledger_entries
     WHERE bookie_id = NEW.bookie_id
       AND player_id = NEW.player_id
     ORDER BY created_at DESC
     LIMIT 1
       FOR UPDATE;

    -- Set prev_hash (NULL for chain head)
    NEW.prev_hash := v_prev_hash;

    -- Compute entry_hash = SHA-256 of key fields
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
$$ LANGUAGE plpgsql;

-- Apply trigger BEFORE INSERT on ledger_entries
CREATE TRIGGER compute_ledger_hash_trigger
    BEFORE INSERT ON ledger_entries
    FOR EACH ROW
    EXECUTE FUNCTION compute_ledger_hash();

-- ============================================================================
-- BACKFILL EXISTING LEDGER ENTRIES
-- Temporarily disable immutability trigger, compute hash chain per
-- (bookie_id, player_id) pair ordered by created_at ASC, then re-enable.
-- ============================================================================
DO $$
DECLARE
    v_pair RECORD;
    v_entry RECORD;
    v_prev_hash TEXT;
    v_entry_hash TEXT;
BEGIN
    -- Disable immutability trigger for backfill
    ALTER TABLE ledger_entries DISABLE TRIGGER prevent_mutation_ledger_entries;

    -- Iterate each distinct (bookie_id, player_id) chain
    FOR v_pair IN
        SELECT DISTINCT bookie_id, player_id
          FROM ledger_entries
         ORDER BY bookie_id, player_id
    LOOP
        v_prev_hash := NULL;

        -- Iterate entries in chain order
        FOR v_entry IN
            SELECT id, bookie_id, player_id, amount, type, created_at
              FROM ledger_entries
             WHERE bookie_id = v_pair.bookie_id
               AND player_id = v_pair.player_id
             ORDER BY created_at ASC
        LOOP
            v_entry_hash := encode(
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

            UPDATE ledger_entries
               SET prev_hash = v_prev_hash,
                   entry_hash = v_entry_hash
             WHERE id = v_entry.id;

            v_prev_hash := v_entry_hash;
        END LOOP;
    END LOOP;

    -- Re-enable immutability trigger
    ALTER TABLE ledger_entries ENABLE TRIGGER prevent_mutation_ledger_entries;
END;
$$;

-- ============================================================================
-- ADD NOT NULL CONSTRAINT ON entry_hash
-- (prev_hash stays nullable for chain heads)
-- ============================================================================
ALTER TABLE ledger_entries ALTER COLUMN entry_hash SET NOT NULL;

-- ============================================================================
-- COMMENTS
-- ============================================================================
COMMENT ON COLUMN ledger_entries.prev_hash IS 'Hash of the previous entry in this (bookie_id, player_id) chain. NULL for chain head.';
COMMENT ON COLUMN ledger_entries.entry_hash IS 'SHA-256 hash of key fields + prev_hash for tamper detection';
COMMENT ON FUNCTION compute_ledger_hash IS 'Trigger function that auto-computes hash chain fields on ledger entry insertion';
