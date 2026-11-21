-- Lock the settlement RPCs to service_role.
--
-- settle_bet_tx, settle_parlay_tx, override_grade_tx, reverse_settlement_tx,
-- and mark_ticket_settled are SECURITY DEFINER and run as their owner. A
-- REVOKE FROM PUBLIC does not remove them from the public API: Supabase's
-- default privileges grant EXECUTE to anon and authenticated by name, and
-- those named grants are what has_function_privilege still sees. Anyone
-- holding the anon key could call them through PostgREST and settle,
-- override, or reverse any bet.
--
-- This migration does not insert, update, or delete rows. It does not
-- replace the settlement logic. It injects one guard call at the start of
-- each existing body, then revokes the client grants. Re-running it is safe.
-- If a later migration replaces one of these bodies, run this file again:
-- CREATE OR REPLACE keeps the grants and drops the injected guard.
--
-- Apply only after all five functions exist (migration 063). No edge
-- function deploy is required: every app caller already uses service_role.

-- ---------------------------------------------------------------------------
-- The five signatures this lockdown covers. An unexpected overload, or a
-- missing one, stops the migration instead of locking the wrong set.
-- ---------------------------------------------------------------------------

DO $lock$
DECLARE
    expected text[] := ARRAY[
        'public.mark_ticket_settled(uuid,timestamptz)',
        'public.override_grade_tx(uuid,uuid,text,text,text)',
        'public.reverse_settlement_tx(uuid,uuid,text,text)',
        'public.settle_bet_tx(uuid,uuid,text,text)',
        'public.settle_parlay_tx(uuid,uuid,text,text,numeric,text,jsonb)'
    ];
    missing text;
    role_name text;
    found_count integer;
BEGIN
    FOREACH role_name IN ARRAY ARRAY['anon', 'authenticated', 'service_role']
    LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = role_name) THEN
            RAISE EXCEPTION '068 requires role %', role_name;
        END IF;
    END LOOP;

    FOREACH missing IN ARRAY expected
    LOOP
        IF to_regprocedure(missing) IS NULL THEN
            RAISE EXCEPTION
                '068 requires %. Apply migration 063 first if it is not already on this database',
                missing;
        END IF;
    END LOOP;

    SELECT count(*)
      INTO found_count
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname IN (
           'settle_bet_tx',
           'settle_parlay_tx',
           'override_grade_tx',
           'reverse_settlement_tx',
           'mark_ticket_settled'
       );

    IF found_count <> cardinality(expected) THEN
        RAISE EXCEPTION
            '068 expected % settlement functions and found %',
            cardinality(expected), found_count;
    END IF;
END
$lock$;

-- ---------------------------------------------------------------------------
-- Future functions created by the migration roles in public. Existing
-- functions are not touched here. anon and authenticated stop receiving
-- a named EXECUTE grant. service_role keeps its default grant, so a new
-- edge-function RPC still runs. Tables and sequences are not changed.
--
-- The named revoke is not enough on its own. PostgreSQL hard-wires EXECUTE
-- to PUBLIC, and ALTER DEFAULT PRIVILEGES REVOKE EXECUTE FROM PUBLIC does
-- not stick: an empty default ACL is stored as NULL and the hard-wired
-- grant comes back. The event trigger below revokes PUBLIC on CREATE
-- FUNCTION in public, including CREATE OR REPLACE. It does not touch a
-- named anon or authenticated grant, so replacing a client RPC keeps the
-- grant that migration already gave it. A new function has neither, and
-- anon cannot call it. A client RPC added later has to GRANT EXECUTE
-- itself. Forgetting the grant fails closed.
-- ---------------------------------------------------------------------------

DO $lock$
DECLARE
    role_name text;
BEGIN
    FOREACH role_name IN ARRAY ARRAY['postgres', 'supabase_admin']
    LOOP
        IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = role_name) THEN
            EXECUTE format(
                'ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated',
                role_name
            );
        END IF;
    END LOOP;

    IF current_user NOT IN ('postgres', 'supabase_admin') THEN
        EXECUTE 'ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated';
    END IF;
END
$lock$;

-- ---------------------------------------------------------------------------
-- Defense in depth. PostgREST connects as authenticator and switches to the
-- JWT role, so session_user stays authenticator and the claim says
-- service_role. Direct SQL from postgres or supabase_admin has no JWT and
-- is the path the settlement checks use. Any other caller raises 42501
-- even if EXECUTE is granted again.
--
-- The GUC is set by PostgREST from the key. It is not a second lock against
-- someone who can already run SQL as authenticator and set the GUC. The
-- revoke above is the lock. anon and authenticated are NOLOGIN.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.assert_settlement_service_role()
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $fn$
DECLARE
    v_role text;
    v_claims text;
BEGIN
    v_role := nullif(current_setting('request.jwt.claim.role', true), '');
    IF v_role IS NULL THEN
        v_claims := nullif(current_setting('request.jwt.claims', true), '');
        IF v_claims IS NOT NULL THEN
            BEGIN
                v_role := v_claims::json->>'role';
            EXCEPTION
                WHEN invalid_text_representation THEN
                    v_role := NULL;
            END;
        END IF;
    END IF;

    IF session_user IN ('postgres', 'supabase_admin') THEN
        RETURN;
    END IF;

    IF session_user = 'authenticator' AND v_role = 'service_role' THEN
        RETURN;
    END IF;

    RAISE EXCEPTION 'settlement RPC requires service_role'
        USING ERRCODE = '42501';
END;
$fn$;

REVOKE ALL ON FUNCTION public.assert_settlement_service_role() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.assert_settlement_service_role() FROM anon, authenticated, service_role;

DO $lock$
DECLARE
    owner_name text;
BEGIN
    FOR owner_name IN
        SELECT DISTINCT pg_get_userbyid(p.proowner)
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
            'GRANT EXECUTE ON FUNCTION public.assert_settlement_service_role() TO %I',
            owner_name
        );
    END LOOP;
END
$lock$;

-- ---------------------------------------------------------------------------
-- Put the guard on the first line of each body. pg_get_functiondef keeps
-- the live settlement logic, including a body that has drifted from this
-- repo. The first line that is only BEGIN is the function body; nested
-- blocks come later and are left alone. A re-run sees the marker and skips.
-- ---------------------------------------------------------------------------

DO $lock$
DECLARE
    proc regprocedure;
    def text;
    injected text;
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
        IF position(marker IN def) > 0 THEN
            CONTINUE;
        END IF;

        injected := regexp_replace(
            def,
            '^([ \t]*)BEGIN[ \t]*$',
            E'\\1BEGIN\n\\1    ' || marker,
            'n'
        );

        IF injected = def OR position(marker IN injected) = 0 THEN
            RAISE EXCEPTION '068: could not inject service_role guard into %', proc;
        END IF;

        IF (length(injected) - length(replace(injected, marker, '')))
           / length(marker) <> 1 THEN
            RAISE EXCEPTION '068: guard would be inserted more than once into %', proc;
        END IF;

        EXECUTE injected;
        EXECUTE format('ALTER FUNCTION %s SET search_path = public', proc);
    END LOOP;
END
$lock$;

CREATE OR REPLACE FUNCTION public.revoke_public_execute_on_function()
RETURNS event_trigger
LANGUAGE plpgsql
SET search_path = public
AS $fn$
DECLARE
    obj record;
BEGIN
    FOR obj IN
        SELECT object_identity
          FROM pg_event_trigger_ddl_commands()
         WHERE command_tag = 'CREATE FUNCTION'
           AND schema_name = 'public'
    LOOP
        EXECUTE format(
            'REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC',
            obj.object_identity
        );
    END LOOP;
END;
$fn$;

DROP EVENT TRIGGER IF EXISTS revoke_public_execute_on_function;
CREATE EVENT TRIGGER revoke_public_execute_on_function
    ON ddl_command_end
    WHEN TAG IN ('CREATE FUNCTION')
    EXECUTE FUNCTION public.revoke_public_execute_on_function();

REVOKE ALL ON FUNCTION public.revoke_public_execute_on_function()
    FROM PUBLIC, anon, authenticated, service_role;

-- Grant first, then revoke. A crash between the two leaves service_role
-- able to call. Revoking PUBLIC does not remove the named service_role
-- grant, and granting it here covers a function that only had PUBLIC.

DO $lock$
DECLARE
    proc regprocedure;
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
        EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', proc);
        EXECUTE format(
            'REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated',
            proc
        );
    END LOOP;
END
$lock$;

DO $lock$
DECLARE
    bad text;
BEGIN
    SELECT string_agg(
               n.nspname || '.' || p.oid::regprocedure::text,
               ', ' ORDER BY p.oid::regprocedure::text
           )
      INTO bad
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
       AND (
           has_function_privilege('anon', p.oid, 'EXECUTE')
           OR has_function_privilege('authenticated', p.oid, 'EXECUTE')
           OR NOT has_function_privilege('service_role', p.oid, 'EXECUTE')
           OR position(
               'PERFORM public.assert_settlement_service_role();'
               IN pg_get_functiondef(p.oid)
           ) = 0
       );

    IF bad IS NOT NULL THEN
        RAISE EXCEPTION '068 privilege or guard check failed for %', bad;
    END IF;
END
$lock$;
