-- ============================================================================
-- 038 — Read-only SQL escape hatch for the admin dashboard (PRD US-006)
--
-- The admin browser covers the common questions. This exists for the ones it
-- does not, so the tool never dead-ends.
--
-- SELECT-ONLY IS ENFORCED STRUCTURALLY, NOT BY STRING MATCHING.
--
-- The query is wrapped as a subquery: SELECT ... FROM ( <query> ) q. That is
-- not cosmetic — it is the control, and it is a parser-level one:
--
--   * a trailing statement (`; DROP TABLE x`) is a syntax error, not a second
--     statement
--   * INSERT / UPDATE / DELETE / TRUNCATE are not valid in a FROM subquery
--   * DDL likewise
--   * a data-modifying CTE is rejected with 0A000, because Postgres requires a
--     WITH clause containing INSERT/UPDATE/DELETE to be at the TOP level, and
--     the wrapper nests it
--
-- No keyword list, no regex for the word DELETE — the PRD rules that out and
-- it would be the weakest part of this if it were here.
--
-- WHAT THIS DOES NOT YET STOP, stated plainly rather than glossed:
-- `SELECT some_function_that_writes()` parses as a legal subquery. The PRD
-- asks for a read-only connection or role as the second control for exactly
-- this case. It is NOT implemented here, because the obvious mechanism does
-- not exist: Postgres refuses `SET transaction_read_only` inside a function
-- ("cannot be set locally in functions"), as either SET LOCAL or a
-- function-level SET clause. A role- or connection-level control is the
-- remaining option and is deliberately left to its own migration rather than
-- guessed at here.
--
-- Until then the exposure is: an allowlisted operator could deliberately call
-- a writing function. That is not privilege escalation — ADMIN_EMAILS already
-- gates who reaches this at all, and EXECUTE is granted to service_role only,
-- never to anon or authenticated.
--
-- Also capped: a statement timeout so a bad query cannot pin the database,
-- and a row limit so a careless SELECT * cannot return the whole events table
-- to a browser.
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

    -- statement_timeout is set locally, which IS permitted for this GUC.
    PERFORM set_config('statement_timeout', v_timeout::TEXT, true);

    -- The %s lands inside a FROM subquery — see the header; this is the
    -- control, not a formatting convenience. The extra LIMIT bounds the result
    -- even when the caller's own query has none.
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
        -- to say why. `write_blocked` separates "you tried to write" from
        -- "your query is wrong", which are very different things to read.
        -- 42601 belongs in that set: a bare DELETE nested in the wrapper is
        -- reported as a syntax error, and calling that a typo would be
        -- misleading — it is the control working.
        --   42601  a write shape could not parse inside the subquery wrapper
        --   0A000  a data-modifying CTE was nested and Postgres refused it
        --   25006  a write reached execution in a read-only transaction
        RETURN jsonb_build_object(
            'error', SQLERRM,
            'sqlstate', SQLSTATE,
            'write_blocked', SQLSTATE IN ('42601', '0A000', '25006')
        );
END;
$$;

REVOKE ALL ON FUNCTION admin_run_select(TEXT, INTEGER, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION admin_run_select(TEXT, INTEGER, INTEGER) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION admin_run_select(TEXT, INTEGER, INTEGER) TO service_role;

COMMENT ON FUNCTION admin_run_select IS
    'Read-only SQL for the admin dashboard. Writes are blocked structurally: the query is wrapped as a FROM subquery, where DML, DDL, a trailing statement and a data-modifying CTE are all rejected by the parser. Not enforced by string matching. A volatile function that writes is NOT yet blocked — see the migration header. service_role only; callers gated by ADMIN_EMAILS in the admin_query edge function.';

-- Assert the control at apply time rather than trusting it. Each of these is
-- a shape that must not execute; the SQLSTATE that stops it is Postgres's
-- business, so the test checks only that an error came back.
DO $$
DECLARE
    r JSONB;
    v_case TEXT;
BEGIN
    r := admin_run_select('SELECT 1 AS n');
    IF r->'rows'->0->>'n' IS DISTINCT FROM '1' THEN
        RAISE EXCEPTION 'admin_run_select failed a trivial SELECT: %', r;
    END IF;

    FOREACH v_case IN ARRAY ARRAY[
        'DELETE FROM lifecycle_emails WHERE false',
        'UPDATE bookies SET name = name WHERE false',
        'INSERT INTO lifecycle_emails (user_id) SELECT NULL WHERE false',
        'WITH d AS (DELETE FROM lifecycle_emails WHERE false RETURNING 1 AS n) SELECT * FROM d',
        'SELECT 1; DROP TABLE lifecycle_emails',
        'CREATE TABLE should_not_exist (id int)'
    ] LOOP
        r := admin_run_select(v_case);
        IF r->>'error' IS NULL THEN
            RAISE EXCEPTION 'admin_run_select did NOT block: % -> %', v_case, r;
        END IF;
        RAISE NOTICE 'blocked [%] %', r->>'sqlstate', left(v_case, 40);
    END LOOP;

    IF to_regclass('public.should_not_exist') IS NOT NULL THEN
        RAISE EXCEPTION 'a CREATE TABLE got through admin_run_select';
    END IF;

    RAISE NOTICE 'admin_run_select: SELECT works, six write shapes blocked';
END $$;
