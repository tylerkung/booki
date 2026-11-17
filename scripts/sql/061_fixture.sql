-- Throwaway reproduction of the production shape for migration 061.
-- Local Postgres only. Never point this at a hosted database.
--
-- Matches what was read from prod on 2026-11-17:
--   RLS off, not forced
--   GRANT ALL to anon, authenticated, and service_role
--   003 policies (TO PUBLIC) plus the two dashboard duplicates (TO authenticated)
--   a few seeded rows

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
        CREATE ROLE anon NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
        CREATE ROLE authenticated NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
        CREATE ROLE service_role NOLOGIN BYPASSRLS;
    END IF;
END $$;

ALTER ROLE service_role BYPASSRLS;
ALTER ROLE anon NOBYPASSRLS;
ALTER ROLE authenticated NOBYPASSRLS;

CREATE SCHEMA IF NOT EXISTS auth;

-- Supabase reads the sub claim. The uuid cast is what makes
-- `user_id = auth.uid()` type-check; the claim access itself is the
-- expression this harness was asked to use.
CREATE OR REPLACE FUNCTION auth.uid()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
    SELECT ((NULLIF(current_setting('request.jwt.claims', true), '')::json)->>'sub')::uuid
$$;

GRANT USAGE ON SCHEMA auth TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION auth.uid() TO anon, authenticated, service_role;

CREATE TABLE IF NOT EXISTS auth.users (
    id uuid PRIMARY KEY
);

-- From 003_user_agreements.sql
CREATE TABLE IF NOT EXISTS public.user_agreements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('bookie', 'player')),
    version TEXT NOT NULL,
    accepted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ip_address TEXT,
    user_agent TEXT
);

CREATE INDEX IF NOT EXISTS idx_user_agreements_user_id ON public.user_agreements(user_id);
CREATE INDEX IF NOT EXISTS idx_user_agreements_version ON public.user_agreements(version);

-- From 004_idempotency_keys.sql
CREATE TABLE IF NOT EXISTS public.idempotency_keys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    key TEXT NOT NULL,
    operation TEXT NOT NULL,
    response TEXT NOT NULL,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '24 hours'),
    UNIQUE(key, operation)
);

CREATE INDEX IF NOT EXISTS idx_idempotency_keys_key_operation
    ON public.idempotency_keys(key, operation);
CREATE INDEX IF NOT EXISTS idx_idempotency_keys_expires_at
    ON public.idempotency_keys(expires_at);

-- 003 policies. Created while RLS is off, which is how they sit in prod:
-- present, and inert until 061 turns RLS on.
DROP POLICY IF EXISTS user_agreements_select_own ON public.user_agreements;
CREATE POLICY user_agreements_select_own ON public.user_agreements
    FOR SELECT
    USING (user_id = auth.uid());

DROP POLICY IF EXISTS user_agreements_insert_own ON public.user_agreements;
CREATE POLICY user_agreements_insert_own ON public.user_agreements
    FOR INSERT
    WITH CHECK (user_id = auth.uid());

-- Dashboard duplicates, TO authenticated, same check with the operands swapped.
DROP POLICY IF EXISTS "Users can read own agreements" ON public.user_agreements;
CREATE POLICY "Users can read own agreements" ON public.user_agreements
    FOR SELECT
    TO authenticated
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own agreements" ON public.user_agreements;
CREATE POLICY "Users can insert own agreements" ON public.user_agreements
    FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = user_id);

ALTER TABLE public.user_agreements DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_agreements NO FORCE ROW LEVEL SECURITY;
ALTER TABLE public.idempotency_keys DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.idempotency_keys NO FORCE ROW LEVEL SECURITY;

GRANT ALL ON TABLE public.user_agreements TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.idempotency_keys TO anon, authenticated, service_role;

INSERT INTO auth.users (id) VALUES
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
    ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.user_agreements (user_id, role, version) VALUES
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'player', '1.0'),
    ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'bookie', '1.0');

INSERT INTO public.idempotency_keys (key, operation, response, user_id) VALUES
    ('seed-a', 'submit_bet', '{"cached":"a"}', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
    ('seed-b', 'create_invite', '{"cached":"b"}', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
