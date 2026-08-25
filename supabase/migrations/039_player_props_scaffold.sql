-- ============================================================================
-- 039 — Player props: identity cache and market subject columns
--
-- Scaffolding for tasks/prd-player-props.md. Creates the identity layer and
-- the columns a prop market needs; it does NOT turn anything on. No prop is
-- ingested until sync_games is changed, and no prop can be ingested at all
-- until US-001 confirms the NFL statline field names.
--
-- The design rests on one rule: A PROP WE CANNOT GRADE IS NEVER OFFERED.
-- Identity is resolved at ingest, not at settlement, so an unresolvable player
-- means the market is never written rather than discovered after someone has
-- money on it. The CHECK constraint at the bottom makes that a property of the
-- database rather than a convention in a function someone can forget.
-- ============================================================================

-- ── Team map: Odds API names <-> balldontlie ids ────────────────────────────
--
-- The two providers share no keys and spell teams differently. 32 rows, and a
-- missing one silently blocks every prop for that team's games, so completeness
-- is asserted rather than hoped for.
CREATE TABLE IF NOT EXISTS bdl_teams (
    bdl_team_id   INTEGER PRIMARY KEY,
    abbreviation  TEXT NOT NULL,
    full_name     TEXT NOT NULL,
    -- What The Odds API calls this team. Usually identical to full_name, which
    -- is exactly why the exceptions are worth storing explicitly.
    odds_api_name TEXT NOT NULL UNIQUE,
    sport         TEXT NOT NULL DEFAULT 'NFL',
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── Player cache ────────────────────────────────────────────────────────────
--
-- Refreshed weekly. Rosters churn constantly and a stale cache does not fail
-- loudly — it just stops resolving newly signed players, so their props quietly
-- stop appearing. last_synced_at exists so that staleness is visible.
CREATE TABLE IF NOT EXISTS bdl_players (
    bdl_player_id   INTEGER PRIMARY KEY,
    first_name      TEXT NOT NULL,
    last_name       TEXT NOT NULL,
    -- Lowercased, accents stripped, punctuation removed, suffix dropped.
    -- Written by the ingest so both sides of a comparison normalise identically;
    -- doing it in two places is how the two sides drift apart.
    normalized_name TEXT NOT NULL,
    position        TEXT,
    bdl_team_id     INTEGER REFERENCES bdl_teams(bdl_team_id),
    sport           TEXT NOT NULL DEFAULT 'NFL',
    last_synced_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- The resolution query is always "this name, on one of these two teams".
CREATE INDEX IF NOT EXISTS idx_bdl_players_lookup
    ON bdl_players (sport, normalized_name, bdl_team_id);

-- ── Event -> balldontlie game ───────────────────────────────────────────────
--
-- Resolved by date plus both team ids and cached, because it is needed once per
-- game at ingest and again at grading, and matching by name every time is both
-- slower and more places to get it wrong.
ALTER TABLE events
    ADD COLUMN IF NOT EXISTS bdl_game_id INTEGER;

COMMENT ON COLUMN events.bdl_game_id IS
    'balldontlie game id, resolved by date + both teams. NULL blocks prop ingest and prop grading for this event.';

-- ── Market subject ──────────────────────────────────────────────────────────
--
-- A prop is about a PERSON. Storing that only inside the side label
-- ("Patrick Mahomes Over 275.5") would mean re-parsing a display string at
-- settlement, which is fragile in exactly the way that mis-settles a bet.
ALTER TABLE markets
    ADD COLUMN IF NOT EXISTS subject_player_id INTEGER REFERENCES bdl_players(bdl_player_id),
    -- Kept alongside the id for display and for debugging a bad match. The id
    -- is the truth; this is what the price feed called them.
    ADD COLUMN IF NOT EXISTS subject_name      TEXT,
    -- The statline field this market settles against, e.g. 'passing_yards'.
    -- Stored per market so grading never has to infer intent from a market type
    -- string, and so an unmapped market is impossible to create.
    ADD COLUMN IF NOT EXISTS stat_key          TEXT;

-- THE RULE, as a constraint. A prop row without a resolved player or a stat to
-- settle against cannot exist, so it can never reach the board.
ALTER TABLE markets
    DROP CONSTRAINT IF EXISTS markets_prop_requires_subject;
ALTER TABLE markets
    ADD CONSTRAINT markets_prop_requires_subject CHECK (
        type <> 'player_prop'
        OR (subject_player_id IS NOT NULL AND stat_key IS NOT NULL)
    );

-- Two players routinely share a line on the same stat in the same game, so the
-- subject is part of what makes a prop row unique — the same collision that
-- team totals hit when keyed on line value alone.
CREATE INDEX IF NOT EXISTS idx_markets_prop_subject
    ON markets (event_id, stat_key, subject_player_id)
    WHERE type = 'player_prop';

-- ── Grading state ───────────────────────────────────────────────────────────
--
-- Props cannot be graded the moment a game ends: statlines arrive late, arrive
-- partial, and are sometimes revised days later. This tracks each game's
-- progress so a retry knows what it is retrying, and so a correction is
-- detectable instead of invisible.
CREATE TABLE IF NOT EXISTS prop_grading_runs (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id        UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    bdl_game_id     INTEGER,
    -- pending | partial | graded | failed | needs_review
    status          TEXT NOT NULL DEFAULT 'pending',
    attempts        INTEGER NOT NULL DEFAULT 0,
    -- The box score the grade was computed from. Snapshotted so that a later
    -- stat correction can be DETECTED by comparison. Without it a revision is
    -- silent and the ledger is quietly wrong.
    statline_snapshot JSONB,
    last_error      TEXT,
    first_attempt_at TIMESTAMPTZ,
    graded_at       TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (event_id)
);

CREATE INDEX IF NOT EXISTS idx_prop_grading_runs_open
    ON prop_grading_runs (status, updated_at)
    WHERE status IN ('pending', 'partial');

-- Service role only: every one of these is written by an edge function, and
-- none of it is per-tenant data a member should read directly.
ALTER TABLE bdl_teams          ENABLE ROW LEVEL SECURITY;
ALTER TABLE bdl_players        ENABLE ROW LEVEL SECURITY;
ALTER TABLE prop_grading_runs  ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    RAISE NOTICE 'player props scaffold: identity cache, market subject columns, grading state';
    RAISE NOTICE 'NOTHING IS ENABLED — sync_games still does not request prop markets';
END $$;
