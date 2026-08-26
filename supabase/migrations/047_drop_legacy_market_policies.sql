-- ============================================================================
-- 047 — Drop two legacy market policies that override the current one
--
-- 046 enabled RLS and its own assertion then failed: the authenticated role
-- could still see all 35 hidden rows. The cause is that markets carries SIX
-- policies, two of which were created outside this repo (via the dashboard) and
-- are invisible in the migration history:
--
--   "Bookies can read their own or shared markets"
--       SELECT USING (bookie_id = auth.uid() OR bookie_id IS NULL)
--
--   "Bookies can manage their own markets"
--       ALL    USING (bookie_id = auth.uid())
--
-- PERMISSIVE policies are OR'd together. The first therefore grants every
-- shared market to every signed-in user regardless of type, which is exactly
-- what markets_select was rewritten to prevent. Adding a restriction to one
-- policy achieves nothing while another still permits the row.
--
-- Both are also WRONG on their own terms: they compare bookie_id — a
-- bookies.id — against auth.uid(), an auth user id. Those are different id
-- spaces and never match, so the "their own" arm has never granted anything.
-- Only the `bookie_id IS NULL` arm ever did any work, and it did too much.
--
-- Everything they were meant to do is already covered correctly by
-- markets_select / markets_insert / markets_update / markets_delete, which use
-- get_user_bookie_id() and compare the right id spaces.
--
-- NOTE FOR FUTURE MIGRATIONS: 046 applied PARTIALLY. The Supabase SQL editor
-- does not wrap a script in a single transaction, so its ALTER TABLE and its
-- CREATE POLICY committed and only the failing DO block rolled back. An
-- assertion at the end of a migration catches a bad state but does NOT undo the
-- statements before it. Write migrations so a partial application is safe.
-- ============================================================================

DROP POLICY IF EXISTS "Bookies can read their own or shared markets" ON markets;
DROP POLICY IF EXISTS "Bookies can manage their own markets" ON markets;

-- 046 may or may not have got this far; both are idempotent.
ALTER TABLE markets ENABLE ROW LEVEL SECURITY;

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
    v_select  INT;
    v_enabled BOOLEAN;
BEGIN
    SELECT relrowsecurity INTO v_enabled
      FROM pg_class WHERE oid = 'public.markets'::regclass;
    IF NOT v_enabled THEN
        RAISE EXCEPTION 'RLS not enabled on markets';
    END IF;

    -- Exactly one SELECT policy, so nothing can permit what it denies.
    SELECT count(*) INTO v_select
      FROM pg_policies
     WHERE tablename = 'markets' AND cmd IN ('SELECT', 'ALL');
    IF v_select <> 1 THEN
        RAISE EXCEPTION 'expected exactly 1 SELECT/ALL policy on markets, found % — a permissive policy will OR around the restriction', v_select;
    END IF;

    SET LOCAL ROLE authenticated;
    SELECT count(*) INTO v_shared FROM markets WHERE type IN ('moneyline','spread','total');
    SELECT count(*) INTO v_hidden FROM markets WHERE type = ANY (legacy_client_hidden_market_types());
    RESET ROLE;

    IF v_shared = 0 THEN
        RAISE EXCEPTION 'authenticated can no longer read core markets — the board would be empty';
    END IF;
    IF v_hidden <> 0 THEN
        RAISE EXCEPTION 'hidden market types still visible to authenticated (% rows)', v_hidden;
    END IF;

    RAISE NOTICE 'markets: RLS on, 1 SELECT policy, % core visible, % hidden visible', v_shared, v_hidden;
END $$;
