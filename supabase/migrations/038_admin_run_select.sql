-- ============================================================================
-- 038 — Read-only SQL escape hatch for the admin dashboard (PRD US-006)
--
-- The admin browser covers the common questions. This exists for the ones it
-- does not, so the tool never dead-ends.
--
-- SELECT-ONLY IS ENFORCED, NOT INSPECTED. Two independent controls, because
-- either one alone has a known hole:
--
--   1. The query is wrapped as a subquery: SELECT ... FROM ( <query> ) sub.
--      A second statement is then a syntax error rather than a second
--      statement, so `; DROP TABLE x` cannot be smuggled in. This alone is
--      NOT sufficient: Postgres permits data-modifying CTEs, and
--        WITH d AS (DELETE FROM t RETURNING *) SELECT * FROM d
--      is a perfectly legal subquery.
--
--   2. The transaction is switched to read-only before the query runs, so
--      Postgres itself rejects every write path — including the CTE above,
--      which control 1 lets through. This is the control that actually holds;
--      string matching for the word 'delete' would not have caught it, which
--      is why the PRD rules that approach out.
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

    -- Control 2. Must happen before the query executes. Postgres raises
    -- "cannot execute INSERT in a read-only transaction" for any write, so
    -- correctness here does not depend on recognising what the query is.
    SET LOCAL transaction_read_only = ON;
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
        -- to say why. SQLSTATE 25006 is the read-only rejection.
        RETURN jsonb_build_object(
            'error', SQLERRM,
            'sqlstate', SQLSTATE,
            'read_only_violation', SQLSTATE = '25006'
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

    -- A data-modifying CTE is a legal subquery, so control 1 lets it parse.
    -- Control 2 must be what stops it.
    r := admin_run_select(
        'WITH d AS (DELETE FROM lifecycle_emails WHERE false RETURNING 1 AS n) SELECT * FROM d');
    IF coalesce((r->>'read_only_violation')::BOOLEAN, false) IS NOT TRUE THEN
        RAISE EXCEPTION 'admin_run_select did NOT block a data-modifying CTE: %', r;
    END IF;

    RAISE NOTICE 'admin_run_select: SELECT works, data-modifying CTE blocked';
END $$;
