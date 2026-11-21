-- Roll back supabase/migrations/068_lock_settlement_rpcs.sql.
--
-- Restores EXECUTE for PUBLIC, anon, and authenticated on the five
-- settlement functions, removes the in-function guard, and puts the
-- function default privileges back. It does not insert, update, or delete
-- rows. Run it only to undo 068. After it, the anon key can settle bets
-- again.
--
-- Run the file in one transaction (psql --single-transaction, or a single
-- paste). Re-running it is safe: a function that no longer has the guard
-- is left as it is, and the grants are the same the second time.

DO $lock$
DECLARE
    proc regprocedure;
    def text;
    stripped text;
    marker constant text := 'PERFORM public.assert_settlement_service_role();';
BEGIN
    PERFORM set_config('search_path', 'public', true);

    FOR proc IN
        SELECT p.oid::regprocedure
          FROM pg_proc p
          JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public'
           AND p.proname IN (
               'settle_bet_tx',
               'settle_parlay_tx',
               'override_grade_tx',
               'reverse_settlement_tx',
               'mark_ticket_settled'
           )
         ORDER BY p.proname
    LOOP
        def := pg_get_functiondef(proc);
        IF position(marker IN def) = 0 THEN
            CONTINUE;
        END IF;

        stripped := regexp_replace(
            def,
            E'\n[ \t]*PERFORM public\\.assert_settlement_service_role\\(\\);',
            '',
            'g'
        );

        IF position(marker IN stripped) > 0 THEN
            RAISE EXCEPTION '068 rollback: guard still present in %', proc;
        END IF;

        EXECUTE stripped;
    END LOOP;
END
$lock$;

DO $lock$
DECLARE
    proc regprocedure;
    role_name text;
BEGIN
    PERFORM set_config('search_path', 'public', true);

    FOR proc IN
        SELECT p.oid::regprocedure
          FROM pg_proc p
          JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public'
           AND p.proname IN (
               'settle_bet_tx',
               'settle_parlay_tx',
               'override_grade_tx',
               'reverse_settlement_tx',
               'mark_ticket_settled'
           )
    LOOP
        EXECUTE format(
            'GRANT EXECUTE ON FUNCTION %s TO PUBLIC, anon, authenticated, service_role',
            proc
        );
    END LOOP;

    FOREACH role_name IN ARRAY ARRAY['postgres', 'supabase_admin']
    LOOP
        IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = role_name) THEN
            EXECUTE format(
                'ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO PUBLIC, anon, authenticated',
                role_name
            );
        END IF;
    END LOOP;

    IF current_user NOT IN ('postgres', 'supabase_admin') THEN
        EXECUTE 'ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO PUBLIC, anon, authenticated';
    END IF;
END
$lock$;

DROP EVENT TRIGGER IF EXISTS revoke_public_execute_on_function;
DROP FUNCTION IF EXISTS public.revoke_public_execute_on_function();
DROP FUNCTION IF EXISTS public.assert_settlement_service_role();
