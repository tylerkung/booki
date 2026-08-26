-- ============================================================================
-- 040 — Seed the balldontlie team map (NFL)
--
-- The seam between the two providers. Verified 2026-08-25: all 32 Odds API NFL
-- team names match balldontlie's full_name EXACTLY, so odds_api_name is
-- currently identical to full_name for every row.
--
-- The table exists anyway, and the column is stored rather than assumed,
-- because that agreement is a fact about today's data and not a guarantee.
-- Either provider can rename a franchise, and when one does this is a one-row
-- UPDATE instead of a hunt through matching logic.
--
-- The only Odds API "team" without a row is 'NFL Super Bowl Winner', the
-- home_team sentinel on an outright event rather than a team. Props are never
-- written against outrights, so it needs no mapping.
-- ============================================================================

INSERT INTO bdl_teams (bdl_team_id, abbreviation, full_name, odds_api_name)
VALUES
    (33, 'ARI', 'Arizona Cardinals', 'Arizona Cardinals'),
    (27, 'ATL', 'Atlanta Falcons', 'Atlanta Falcons'),
    (6, 'BAL', 'Baltimore Ravens', 'Baltimore Ravens'),
    (3, 'BUF', 'Buffalo Bills', 'Buffalo Bills'),
    (29, 'CAR', 'Carolina Panthers', 'Carolina Panthers'),
    (24, 'CHI', 'Chicago Bears', 'Chicago Bears'),
    (9, 'CIN', 'Cincinnati Bengals', 'Cincinnati Bengals'),
    (8, 'CLE', 'Cleveland Browns', 'Cleveland Browns'),
    (19, 'DAL', 'Dallas Cowboys', 'Dallas Cowboys'),
    (15, 'DEN', 'Denver Broncos', 'Denver Broncos'),
    (25, 'DET', 'Detroit Lions', 'Detroit Lions'),
    (22, 'GB', 'Green Bay Packers', 'Green Bay Packers'),
    (10, 'HOU', 'Houston Texans', 'Houston Texans'),
    (12, 'IND', 'Indianapolis Colts', 'Indianapolis Colts'),
    (13, 'JAX', 'Jacksonville Jaguars', 'Jacksonville Jaguars'),
    (14, 'KC', 'Kansas City Chiefs', 'Kansas City Chiefs'),
    (17, 'LAC', 'Los Angeles Chargers', 'Los Angeles Chargers'),
    (32, 'LAR', 'Los Angeles Rams', 'Los Angeles Rams'),
    (16, 'LV', 'Las Vegas Raiders', 'Las Vegas Raiders'),
    (5, 'MIA', 'Miami Dolphins', 'Miami Dolphins'),
    (23, 'MIN', 'Minnesota Vikings', 'Minnesota Vikings'),
    (1, 'NE', 'New England Patriots', 'New England Patriots'),
    (26, 'NO', 'New Orleans Saints', 'New Orleans Saints'),
    (20, 'NYG', 'New York Giants', 'New York Giants'),
    (4, 'NYJ', 'New York Jets', 'New York Jets'),
    (18, 'PHI', 'Philadelphia Eagles', 'Philadelphia Eagles'),
    (7, 'PIT', 'Pittsburgh Steelers', 'Pittsburgh Steelers'),
    (31, 'SEA', 'Seattle Seahawks', 'Seattle Seahawks'),
    (30, 'SF', 'San Francisco 49ers', 'San Francisco 49ers'),
    (28, 'TB', 'Tampa Bay Buccaneers', 'Tampa Bay Buccaneers'),
    (11, 'TEN', 'Tennessee Titans', 'Tennessee Titans'),
    (21, 'WSH', 'Washington Commanders', 'Washington Commanders')
ON CONFLICT (bdl_team_id) DO UPDATE
    SET abbreviation  = EXCLUDED.abbreviation,
        full_name     = EXCLUDED.full_name,
        odds_api_name = EXCLUDED.odds_api_name,
        updated_at    = now();

-- Assert rather than assume. A short map does not fail loudly at runtime — it
-- silently stops resolving props for whichever team is missing, which reads as
-- "that game just has no props" and could go unnoticed for a season.
DO $$
DECLARE
    n INT;
BEGIN
    SELECT count(*) INTO n FROM bdl_teams WHERE sport = 'NFL';
    IF n <> 32 THEN
        RAISE EXCEPTION 'bdl_teams: expected 32 NFL teams, found %', n;
    END IF;

    SELECT count(*) INTO n FROM (
        SELECT odds_api_name FROM bdl_teams WHERE sport = 'NFL'
        GROUP BY odds_api_name HAVING count(*) > 1
    ) dupes;
    IF n > 0 THEN
        RAISE EXCEPTION 'bdl_teams: % duplicated odds_api_name values', n;
    END IF;

    RAISE NOTICE 'bdl_teams: 32 NFL teams seeded, odds_api_name unique';
END $$;
