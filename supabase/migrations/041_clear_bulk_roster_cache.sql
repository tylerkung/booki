-- ============================================================================
-- 041 — Clear the bulk roster cache; resolution becomes on-demand
--
-- REPLACES the weekly full-roster sync that this file previously scheduled.
-- That migration was never run, so its number is reused rather than leaving a
-- scheduled job for a sync that should not exist.
--
-- Why the bulk cache had to go, and why deleting rows is the safe direction:
--
-- bdl_players was filled by pulling ~100 players per team. balldontlie returns
-- every player who has EVER played for a franchise, current roster first, so a
-- page cap silently truncates the tail. It missed a second currently-rostered
-- Josh Allen (C, Arizona) — which meant the cache reported that name as UNIQUE
-- when it is not.
--
-- That is the dangerous shape. Resolution reads the cache first and trusts a
-- single hit; a cache that is incomplete turns a genuine ambiguity into a
-- confident wrong answer, which is precisely the failure the whole props design
-- exists to prevent. An incomplete cache is worse than an empty one.
--
-- So the table is emptied and its meaning changes: it is no longer a mirror of
-- the league, it is a record of resolutions we have ACTUALLY VERIFIED against
-- the API, one player at a time, filled on demand by _shared/bdl_resolve.ts.
-- A miss costs one API call; a wrong hit costs a member's money.
--
-- This also makes the weekly refresh unnecessary. A traded player's cached team
-- goes stale, which produces a cache MISS rather than a wrong answer, and the
-- next resolution re-queries and corrects it. The cache self-heals in the only
-- direction that is safe.
-- ============================================================================

DELETE FROM bdl_players;

COMMENT ON TABLE bdl_players IS
    'Verified name->player resolutions, filled on demand by _shared/bdl_resolve.ts. NOT a mirror of the league: a row exists only because a prop named that player and the API confirmed exactly one match on that game''s rosters. Never bulk-load this table — an incomplete cache reports ambiguous names as unique.';

DO $$
DECLARE
    n INT;
BEGIN
    SELECT count(*) INTO n FROM bdl_players;
    IF n <> 0 THEN
        RAISE EXCEPTION 'bdl_players should be empty, found % rows', n;
    END IF;

    -- The team map stays: it is complete (all 32, asserted in 040) and is a
    -- genuine 1:1 mapping rather than a sample.
    SELECT count(*) INTO n FROM bdl_teams WHERE sport = 'NFL';
    IF n <> 32 THEN
        RAISE EXCEPTION 'bdl_teams should still hold 32 NFL teams, found %', n;
    END IF;

    RAISE NOTICE 'bdl_players emptied; resolution is now on-demand and verified per player';
END $$;
