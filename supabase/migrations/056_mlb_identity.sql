-- ============================================================================
-- Multi-sport identity: composite keys, then the MLB team map
-- Migration: 056_mlb_identity.sql
--
-- WHY THIS IS NOT JUST AN INSERT
-- ------------------------------
-- bdl_teams.bdl_team_id is the PRIMARY KEY, and balldontlie numbers teams from
-- 1 within each sport. Measured against the live API: NFL uses ids 1..33, MLB
-- uses 1..30, and 29 of the 30 MLB ids are already taken by an NFL team --
-- id 1 is New England for NFL and Arizona for MLB.
--
-- So seeding MLB into the existing table would not fail loudly. It would
-- collide on the primary key and either abort or, with an upsert, quietly
-- rewrite NFL teams -- breaking the NFL identity resolution that currently
-- works, in a way that would only surface as mis-resolved players months later.
-- bdl_players has the same shape and the same problem.
--
-- The `sport` column was already there from migration 039, defaulted to NFL.
-- This makes it part of the key, which is what it was always for.
--
-- markets.subject_player_id gains a companion `subject_sport` so its foreign
-- key can stay a real constraint rather than being dropped. The prop CHECK from
-- 039 is extended to demand it: a prop row still cannot exist without a
-- resolved subject, and now that subject is unambiguous across sports.
-- ============================================================================

-- ── 1. Composite keys ───────────────────────────────────────────────────────
-- Dropped by catalog lookup rather than by guessed name, since these were
-- created inline and their names are whatever Postgres chose.
DO $$
DECLARE r RECORD;
BEGIN
    FOR r IN
        SELECT conname, conrelid::regclass AS tbl
          FROM pg_constraint
         WHERE contype = 'f'
           AND (confrelid = 'bdl_teams'::regclass OR confrelid = 'bdl_players'::regclass)
    LOOP
        EXECUTE format('ALTER TABLE %s DROP CONSTRAINT %I', r.tbl, r.conname);
    END LOOP;
END $$;

ALTER TABLE bdl_teams   DROP CONSTRAINT IF EXISTS bdl_teams_pkey;
ALTER TABLE bdl_players DROP CONSTRAINT IF EXISTS bdl_players_pkey;

ALTER TABLE bdl_teams   ADD CONSTRAINT bdl_teams_pkey   PRIMARY KEY (sport, bdl_team_id);
ALTER TABLE bdl_players ADD CONSTRAINT bdl_players_pkey PRIMARY KEY (sport, bdl_player_id);

ALTER TABLE bdl_players
    DROP CONSTRAINT IF EXISTS bdl_players_team_fkey;
ALTER TABLE bdl_players
    ADD CONSTRAINT bdl_players_team_fkey
    FOREIGN KEY (sport, bdl_team_id) REFERENCES bdl_teams (sport, bdl_team_id);

-- ── 2. markets carries the sport of its subject ─────────────────────────────
ALTER TABLE markets ADD COLUMN IF NOT EXISTS subject_sport TEXT;

-- Every prop row written before this migration is NFL by construction: it is
-- the only sport the ingest has ever run for.
UPDATE markets SET subject_sport = 'NFL'
 WHERE type = 'player_prop' AND subject_player_id IS NOT NULL AND subject_sport IS NULL;

ALTER TABLE markets DROP CONSTRAINT IF EXISTS markets_subject_player_fkey;
ALTER TABLE markets
    ADD CONSTRAINT markets_subject_player_fkey
    FOREIGN KEY (subject_sport, subject_player_id)
    REFERENCES bdl_players (sport, bdl_player_id);

ALTER TABLE markets DROP CONSTRAINT IF EXISTS markets_prop_requires_subject;
ALTER TABLE markets
    ADD CONSTRAINT markets_prop_requires_subject CHECK (
        type <> 'player_prop'
        OR (subject_player_id IS NOT NULL AND stat_key IS NOT NULL AND subject_sport IS NOT NULL)
    );

COMMENT ON COLUMN markets.subject_sport IS
  'Which sport subject_player_id belongs to. balldontlie numbers players from 1 '
  'per sport, so the id alone is ambiguous -- 29 of 30 MLB team ids collide with '
  'NFL ones, and player ids collide the same way.';

-- ── 3. The MLB team map ─────────────────────────────────────────────────────
-- 29 of 30 names are identical across the two sources. The exception is the
-- Athletics: balldontlie still says "Oakland Athletics", the Odds API has
-- dropped the city. That is exactly the kind of drift odds_api_name exists for.
INSERT INTO bdl_teams (bdl_team_id, abbreviation, full_name, odds_api_name, sport) VALUES
    (1, 'ARI', 'Arizona Diamondbacks', 'Arizona Diamondbacks', 'MLB'),
    (2, 'ATL', 'Atlanta Braves', 'Atlanta Braves', 'MLB'),
    (3, 'BAL', 'Baltimore Orioles', 'Baltimore Orioles', 'MLB'),
    (4, 'BOS', 'Boston Red Sox', 'Boston Red Sox', 'MLB'),
    (5, 'CHC', 'Chicago Cubs', 'Chicago Cubs', 'MLB'),
    (6, 'CHW', 'Chicago White Sox', 'Chicago White Sox', 'MLB'),
    (7, 'CIN', 'Cincinnati Reds', 'Cincinnati Reds', 'MLB'),
    (8, 'CLE', 'Cleveland Guardians', 'Cleveland Guardians', 'MLB'),
    (9, 'COL', 'Colorado Rockies', 'Colorado Rockies', 'MLB'),
    (10, 'DET', 'Detroit Tigers', 'Detroit Tigers', 'MLB'),
    (11, 'HOU', 'Houston Astros', 'Houston Astros', 'MLB'),
    (12, 'KC', 'Kansas City Royals', 'Kansas City Royals', 'MLB'),
    (13, 'LAA', 'Los Angeles Angels', 'Los Angeles Angels', 'MLB'),
    (14, 'LAD', 'Los Angeles Dodgers', 'Los Angeles Dodgers', 'MLB'),
    (15, 'MIA', 'Miami Marlins', 'Miami Marlins', 'MLB'),
    (16, 'MIL', 'Milwaukee Brewers', 'Milwaukee Brewers', 'MLB'),
    (17, 'MIN', 'Minnesota Twins', 'Minnesota Twins', 'MLB'),
    (18, 'NYM', 'New York Mets', 'New York Mets', 'MLB'),
    (19, 'NYY', 'New York Yankees', 'New York Yankees', 'MLB'),
    (20, 'OAK', 'Oakland Athletics', 'Athletics', 'MLB'),
    (21, 'PHI', 'Philadelphia Phillies', 'Philadelphia Phillies', 'MLB'),
    (22, 'PIT', 'Pittsburgh Pirates', 'Pittsburgh Pirates', 'MLB'),
    (23, 'SD', 'San Diego Padres', 'San Diego Padres', 'MLB'),
    (24, 'SF', 'San Francisco Giants', 'San Francisco Giants', 'MLB'),
    (25, 'SEA', 'Seattle Mariners', 'Seattle Mariners', 'MLB'),
    (26, 'STL', 'St. Louis Cardinals', 'St. Louis Cardinals', 'MLB'),
    (27, 'TB', 'Tampa Bay Rays', 'Tampa Bay Rays', 'MLB'),
    (28, 'TEX', 'Texas Rangers', 'Texas Rangers', 'MLB'),
    (29, 'TOR', 'Toronto Blue Jays', 'Toronto Blue Jays', 'MLB'),
    (30, 'WSH', 'Washington Nationals', 'Washington Nationals', 'MLB')
ON CONFLICT (sport, bdl_team_id) DO UPDATE
    SET abbreviation  = EXCLUDED.abbreviation,
        full_name     = EXCLUDED.full_name,
        odds_api_name = EXCLUDED.odds_api_name,
        updated_at    = now();

-- ── 4. Assertions ───────────────────────────────────────────────────────────
DO $$
DECLARE
    v_mlb INT;
    v_nfl INT;
BEGIN
    SELECT count(*) INTO v_mlb FROM bdl_teams WHERE sport = 'MLB';
    SELECT count(*) INTO v_nfl FROM bdl_teams WHERE sport = 'NFL';
    IF v_mlb <> 30 THEN RAISE EXCEPTION '056: expected 30 MLB teams, found %', v_mlb; END IF;
    IF v_nfl <> 32 THEN RAISE EXCEPTION '056: NFL teams changed to % -- collision suspected', v_nfl; END IF;
    RAISE NOTICE '056: % NFL + % MLB teams, composite keys in place', v_nfl, v_mlb;
END $$;
