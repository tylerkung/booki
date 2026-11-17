-- After the rollback, anon is back to the pre-061 access: RLS off, so a
-- SELECT sees every seeded row, and INSERT/UPDATE/DELETE/TRUNCATE succeed.

DO $$
DECLARE
    ids text;
    keys text;
    rls boolean;
    forced boolean;
BEGIN
    SELECT c.relrowsecurity, c.relforcerowsecurity INTO rls, forced
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public' AND c.relname = 'user_agreements';
    IF rls IS NOT FALSE OR forced IS NOT FALSE THEN
        RAISE EXCEPTION 'user_agreements after rollback: rls=%, forced=%', rls, forced;
    END IF;

    SELECT c.relrowsecurity, c.relforcerowsecurity INTO rls, forced
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public' AND c.relname = 'idempotency_keys';
    IF rls IS NOT FALSE OR forced IS NOT FALSE THEN
        RAISE EXCEPTION 'idempotency_keys after rollback: rls=%, forced=%', rls, forced;
    END IF;
    RAISE NOTICE 'PASS rollback left RLS off and not forced on both tables';

    EXECUTE 'SET LOCAL ROLE anon';

    SELECT string_agg(user_id::text, ',' ORDER BY user_id) INTO ids FROM public.user_agreements;
    IF ids IS DISTINCT FROM 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa,bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' THEN
        RAISE EXCEPTION 'anon SELECT user_agreements returned [%]', ids;
    END IF;

    SELECT string_agg(key, ',' ORDER BY key) INTO keys FROM public.idempotency_keys;
    IF keys IS DISTINCT FROM 'seed-a,seed-b' THEN
        RAISE EXCEPTION 'anon SELECT idempotency_keys returned [%]', keys;
    END IF;
    RAISE NOTICE 'PASS anon SELECT sees both agreements (%) and both idempotency keys (%)', ids, keys;

    INSERT INTO public.user_agreements (user_id, role, version)
    VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'player', 'rollback-test');
    UPDATE public.user_agreements SET version = 'rollback-test-2' WHERE version = 'rollback-test';
    DELETE FROM public.user_agreements WHERE version = 'rollback-test-2';

    INSERT INTO public.idempotency_keys (key, operation, response)
    VALUES ('rollback-test', 'submit_bet', '{}');
    UPDATE public.idempotency_keys SET response = '{"x":1}' WHERE key = 'rollback-test';
    DELETE FROM public.idempotency_keys WHERE key = 'rollback-test';
    RAISE NOTICE 'PASS anon INSERT/UPDATE/DELETE on both tables';

    TRUNCATE public.user_agreements;
    TRUNCATE public.idempotency_keys;
    IF (SELECT count(*) FROM public.user_agreements) <> 0
       OR (SELECT count(*) FROM public.idempotency_keys) <> 0 THEN
        RAISE EXCEPTION 'anon TRUNCATE did not empty the tables';
    END IF;
    RAISE NOTICE 'PASS anon TRUNCATE emptied both tables';

    EXECUTE 'RESET ROLE';
END $$;
