/**
 * Odds API prop market -> the balldontlie NFL statline that settles it.
 *
 * Verified 2026-08-25 against game 423945 (Cowboys at Eagles, 60 statlines).
 * Every expression below resolves to a field that exists and is populated.
 *
 * Two traps are encoded here rather than left to the caller, because both
 * mis-settle real bets and neither is obvious from the field names:
 *
 *   1. A row of zeroes is NOT a player who sat out. balldontlie emits a
 *      statline only for players with recorded involvement — ~30 per team
 *      against a ~48 gameday roster — so absence means DNP and a zero row
 *      means "played, did nothing". The PRESENCE of the row is the signal;
 *      the values in it never are. Collapsing the two would void props that
 *      should have lost, refunding stakes on bets the book won.
 *
 *   2. `passing_touchdowns` must never count toward an anytime touchdown. The
 *      quarterback throws it, the receiver scores it. Including it would credit
 *      every QB with touchdowns they did not score, on one of the most popular
 *      markets there is.
 */

export type Statline = Record<string, number | null>;

const num = (s: Statline, k: string): number => Number(s[k] ?? 0);

/**
 * Every way a player can put six points on the board himself.
 *
 * `passing_touchdowns` is deliberately absent — see trap 2 above.
 */
const SCORING_TD_FIELDS = [
  'rushing_touchdowns',
  'receiving_touchdowns',
  'kick_return_touchdowns',
  'punt_return_touchdowns',
  'interception_touchdowns',
  'fumbles_touchdowns',
] as const;

export const PROP_STATS: Record<string, (s: Statline) => number> = {
  player_pass_yds:            (s) => num(s, 'passing_yards'),
  player_pass_tds:            (s) => num(s, 'passing_touchdowns'),
  player_pass_completions:    (s) => num(s, 'passing_completions'),
  player_pass_attempts:       (s) => num(s, 'passing_attempts'),
  player_pass_interceptions:  (s) => num(s, 'passing_interceptions'),

  player_rush_yds:            (s) => num(s, 'rushing_yards'),
  player_rush_attempts:       (s) => num(s, 'rushing_attempts'),
  player_rush_longest:        (s) => num(s, 'long_rushing'),

  player_receptions:          (s) => num(s, 'receptions'),
  player_reception_yds:       (s) => num(s, 'receiving_yards'),
  player_reception_longest:   (s) => num(s, 'long_reception'),

  player_rush_reception_yds:  (s) => num(s, 'rushing_yards') + num(s, 'receiving_yards'),
  player_pass_rush_yds:       (s) => num(s, 'passing_yards') + num(s, 'rushing_yards'),

  player_anytime_td:          (s) => SCORING_TD_FIELDS.reduce((t, f) => t + num(s, f), 0),
  player_tds_over:            (s) => SCORING_TD_FIELDS.reduce((t, f) => t + num(s, f), 0),

  player_field_goals:         (s) => num(s, 'field_goals_made'),
  player_pats:                (s) => num(s, 'extra_points_made'),
  // total_points exists in the schema but is not populated — zero non-null
  // values across every statline in the verification game — so kicking points
  // are derived rather than read.
  player_kicking_points:      (s) => num(s, 'field_goals_made') * 3 + num(s, 'extra_points_made'),

  player_sacks:                   (s) => num(s, 'defensive_sacks'),
  player_solo_tackles:            (s) => num(s, 'solo_tackles'),
  player_tackles_assists:         (s) => num(s, 'total_tackles'),
  player_defensive_interceptions: (s) => num(s, 'defensive_interceptions'),
};

/** Markets needing play-by-play, which ALL-STAR does not include. */
export const UNSUPPORTED_PROPS = ['player_1st_td', 'player_last_td'];

export type PropVerdict = 'win' | 'loss' | 'push' | 'void' | 'pending';

export interface PropOutcome {
  result: PropVerdict;
  detail: string;
}

/**
 * Settle one prop.
 *
 * `statline` is null when the player has NO row for this game, which is the
 * only signal that he did not play. Pass the row itself — even an all-zero one
 * — whenever it exists.
 */
export function gradeProp(
  marketKey: string,
  side: string,               // "Patrick Mahomes Over 275.5"
  statline: Statline | null,
): PropOutcome {
  const parsed = side.match(/^(.*)\s+(Over|Under)\s+([\d.]+)$/i);
  if (!parsed) return { result: 'pending', detail: `unparseable side "${side}"` };
  const [, subject, direction, lineStr] = parsed;
  const line = Number(lineStr);

  if (statline === null) {
    return { result: 'void', detail: `${subject} did not play` };
  }

  const getter = PROP_STATS[marketKey];
  if (!getter) return { result: 'pending', detail: `no stat mapping for ${marketKey}` };

  const actual = getter(statline);
  if (actual === line) {
    return { result: 'push', detail: `${subject} ${actual} = ${line}` };
  }
  const won = direction.toLowerCase() === 'over' ? actual > line : actual < line;
  return {
    result: won ? 'win' : 'loss',
    detail: `${subject} ${actual} vs ${direction} ${line}`,
  };
}
