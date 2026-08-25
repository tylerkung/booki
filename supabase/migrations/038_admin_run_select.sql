-- ============================================================================
-- 038 — Read-only SQL escape hatch for the admin dashboard (PRD US-006)
--
-- The admin browser covers the common questions. This exists for the ones it
-- does not, so the tool never dead-ends.
--
-- SELECT-ONLY IS ENFORCED, NOT INSPECTED. Two independent controls:
--
--   1. The query is wrapped as a subquery: SELECT ... FROM ( <query> ) sub.
--      A second statement is then a syntax error rather than a second
--      statement, so `; DROP TABLE x` cannot be smuggled in. This also blocks
--      data-modifying CTEs, because Postgres requires a WITH clause containing
--      INSERT/UPDATE/DELETE to be at the TOP level — nested in a subquery it
--      raises 0A000 before anything runs.
--
--   2. The transaction is read-only for the duration of the call, so Postgres
--      rejects any write that reaches execution — a volatile function that
--      writes, for instance, which parses perfectly well as a subquery and so
--      passes control 1 untouched.
--
-- Neither control depends on recognising what the query *says*, which is the
-- approach the PRD rules out: no keyword list, no regex for the word DELETE.
--
-- Also capped: a statement timeout so a bad query cannot pin the database,
-- and a row limit so a careless SELECT * cannot return the whole events table
-- to a browser.
--
-- Callers are gated separately: the admin_query edge function checks the
-- ADMIN_EMAILS allowlist before it ever reaches this function. EXECUTE is
-- granted to service_role only — never to anon or authenticated — so this is
-- not reachable from a browser with an ordinary JWT.
-- ============================================================================

CREATE OR REPLACE FUNCTION admin_run_select(
    p_query      TEXT,
    p_max_rows   INTEGER DEFAULT 500,
    p_timeout_ms INTEGER DEFAULT 5000
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
-- A function-level SET is saved and restored around the call. SET LOCAL would
-- have leaked read-only to the rest of the caller's transaction, which is
-- harmless per-request under PostgREST but would break any transaction that
-- calls this and then writes.
SET transaction_read_only = on
AS $$
DECLARE
    v_rows     JSONB;
    v_started  TIMESTAMPTZ := clock_timestamp();
    v_limit    INTEGER := least(greatest(coalesce(p_max_rows, 500), 1), 5000);
    v_timeout  INTEGER := least(greatest(coalesce(p_timeout_ms, 5000), 100), 15000);
BEGIN
    IF p_query IS NULL OR btrim(p_query) = '' THEN
        RETURN jsonb_build_object('error', 'Empty query');
    END IF;

    -- Control 2 is armed by the SET clause above, before the body runs.
    PERFORM set_config('statement_timeout', v_timeout::TEXT, true);

    -- Control 1. The %s lands inside a FROM subquery, so a trailing statement
    -- cannot parse. The extra LIMIT bounds the result even if the caller's own
    -- query has none.
    EXECUTE format(
        'SELECT coalesce(jsonb_agg(to_jsonb(t)), ''[]''::jsonb) FROM (SELECT * FROM (%s) q LIMIT %s) t',
        p_query, v_limit
    ) INTO v_rows;

    RETURN jsonb_build_object(
        'rows', v_rows,
        'row_count', jsonb_array_length(v_rows),
        -- Equality means the cap was probably hit; the caller should narrow.
        'truncated', jsonb_array_length(v_rows) >= v_limit,
        'elapsed_ms', round(extract(epoch FROM (clock_timestamp() - v_started)) * 1000)
    );
EXCEPTION
    WHEN OTHERS THEN
        -- The message is the whole point of an escape hatch: a bad query has
        -- to say why. The two flags distinguish "you tried to write" from
        -- "your query is wrong", which are very different things to see:
        --   25006  a write reached execution and the read-only transaction
        --          refused it (control 2)
        --   0A000  a data-modifying CTE was nested by the wrapper and Postgres
        --          refused to plan it (control 1)
        RETURN jsonb_build_object(
            'error', SQLERRM,
            'sqlstate', SQLSTATE,
            'read_only_violation', SQLSTATE = '25006',
            'write_blocked', SQLSTATE IN ('25006', '0A000')
        );
END;
$$;

REVOKE ALL ON FUNCTION admin_run_select(TEXT, INTEGER, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION admin_run_select(TEXT, INTEGER, INTEGER) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION admin_run_select(TEXT, INTEGER, INTEGER) TO service_role;

COMMENT ON FUNCTION admin_run_select IS
    'Read-only SQL for the admin dashboard. SELECT-only is enforced by a read-only transaction plus subquery wrapping, not by string matching. service_role only; callers are gated by ADMIN_EMAILS in the admin_query edge function.';

-- Prove the controls hold at migration time rather than trusting them.
DO $$
DECLARE
    r JSONB;
BEGIN
    r := admin_run_select('SELECT 1 AS n');
    IF r->'rows'->0->>'n' IS DISTINCT FROM '1' THEN
        RAISE EXCEPTION 'admin_run_select failed a trivial SELECT: %', r;
    END IF;

    -- Control 2 is armed. Asserted directly rather than inferred from a write
    -- that fails, because a write can fail for more than one reason and then
    -- the test passes without the control being on at all.
    r := admin_run_select('SELECT current_setting(''transaction_read_only'') AS ro');
    IF r->'rows'->0->>'ro' IS DISTINCT FROM 'on' THEN
        RAISE EXCEPTION 'admin_run_select did not enter a read-only transaction: %', r;
    END IF;

    -- Control 1. A data-modifying CTE must be rejected. Postgres refuses it
    -- with 0A000 ("WITH clause containing a data-modifying statement must be
    -- at the top level") because the wrapper nests it, so it never reaches the
    -- read-only check. Assert only that it is BLOCKED — pinning the test to
    -- one SQLSTATE asserts which control fired, which is not the guarantee
    -- anyone depends on.
    r := admin_run_select(
        'WITH d AS (DELETE FROM lifecycle_emails WHERE false RETURNING 1 AS n) SELECT * FROM d');
    IF r->>'error' IS NULL THEN
        RAISE EXCEPTION 'admin_run_select did NOT block a data-modifying CTE: %', r;
    END IF;
    RAISE NOTICE 'data-modifying CTE blocked with SQLSTATE %', r->>'sqlstate';

    -- A plain write, which parses as neither a subquery nor a CTE.
    r := admin_run_select('DELETE FROM lifecycle_emails WHERE false');
    IF r->>'error' IS NULL THEN
        RAISE EXCEPTION 'admin_run_select did NOT block a bare DELETE: %', r;
    END IF;

    RAISE NOTICE 'admin_run_select: SELECT works, read-only armed, writes blocked';
END $$;
