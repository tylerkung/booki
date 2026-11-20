-- ============================================================================
-- One ticket per submit idempotency key
-- Migration: 065_submit_idempotency.sql
--
-- THE BUG
-- -------
-- submit_bets checked idempotency_keys, inserted the bet, then inserted the
-- key. Those are three separate requests. Two in-flight calls with the same
-- key both saw "not found" (PostgREST 406), both inserted a bet, and the
-- key insert then returned 201 for one and 409/23505 for the other. The
-- second bet was already committed. There is no tickets table and bets had
-- no idempotency column, so the database enforced nothing.
--
-- Confirmed in production on 2026-11-20 and left untouched by this file:
--   key    0845800d   one submit_bets key, stored against the first ticket
--   ticket defc7465   bet 55c3ae26   Colorado +3, -110, $1, 12:08:09.632 PT
--   ticket 51bd1346   bet 569a7dbd   same market 1050ea8a, 1.397s later
--
-- WHAT THIS FILE DOES
-- -------------------
-- claim_bet_submission takes the idempotency key and inserts the bet rows
-- in one transaction. A second call with the same player, operation, and
-- key waits, then returns the stored response and inserts nothing. The same
-- key with a different payload raises idempotency_payload_mismatch (SQLSTATE
-- P0422) and writes nothing. The edge functions map that to HTTP 422.
--
-- The unique key is per player, not global. Player A's key cannot collide
-- with player B's. The old UNIQUE (key, operation) made that collision, and
-- it also made every other operation's key global. This file replaces it
-- with:
--   * submit operations: UNIQUE (user_id, operation, key), plus
--     UNIQUE (player_id, operation, key) where player_id is set
--   * every other operation: UNIQUE (operation, key), same as before
-- Old submit functions still insert (key, operation, response, user_id)
-- with a null player_id. The same user repeating a key still hits 23505.
-- A different user's key does not. Existing rows already satisfy the new
-- indexes because (key, operation) was unique, so the indexes build without
-- rewriting a row.
--
-- bets.idempotency_key records which key created the row. It is not unique
-- on bets: one submit_bets call inserts several singles, and one parlay
-- inserts several legs, all under one key. The uniqueness is the
-- idempotency_keys row.
--
-- A row written by the old functions has a null request_payload. Replaying
-- that key returns the stored response. There is no payload to compare.
-- This file does not backfill one.
--
-- Safe while the old functions are live: additive columns, new indexes,
-- a narrower unique key, and functions nothing calls until the new
-- submit_bet / submit_bets / submit_parlay builds are deployed. No UPDATE.
-- No DELETE. No rewrite of existing bets or idempotency_keys rows.
-- Re-running the file only replaces functions and skips existing columns
-- and indexes. 064 (main line identity) is a different table; this file
-- does not depend on it. Calling claim_bet_submission before migration 062
-- fails at runtime because the insert names the prop snapshot columns.
--
-- ----------------------------------------------------------------------------
-- Read-only check for the existing duplicate. Do not run it as part of
-- applying this file. It does not update or delete anything. It should list
-- tickets defc7465 and 51bd1346 (key 0845800d). Do not correct them.
-- A batch of singles shares one key across tickets on purpose; those tickets
-- are named in the key's response and are not what this looks for. The
-- duplicate is a second ticket that the key row does not name.
--
-- WITH keyed AS (
--   SELECT
--     ik.key,
--     ik.operation,
--     (elem->>'id')::uuid AS bet_id
--   FROM idempotency_keys ik
--   CROSS JOIN LATERAL jsonb_array_elements(
--     CASE
--       WHEN jsonb_typeof(ik.response::jsonb->'bets') = 'array' THEN ik.response::jsonb->'bets'
--       WHEN jsonb_typeof(ik.response::jsonb->'bet') = 'object' THEN jsonb_build_array(ik.response::jsonb->'bet')
--       ELSE '[]'::jsonb
--     END
--   ) AS elem
--   WHERE ik.operation IN ('submit_bet', 'submit_bets', 'submit_parlay')
-- )
-- SELECT
--   k.key,
--   k.operation,
--   stored.ticket_id AS stored_ticket_id,
--   stored.id AS stored_bet_id,
--   dup.ticket_id AS duplicate_ticket_id,
--   dup.id AS duplicate_bet_id,
--   dup.market_id,
--   dup.odds,
--   dup.stake,
--   stored.created_at AS stored_at,
--   dup.created_at AS duplicate_at
-- FROM keyed k
-- JOIN bets stored ON stored.id = k.bet_id
-- JOIN bets dup
--   ON dup.player_id = stored.player_id
--  AND dup.market_id IS NOT DISTINCT FROM stored.market_id
--  AND dup.odds = stored.odds
--  AND dup.stake = stored.stake
--  AND dup.ticket_id <> stored.ticket_id
--  AND dup.id <> stored.id
--  AND dup.created_at BETWEEN stored.created_at - interval '5 seconds'
--                        AND stored.created_at + interval '30 seconds'
-- ORDER BY k.key, stored.ticket_id, dup.ticket_id;
-- ----------------------------------------------------------------------------

ALTER TABLE idempotency_keys
    ADD COLUMN IF NOT EXISTS player_id UUID,
    ADD COLUMN IF NOT EXISTS bookie_id UUID,
    ADD COLUMN IF NOT EXISTS request_payload JSONB;

ALTER TABLE bets
    ADD COLUMN IF NOT EXISTS idempotency_key TEXT;

COMMENT ON COLUMN idempotency_keys.player_id IS
  'Player this submit key belongs to. NULL on rows written before migration 065 and on every non-submit operation. Together with operation and key it is unique when set, so one player''s key cannot collide with another''s.';

COMMENT ON COLUMN idempotency_keys.bookie_id IS
  'Bookie for a submit key. NULL on older rows. Not part of the unique key.';

COMMENT ON COLUMN idempotency_keys.request_payload IS
  'Canonical submit payload. NULL on rows the old functions stored. A replay with a different payload raises P0422. A NULL payload replays the stored response.';

COMMENT ON COLUMN bets.idempotency_key IS
  'Submit key that created this row. Not unique here: one submit_bets or submit_parlay call writes several rows under one key. Uniqueness is idempotency_keys (player_id, operation, key). NULL on rows written before migration 065.';

-- Build the new indexes before dropping the old constraint, so a re-run
-- that stops in the middle still has a unique key in place.
CREATE UNIQUE INDEX IF NOT EXISTS uq_idempotency_submit_user_op_key
    ON idempotency_keys (user_id, operation, key)
    WHERE operation IN ('submit_bet', 'submit_bets', 'submit_parlay')
      AND user_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_idempotency_submit_player_op_key
    ON idempotency_keys (player_id, operation, key)
    WHERE operation IN ('submit_bet', 'submit_bets', 'submit_parlay')
      AND player_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_idempotency_submit_op_key_null_user
    ON idempotency_keys (operation, key)
    WHERE operation IN ('submit_bet', 'submit_bets', 'submit_parlay')
      AND user_id IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_idempotency_op_key_non_submit
    ON idempotency_keys (operation, key)
    WHERE operation NOT IN ('submit_bet', 'submit_bets', 'submit_parlay');

CREATE INDEX IF NOT EXISTS idx_bets_player_idempotency_key
    ON bets (player_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;

-- The pre-065 table constraint. Dropping it does not rewrite rows.
-- New indexes above already cover every existing row.
DO $$
DECLARE
    conname text;
BEGIN
    SELECT c.conname INTO conname
    FROM pg_constraint c
    JOIN pg_class t ON t.oid = c.conrelid
    JOIN pg_namespace n ON n.oid = t.relnamespace
    WHERE n.nspname = 'public'
      AND t.relname = 'idempotency_keys'
      AND c.contype = 'u'
      AND (
          SELECT array_agg(a.attname::text ORDER BY a.attname)
          FROM unnest(c.conkey) AS ck(colnum)
          JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = ck.colnum
      ) = ARRAY['key', 'operation']::text[];

    IF conname IS NOT NULL THEN
        EXECUTE format('ALTER TABLE public.idempotency_keys DROP CONSTRAINT %I', conname);
    END IF;
END $$;

DROP FUNCTION IF EXISTS claim_bet_submission(text, text, uuid, uuid, uuid, jsonb, jsonb, jsonb);
DROP FUNCTION IF EXISTS peek_bet_submission(text, text, uuid, uuid, jsonb);
DROP FUNCTION IF EXISTS submit_idempotency_decision(idempotency_keys, jsonb);
DROP FUNCTION IF EXISTS find_submit_idempotency(text, text, uuid, uuid, boolean);

CREATE FUNCTION find_submit_idempotency(
    p_operation text,
    p_key text,
    p_user_id uuid,
    p_player_id uuid,
    p_lock boolean
) RETURNS idempotency_keys
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_row idempotency_keys;
BEGIN
    IF p_lock THEN
        SELECT * INTO v_row
        FROM idempotency_keys
        WHERE operation = p_operation
          AND key = p_key
          AND (
              player_id = p_player_id
              OR (player_id IS NULL AND user_id = p_user_id)
          )
        ORDER BY (player_id IS NOT NULL) DESC, created_at
        LIMIT 1
        FOR UPDATE;
    ELSE
        SELECT * INTO v_row
        FROM idempotency_keys
        WHERE operation = p_operation
          AND key = p_key
          AND (
              player_id = p_player_id
              OR (player_id IS NULL AND user_id = p_user_id)
          )
        ORDER BY (player_id IS NOT NULL) DESC, created_at
        LIMIT 1;
    END IF;
    RETURN v_row;
END;
$$;

-- Legacy rows (request_payload NULL) replay the stored response.
-- A stored payload that differs raises P0422 and the caller writes nothing.
CREATE FUNCTION submit_idempotency_decision(
    p_existing idempotency_keys,
    p_request jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF p_existing.request_payload IS NOT NULL
       AND p_existing.request_payload IS DISTINCT FROM p_request THEN
        RAISE EXCEPTION 'idempotency_payload_mismatch'
            USING ERRCODE = 'P0422';
    END IF;
    RETURN jsonb_build_object(
        'replayed', true,
        'response', p_existing.response::jsonb
    );
END;
$$;

CREATE FUNCTION peek_bet_submission(
    p_operation text,
    p_idempotency_key text,
    p_user_id uuid,
    p_player_id uuid,
    p_request jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_existing idempotency_keys;
BEGIN
    IF p_operation NOT IN ('submit_bet', 'submit_bets', 'submit_parlay') THEN
        RAISE EXCEPTION 'unsupported submit operation'
            USING ERRCODE = '22023';
    END IF;

    v_existing := find_submit_idempotency(
        p_operation, p_idempotency_key, p_user_id, p_player_id, false
    );
    IF v_existing IS NULL OR v_existing.id IS NULL THEN
        RETURN jsonb_build_object('found', false);
    END IF;
    RETURN jsonb_build_object('found', true)
        || submit_idempotency_decision(v_existing, p_request);
END;
$$;

CREATE FUNCTION claim_bet_submission(
    p_operation text,
    p_idempotency_key text,
    p_user_id uuid,
    p_player_id uuid,
    p_bookie_id uuid,
    p_request jsonb,
    p_bets jsonb,
    p_extra jsonb DEFAULT '{}'::jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_existing idempotency_keys;
    v_elem record;
    v_bet jsonb;
    v_rows jsonb := '[]'::jsonb;
    v_body jsonb;
    v_response text;
BEGIN
    IF p_operation NOT IN ('submit_bet', 'submit_bets', 'submit_parlay') THEN
        RAISE EXCEPTION 'unsupported submit operation'
            USING ERRCODE = '22023';
    END IF;
    IF p_idempotency_key IS NULL OR length(btrim(p_idempotency_key)) = 0 THEN
        RAISE EXCEPTION 'idempotency key is required'
            USING ERRCODE = '22023';
    END IF;
    IF p_user_id IS NULL OR p_player_id IS NULL OR p_bookie_id IS NULL THEN
        RAISE EXCEPTION 'submit requires user, player, and bookie'
            USING ERRCODE = '22023';
    END IF;
    IF p_request IS NULL OR jsonb_typeof(p_request) <> 'object' THEN
        RAISE EXCEPTION 'submit request payload must be an object'
            USING ERRCODE = '22023';
    END IF;
    IF p_bets IS NULL OR jsonb_typeof(p_bets) <> 'array' OR jsonb_array_length(p_bets) = 0 THEN
        RAISE EXCEPTION 'submit requires at least one bet'
            USING ERRCODE = '22023';
    END IF;
    IF p_operation = 'submit_bet' AND jsonb_array_length(p_bets) <> 1 THEN
        RAISE EXCEPTION 'submit_bet accepts one bet'
            USING ERRCODE = '22023';
    END IF;
    IF p_extra IS NULL THEN
        p_extra := '{}'::jsonb;
    END IF;

    -- Serialize this player+key and this user+key. The second lock covers a
    -- legacy row that has user_id set and player_id null. Two different
    -- players take different locks and both succeed.
    PERFORM pg_advisory_xact_lock(hashtextextended(
        'booki-submit-player:' || p_player_id::text || '|' || p_operation || '|' || p_idempotency_key,
        0
    ));
    PERFORM pg_advisory_xact_lock(hashtextextended(
        'booki-submit-user:' || p_user_id::text || '|' || p_operation || '|' || p_idempotency_key,
        0
    ));

    v_existing := find_submit_idempotency(
        p_operation, p_idempotency_key, p_user_id, p_player_id, true
    );
    IF v_existing IS NOT NULL AND v_existing.id IS NOT NULL THEN
        RETURN submit_idempotency_decision(v_existing, p_request);
    END IF;

    BEGIN
        FOR v_elem IN
            SELECT elem, ord
            FROM jsonb_array_elements(p_bets) WITH ORDINALITY AS e(elem, ord)
            ORDER BY ord
        LOOP
            INSERT INTO bets (
                bookie_id, player_id, event_id, ticket_id, market, market_id, side,
                stat_key, subject_player_id, prop_line, odds, stake, status, accepted_at,
                is_parlay, parlay_legs, policy_violation_reason, idempotency_key
            ) VALUES (
                p_bookie_id,
                p_player_id,
                v_elem.elem->>'event_id',
                (v_elem.elem->>'ticket_id')::uuid,
                v_elem.elem->>'market',
                NULLIF(v_elem.elem->>'market_id', '')::uuid,
                v_elem.elem->>'side',
                v_elem.elem->>'stat_key',
                NULLIF(v_elem.elem->>'subject_player_id', '')::integer,
                NULLIF(v_elem.elem->>'prop_line', '')::numeric,
                (v_elem.elem->>'odds')::integer,
                (v_elem.elem->>'stake')::numeric,
                COALESCE(v_elem.elem->>'status', 'pending'),
                NULLIF(v_elem.elem->>'accepted_at', '')::timestamptz,
                COALESCE((v_elem.elem->>'is_parlay')::boolean, false),
                COALESCE((v_elem.elem->>'parlay_legs')::integer, 1),
                v_elem.elem->>'policy_violation_reason',
                p_idempotency_key
            )
            RETURNING to_jsonb(bets) INTO v_bet;
            v_rows := v_rows || jsonb_build_array(v_bet);
        END LOOP;

        IF p_operation = 'submit_bet' THEN
            v_body := jsonb_build_object('success', true, 'bet', v_rows->0);
        ELSIF p_operation = 'submit_parlay' THEN
            v_body := jsonb_build_object(
                'success', true,
                'bets', v_rows,
                'ticket_id', v_rows->0->>'ticket_id'
            );
        ELSIF p_extra ? 'failed'
              AND jsonb_typeof(p_extra->'failed') = 'array'
              AND jsonb_array_length(p_extra->'failed') > 0 THEN
            v_body := jsonb_build_object(
                'success', true,
                'bets', v_rows,
                'failed', p_extra->'failed'
            );
        ELSE
            v_body := jsonb_build_object('success', true, 'bets', v_rows);
        END IF;

        INSERT INTO idempotency_keys (
            key, operation, response, user_id, player_id, bookie_id, request_payload
        ) VALUES (
            p_idempotency_key,
            p_operation,
            v_body::text,
            p_user_id,
            p_player_id,
            p_bookie_id,
            p_request
        )
        RETURNING response INTO v_response;

        RETURN jsonb_build_object('replayed', false, 'response', v_response::jsonb);
    EXCEPTION
        WHEN unique_violation THEN
            -- The bet inserts above roll back with this subtransaction.
            v_existing := find_submit_idempotency(
                p_operation, p_idempotency_key, p_user_id, p_player_id, true
            );
            IF v_existing IS NULL OR v_existing.id IS NULL THEN
                RAISE;
            END IF;
            RETURN submit_idempotency_decision(v_existing, p_request);
    END;
END;
$$;

DO $$
DECLARE
    fn regprocedure;
BEGIN
    FOR fn IN
        SELECT p.oid::regprocedure
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname IN (
              'claim_bet_submission',
              'peek_bet_submission',
              'submit_idempotency_decision',
              'find_submit_idempotency'
          )
    LOOP
        EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC', fn);
        IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
            EXECUTE format('REVOKE ALL ON FUNCTION %s FROM anon', fn);
        END IF;
        IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
            EXECUTE format('REVOKE ALL ON FUNCTION %s FROM authenticated', fn);
        END IF;
    END LOOP;

    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
        GRANT EXECUTE ON FUNCTION peek_bet_submission(text, text, uuid, uuid, jsonb) TO service_role;
        GRANT EXECUTE ON FUNCTION claim_bet_submission(text, text, uuid, uuid, uuid, jsonb, jsonb, jsonb) TO service_role;
    END IF;
END $$;

COMMENT ON FUNCTION claim_bet_submission(text, text, uuid, uuid, uuid, jsonb, jsonb, jsonb) IS
  'Insert a submit''s bets and its idempotency key in one transaction. Same player+operation+key returns the stored response. A different payload raises P0422.';
