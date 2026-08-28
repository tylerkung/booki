/**
 * Per-sport configuration for the props pipeline.
 *
 * The pipeline was built NFL-only and every mechanism in it is sport-agnostic
 * except three constants: which Odds API sport to ask, which balldontlie API to
 * resolve identity against, and which market keys to request. Those live here so
 * a second sport is a config entry rather than a fork.
 *
 * `settleable` is the one that carries weight. balldontlie's /nfl/v1/stats and
 * /nba/v1/stats answer on the current plan; /mlb/v1/stats returns 401. A sport
 * without statlines can be priced and displayed but never graded, so its markets
 * are written with bettable = false and the submit endpoints refuse them.
 */

export interface SportConfig {
  /** The Odds API sport key. */
  oddsKey: string;
  /** balldontlie API root for this sport. */
  bdlBase: string;
  /** Value stored in bdl_teams.sport, bdl_players.sport, markets.subject_sport. */
  sport: string;
  /** Odds API market keys to request. Deliberately narrow — each costs 1 credit
   *  per game and props are the largest market type by row count. */
  propMarkets: string[];
  /** Odds API market key -> the stat_key stored on the market row. */
  marketToStat: Record<string, string>;
  /** False when no statline source exists, so nothing here can be graded. */
  settleable: boolean;
}

const NFL_MARKETS = [
  'player_pass_yds',
  'player_pass_tds',
  'player_rush_yds',
  'player_reception_yds',
  'player_receptions',
  'player_anytime_td',
];

/**
 * Six MLB markets, chosen the same way the NFL six were: each maps to exactly
 * one countable stat with no interpretation, and each is quoted by enough books
 * to be worth storing. Measured live 2026-08-28 (Reds at Cubs, 39 markets
 * offered): batter_total_bases 6 books, pitcher_strikeouts 6, batter_hits 4,
 * pitcher_outs 4, batter_rbis 3, batter_home_runs 1.
 *
 * Deliberately excluded: batter_hits_runs_rbis (a composite of three stats, and
 * ambiguity is what the whole subject-resolution rule exists to avoid) and every
 * *_alternate variant, which carry up to 95 outcomes each and would dwarf the
 * row budget this project has already blown once.
 */
const MLB_MARKETS = [
  'batter_total_bases',
  'batter_hits',
  'batter_home_runs',
  'batter_rbis',
  'pitcher_strikeouts',
  'pitcher_outs',
];

const identity = (keys: string[]): Record<string, string> =>
  Object.fromEntries(keys.map((k) => [k, k]));

export const SPORTS: Record<string, SportConfig> = {
  NFL: {
    oddsKey: 'americanfootball_nfl',
    bdlBase: 'https://api.balldontlie.io/nfl/v1',
    sport: 'NFL',
    propMarkets: NFL_MARKETS,
    marketToStat: identity(NFL_MARKETS),
    settleable: true,
  },
  MLB: {
    oddsKey: 'baseball_mlb',
    bdlBase: 'https://api.balldontlie.io/mlb/v1',
    sport: 'MLB',
    propMarkets: MLB_MARKETS,
    marketToStat: identity(MLB_MARKETS),
    // /mlb/v1/stats returns 401 on the current balldontlie plan. Flip to true
    // when that changes and the markets become bettable on the next ingest.
    settleable: false,
  },
};

export function sportConfig(name?: string): SportConfig {
  const cfg = SPORTS[(name ?? 'NFL').toUpperCase()];
  if (!cfg) throw new Error(`unknown sport "${name}" — expected one of ${Object.keys(SPORTS).join(', ')}`);
  return cfg;
}
