-- ============================================================================
-- Enable RLS on user_agreements and idempotency_keys
-- Migration: 061_enable_rls_agreements_and_idempotency.sql
--
-- Both tables are in the exposed public schema with RLS off and
-- GRANT ALL to anon and authenticated (arwdDxtm: SELECT, INSERT, UPDATE,
-- DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN). The public anon key
-- can read, write, and truncate them. Postgres does not apply RLS to
-- TRUNCATE, so enabling RLS without revoking those grants would leave
-- truncate in place, and a SELECT would still succeed.
--
-- user_agreements: migration 003 enabled RLS and added own-row policies.
-- RLS was turned off out of band. The 003 policies are still present and
-- inert, and the dashboard added a second pair that does the same check
-- ("Users can read own agreements", "Users can insert own agreements").
-- This turns RLS back on, keeps the 003 policies, drops the duplicates,
-- and leaves authenticated with SELECT and INSERT only. No UPDATE or
-- DELETE policy: agreement rows are immutable. service_role already has
-- GRANT ALL and is not revoked.
--
-- idempotency_keys: migration 004 says service-role only and never enabled
-- RLS or revoked grants. RLS is enabled here with no policies, and anon
-- and authenticated lose every grant. RLS is not FORCE'd. service_role
-- has BYPASSRLS and keeps its grant, which is how
-- supabase/functions/_shared/idempotency.ts reaches this table
-- (createServiceClient). A user or anon policy is intentionally not added.
--
-- Re-runnable. CREATE POLICY has no OR REPLACE, so the kept policies are
-- dropped and recreated. ENABLE / NO FORCE / REVOKE / GRANT are idempotent.
-- The first apply enables RLS only after those policies exist. If a re-run
-- stops between that drop and the create, run the file again. The closing
-- block checks the end state and writes no rows.
--
-- Not applied by this change. Apply it in the SQL editor after review.
-- Rollback SQL is in the pull request, not in this file, so it cannot run
-- by accident.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- user_agreements
-- ----------------------------------------------------------------------------

-- Dashboard duplicates of the 003 policies. PERMISSIVE policies are OR'd,
-- so leaving them would keep a second copy of the same rule.
DROP POLICY IF EXISTS "Users can read own agreements" ON public.user_agreements;
DROP POLICY IF EXISTS "Users can insert own agreements" ON public.user_agreements;

-- Any other policy on this table is not part of the intended access model.
DO $$
DECLARE
    pol record;
BEGIN
    FOR pol IN
        SELECT policyname
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'user_agreements'
          AND policyname NOT IN (
              'user_agreements_select_own',
              'user_agreements_insert_own'
          )
    LOOP
        EXECUTE format(
            'DROP POLICY IF EXISTS %I ON public.user_agreements',
            pol.policyname
        );
    END LOOP;
END $$;

DROP POLICY IF EXISTS user_agreements_select_own ON public.user_agreements;
CREATE POLICY user_agreements_select_own ON public.user_agreements
    FOR SELECT
    USING (user_id = auth.uid());

DROP POLICY IF EXISTS user_agreements_insert_own ON public.user_agreements;
CREATE POLICY user_agreements_insert_own ON public.user_agreements
    FOR INSERT
    WITH CHECK (user_id = auth.uid());

COMMENT ON POLICY user_agreements_select_own ON public.user_agreements IS
    'Users can only read their own agreement records';
COMMENT ON POLICY user_agreements_insert_own ON public.user_agreements IS
    'Users can only insert their own agreement records';

ALTER TABLE IF EXISTS public.user_agreements ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.user_agreements NO FORCE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.user_agreements FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT ON TABLE public.user_agreements TO authenticated;

-- ----------------------------------------------------------------------------
-- idempotency_keys
-- ----------------------------------------------------------------------------

DO $$
DECLARE
    pol record;
BEGIN
    FOR pol IN
        SELECT policyname
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'idempotency_keys'
    LOOP
        EXECUTE format(
            'DROP POLICY IF EXISTS %I ON public.idempotency_keys',
            pol.policyname
        );
    END LOOP;
END $$;

ALTER TABLE IF EXISTS public.idempotency_keys ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.idempotency_keys NO FORCE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.idempotency_keys FROM PUBLIC, anon, authenticated;

-- ----------------------------------------------------------------------------
-- End state. Reads catalog and privilege flags only; writes no rows.
-- ----------------------------------------------------------------------------

DO $$
DECLARE
    v_rls boolean;
    v_forced boolean;
    v_qual text;
    v_check text;
    v_count int;
    v_priv text;
BEGIN
    SELECT c.relrowsecurity, c.relforcerowsecurity
      INTO v_rls, v_forced
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public'
       AND c.relname = 'user_agreements';
    IF v_rls IS NOT TRUE OR v_forced IS NOT FALSE THEN
        RAISE EXCEPTION
            'user_agreements RLS end state is rls=%, forced=%', v_rls, v_forced;
    END IF;

    SELECT c.relrowsecurity, c.relforcerowsecurity
      INTO v_rls, v_forced
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public'
       AND c.relname = 'idempotency_keys';
    IF v_rls IS NOT TRUE OR v_forced IS NOT FALSE THEN
        RAISE EXCEPTION
            'idempotency_keys RLS end state is rls=%, forced=%', v_rls, v_forced;
    END IF;

    SELECT count(*) INTO v_count
      FROM pg_policies
     WHERE schemaname = 'public'
       AND tablename = 'user_agreements';
    IF v_count <> 2 THEN
        RAISE EXCEPTION 'user_agreements has % policies, expected 2', v_count;
    END IF;

    SELECT qual INTO v_qual
      FROM pg_policies
     WHERE schemaname = 'public'
       AND tablename = 'user_agreements'
       AND policyname = 'user_agreements_select_own'
       AND cmd = 'SELECT';
    IF regexp_replace(coalesce(v_qual, ''), '\s+', '', 'g')
       NOT IN ('(user_id=auth.uid())', '((user_id=auth.uid()))') THEN
        RAISE EXCEPTION 'user_agreements_select_own qual is %', v_qual;
    END IF;

    SELECT with_check INTO v_check
      FROM pg_policies
     WHERE schemaname = 'public'
       AND tablename = 'user_agreements'
       AND policyname = 'user_agreements_insert_own'
       AND cmd = 'INSERT';
    IF regexp_replace(coalesce(v_check, ''), '\s+', '', 'g')
       NOT IN ('(user_id=auth.uid())', '((user_id=auth.uid()))') THEN
        RAISE EXCEPTION 'user_agreements_insert_own check is %', v_check;
    END IF;

    SELECT count(*) INTO v_count
      FROM pg_policies
     WHERE schemaname = 'public'
       AND tablename = 'user_agreements'
       AND cmd IN ('UPDATE', 'DELETE', 'ALL');
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'user_agreements still has an UPDATE, DELETE, or ALL policy';
    END IF;

    SELECT count(*) INTO v_count
      FROM pg_policies
     WHERE schemaname = 'public'
       AND tablename = 'idempotency_keys';
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'idempotency_keys still has % policies', v_count;
    END IF;

    FOREACH v_priv IN ARRAY ARRAY[
        'SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE',
        'REFERENCES', 'TRIGGER', 'MAINTAIN'
    ]
    LOOP
        IF has_table_privilege('anon', 'public.user_agreements', v_priv) THEN
            RAISE EXCEPTION 'anon still has % on user_agreements', v_priv;
        END IF;
        IF has_table_privilege('anon', 'public.idempotency_keys', v_priv) THEN
            RAISE EXCEPTION 'anon still has % on idempotency_keys', v_priv;
        END IF;
        IF has_table_privilege('authenticated', 'public.idempotency_keys', v_priv) THEN
            RAISE EXCEPTION 'authenticated still has % on idempotency_keys', v_priv;
        END IF;
        IF has_table_privilege('service_role', 'public.idempotency_keys', v_priv) IS NOT TRUE THEN
            RAISE EXCEPTION 'service_role lost % on idempotency_keys', v_priv;
        END IF;
        IF has_table_privilege('service_role', 'public.user_agreements', v_priv) IS NOT TRUE THEN
            RAISE EXCEPTION 'service_role lost % on user_agreements', v_priv;
        END IF;
    END LOOP;

    IF NOT (
        has_table_privilege('authenticated', 'public.user_agreements', 'SELECT')
        AND has_table_privilege('authenticated', 'public.user_agreements', 'INSERT')
    ) THEN
        RAISE EXCEPTION 'authenticated is missing SELECT or INSERT on user_agreements';
    END IF;

    FOREACH v_priv IN ARRAY ARRAY[
        'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER', 'MAINTAIN'
    ]
    LOOP
        IF has_table_privilege('authenticated', 'public.user_agreements', v_priv) THEN
            RAISE EXCEPTION 'authenticated still has % on user_agreements', v_priv;
        END IF;
    END LOOP;

    IF NOT (
        SELECT rolbypassrls FROM pg_roles WHERE rolname = 'service_role'
    ) THEN
        RAISE EXCEPTION 'service_role no longer bypasses RLS';
    END IF;
END $$;
