-- ============================================================================
-- 046 — Actually enable RLS on markets
--
-- markets_select has existed since migration 011 and has NEVER been enforced,
-- because nothing ever ran ENABLE ROW LEVEL SECURITY on the table. A policy on
-- a table without RLS is inert: Postgres does not warn, the policy shows up in
-- pg_policies exactly as though it works, and every row is readable by anyone
-- holding the anon key.
--
-- Found when migration 045 added a clause to that policy to hide player props
-- from clients, and a signed-in client kept returning all 35 of them.
--
-- Two consequences, and the second is why this is worth doing carefully:
--
--   1. 045 did nothing. Hiding unrenderable market types only starts working
--      once RLS is on.
--
--   2. markets has had no row-level protection at all. Odds are not secret, so
--      this is not a data leak of consequence — but bookie-scoped markets
--      (bookie_id NOT NULL) were readable across tenants, and the isolation the
--      policy describes was never real.
--
-- RISK: turning RLS on changes reads for every client at once. If the policy is
-- wrong, the board goes empty. The DO block at the bottom therefore assumes the
-- authenticated role and asserts what that role can actually see, rather than
-- trusting that the policy says what it means.
-- ============================================================================

ALTER TABLE markets ENABLE ROW LEVEL SECURITY;

-- Recreated here rather than relied upon from 045, so this migration is
-- self-contained: the policy and the enable that makes it real arrive together.
DROP POLICY IF EXISTS markets_select ON markets;
CREATE POLICY markets_select ON markets
    FOR SELECT
    USING (
        (bookie_id = get_user_bookie_id() OR bookie_id IS NULL)
        AND NOT (type = ANY (legacy_client_hidden_market_types()))
    );

DO $$
DECLARE
    v_shared  INT;
    v_hidden  INT;
    v_enabled BOOLEAN;
BEGIN
    SELECT relrowsecurity INTO v_enabled
      FROM pg_class WHERE oid = 'public.markets'::regclass;
    IF NOT v_enabled THEN
        RAISE EXCEPTION 'RLS still not enabled on markets';
    END IF;

    -- Read as a client would. get_user_bookie_id() returns NULL without a JWT,
    -- so this exercises the shared-markets arm, which is what every member
    -- relies on to see a board at all.
    SET LOCAL ROLE authenticated;

    SELECT count(*) INTO v_shared
      FROM markets WHERE type IN ('moneyline', 'spread', 'total');
    SELECT count(*) INTO v_hidden
      FROM markets WHERE type = ANY (legacy_client_hidden_market_types());

    RESET ROLE;

    -- An empty board is the failure this migration could plausibly cause, so
    -- refuse rather than ship it.
    IF v_shared = 0 THEN
        RAISE EXCEPTION 'authenticated role can no longer read core markets — the board would be empty';
    END IF;
    IF v_hidden <> 0 THEN
        RAISE EXCEPTION 'hidden market types are still visible to authenticated (% rows)', v_hidden;
    END IF;

    RAISE NOTICE 'RLS enforced on markets: % core markets visible, % hidden types visible', v_shared, v_hidden;
END $$;
