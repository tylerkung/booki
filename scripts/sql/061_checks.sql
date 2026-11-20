-- Behavioral checks for migration 061. Runs as the table owner (postgres)
-- and switches role inside each block. Expected denials must be privilege
-- errors (42501, and not the row-level security wording): 061 revokes the
-- grants, it does not rely on an empty RLS result.

CREATE OR REPLACE FUNCTION pg_temp.expect_denied(p_role text, p_sql text, p_label text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    EXECUTE format('SET LOCAL ROLE %I', p_role);
    BEGIN
        EXECUTE p_sql;
        RAISE EXCEPTION '% unexpectedly succeeded', p_label;
    EXCEPTION
        WHEN insufficient_privilege THEN
            IF SQLERRM ILIKE '%row-level security%' THEN
                RAISE EXCEPTION '% was denied by RLS instead of a missing grant: %', p_label, SQLERRM;
            END IF;
            RAISE NOTICE 'PASS % — %', p_label, SQLERRM;
    END;
    EXECUTE 'RESET ROLE';
END;
$$;

SELECT set_config(
    'request.jwt.claims',
    '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","role":"anon"}',
    true
);

SELECT pg_temp.expect_denied('anon', 'SELECT 1 FROM public.user_agreements', 'anon SELECT user_agreements');
SELECT pg_temp.expect_denied('anon', $$INSERT INTO public.user_agreements (user_id, role, version) VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'player', 'anon')$$, 'anon INSERT user_agreements');
SELECT pg_temp.expect_denied('anon', $$UPDATE public.user_agreements SET version = 'anon'$$, 'anon UPDATE user_agreements');
SELECT pg_temp.expect_denied('anon', 'DELETE FROM public.user_agreements', 'anon DELETE user_agreements');
SELECT pg_temp.expect_denied('anon', 'TRUNCATE public.user_agreements', 'anon TRUNCATE user_agreements');

SELECT pg_temp.expect_denied('anon', 'SELECT 1 FROM public.idempotency_keys', 'anon SELECT idempotency_keys');
SELECT pg_temp.expect_denied('anon', $$INSERT INTO public.idempotency_keys (key, operation, response) VALUES ('anon', 'submit_bet', '{}')$$, 'anon INSERT idempotency_keys');
SELECT pg_temp.expect_denied('anon', $$UPDATE public.idempotency_keys SET response = '{}'$$, 'anon UPDATE idempotency_keys');
SELECT pg_temp.expect_denied('anon', 'DELETE FROM public.idempotency_keys', 'anon DELETE idempotency_keys');
SELECT pg_temp.expect_denied('anon', 'TRUNCATE public.idempotency_keys', 'anon TRUNCATE idempotency_keys');

-- Authenticated user A, with that user's sub claim.
SELECT set_config(
    'request.jwt.claims',
    '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","role":"authenticated"}',
    true
);

DO $$
DECLARE
    visible int;
    own_rows int;
BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';

    INSERT INTO public.user_agreements (user_id, role, version)
    VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'player', 'rls-test');

    SELECT count(*) INTO visible FROM public.user_agreements;
    SELECT count(*) INTO own_rows
      FROM public.user_agreements
     WHERE user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

    IF visible IS DISTINCT FROM own_rows OR visible <> 2 THEN
        RAISE EXCEPTION 'user A sees % rows (% of them their own); expected 2 own rows and no others', visible, own_rows;
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.user_agreements
        WHERE user_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
    ) THEN
        RAISE EXCEPTION 'user A can see user B''s agreement';
    END IF;
    RAISE NOTICE 'PASS user A inserted their own agreement and SELECT returned only their 2 rows';

    BEGIN
        INSERT INTO public.user_agreements (user_id, role, version)
        VALUES ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'player', 'rls-test');
        RAISE EXCEPTION 'user A inserted an agreement for user B';
    EXCEPTION
        WHEN insufficient_privilege THEN
            IF SQLERRM NOT ILIKE '%row-level security%' THEN
                RAISE EXCEPTION 'insert for B failed for the wrong reason: %', SQLERRM;
            END IF;
            RAISE NOTICE 'PASS user A cannot insert for user B — %', SQLERRM;
    END;

    BEGIN
        UPDATE public.user_agreements SET version = 'nope' WHERE user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
        RAISE EXCEPTION 'user A updated an agreement';
    EXCEPTION
        WHEN insufficient_privilege THEN
            IF SQLERRM ILIKE '%row-level security%' THEN
                RAISE EXCEPTION 'user A UPDATE was denied by RLS instead of a missing grant: %', SQLERRM;
            END IF;
            RAISE NOTICE 'PASS user A UPDATE user_agreements denied — %', SQLERRM;
    END;

    BEGIN
        DELETE FROM public.user_agreements WHERE user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
        RAISE EXCEPTION 'user A deleted an agreement';
    EXCEPTION
        WHEN insufficient_privilege THEN
            IF SQLERRM ILIKE '%row-level security%' THEN
                RAISE EXCEPTION 'user A DELETE was denied by RLS instead of a missing grant: %', SQLERRM;
            END IF;
            RAISE NOTICE 'PASS user A DELETE user_agreements denied — %', SQLERRM;
    END;

    EXECUTE 'RESET ROLE';
    DELETE FROM public.user_agreements WHERE version = 'rls-test';
END $$;

SELECT pg_temp.expect_denied('authenticated', 'SELECT 1 FROM public.idempotency_keys', 'authenticated SELECT idempotency_keys');
SELECT pg_temp.expect_denied('authenticated', $$INSERT INTO public.idempotency_keys (key, operation, response) VALUES ('auth', 'submit_bet', '{}')$$, 'authenticated INSERT idempotency_keys');
SELECT pg_temp.expect_denied('authenticated', $$UPDATE public.idempotency_keys SET response = '{}'$$, 'authenticated UPDATE idempotency_keys');
SELECT pg_temp.expect_denied('authenticated', 'DELETE FROM public.idempotency_keys', 'authenticated DELETE idempotency_keys');
SELECT pg_temp.expect_denied('authenticated', 'TRUNCATE public.idempotency_keys', 'authenticated TRUNCATE idempotency_keys');

DO $$
DECLARE
    agreements int;
    keys int;
BEGIN
    EXECUTE 'SET LOCAL ROLE service_role';

    SELECT count(*) INTO agreements FROM public.user_agreements;
    SELECT count(*) INTO keys FROM public.idempotency_keys;
    IF agreements <> 2 THEN
        RAISE EXCEPTION 'service_role sees % agreements, expected both seeded rows', agreements;
    END IF;
    IF keys <> 2 THEN
        RAISE EXCEPTION 'service_role sees % idempotency keys, expected both seeded rows', keys;
    END IF;

    INSERT INTO public.idempotency_keys (key, operation, response, user_id)
    VALUES ('rls-test', 'submit_bet', '{"ok":true}', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
    UPDATE public.idempotency_keys SET response = '{"ok":false}' WHERE key = 'rls-test';
    DELETE FROM public.idempotency_keys WHERE key = 'rls-test';

    INSERT INTO public.user_agreements (user_id, role, version)
    VALUES ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'bookie', 'svc-test');
    UPDATE public.user_agreements SET version = 'svc-test-2' WHERE version = 'svc-test';
    DELETE FROM public.user_agreements WHERE version = 'svc-test-2';

    RAISE NOTICE 'PASS service_role SELECT/INSERT/UPDATE/DELETE on both tables (still sees both seeded agreements and both keys)';
    EXECUTE 'RESET ROLE';
END $$;
