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

/**
 * A present 0 is a real zero. A missing key or a null is not — callers must
 * not grade that as "played and did nothing". A non-finite value is returned
 * as-is so the grader can refuse it instead of treating NaN as 0.
 */
export function readStat(s: Statline, key: string): number | null {
  if (!Object.prototype.hasOwnProperty.call(s, key)) return null;
  const value = s[key];
  if (value === null || value === undefined) return null;
  return Number(value);
}

function add(s: Statline, keys: readonly string[]): number | null {
  let total = 0;
  for (const key of keys) {
    const value = readStat(s, key);
    if (value === null) return null;
    if (!Number.isFinite(value)) return value;
    total += value;
  }
  return total;
}

/**
 * Touchdown props. A real NFL statline omits return and fumble scores for a
 * player who only rushed. Those absent fields are 0 once the player has a
 * row. A missing statline is handled before this runs and stays a void, and
 * a missing primary stat (yards, receptions) still uses `add` and stays pending.
 */
function addAbsentAsZero(s: Statline, keys: readonly string[]): number | null {
  let total = 0;
  for (const key of keys) {
    const value = readStat(s, key);
    if (value === null) continue;
    if (!Number.isFinite(value)) return value;
    total += value;
  }
  return total;
}

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

export const PROP_STATS: Record<string, (s: Statline) => number | null> = {
  player_pass_yds:            (s) => readStat(s, 'passing_yards'),
  player_pass_tds:            (s) => readStat(s, 'passing_touchdowns'),
  player_pass_completions:    (s) => readStat(s, 'passing_completions'),
  player_pass_attempts:       (s) => readStat(s, 'passing_attempts'),
  player_pass_interceptions:  (s) => readStat(s, 'passing_interceptions'),

  player_rush_yds:            (s) => readStat(s, 'rushing_yards'),
  player_rush_attempts:       (s) => readStat(s, 'rushing_attempts'),
  player_rush_tds:            (s) => readStat(s, 'rushing_touchdowns'),
  player_rush_longest:        (s) => readStat(s, 'long_rushing'),

  player_receptions:          (s) => readStat(s, 'receptions'),
  player_reception_yds:       (s) => readStat(s, 'receiving_yards'),
  player_reception_longest:   (s) => readStat(s, 'long_reception'),

  player_rush_reception_yds:  (s) => add(s, ['rushing_yards', 'receiving_yards']),
  player_pass_rush_yds:       (s) => add(s, ['passing_yards', 'rushing_yards']),

  // Scoring touchdowns only. passing_touchdowns is a different market.
  player_anytime_td:          (s) => addAbsentAsZero(s, SCORING_TD_FIELDS),
  player_tds_over:            (s) => addAbsentAsZero(s, SCORING_TD_FIELDS),

  player_field_goals:         (s) => readStat(s, 'field_goals_made'),
  player_pats:                (s) => readStat(s, 'extra_points_made'),
  // total_points exists in the schema but is not populated — zero non-null
  // values across every statline in the verification game — so kicking points
  // are derived rather than read.
  player_kicking_points:      (s) => {
    const made = readStat(s, 'field_goals_made');
    const extra = readStat(s, 'extra_points_made');
    if (made === null || extra === null) return null;
    if (!Number.isFinite(made) || !Number.isFinite(extra)) return Number.NaN;
    return made * 3 + extra;
  },

  player_sacks:                   (s) => readStat(s, 'defensive_sacks'),
  player_solo_tackles:            (s) => readStat(s, 'solo_tackles'),
  player_tackles_assists:         (s) => readStat(s, 'total_tackles'),
  player_defensive_interceptions: (s) => readStat(s, 'defensive_interceptions'),

  // NBA box-score fields, verified against a real balldontlie game in
  // docs/spikes/prop-grading-spike.ts. grade_player_props does not fetch NBA
  // yet — the ingest and the completeness gate are NFL-only — but a snapshot
  // that already names one of these keys can be graded by the pure function.
  player_points:                  (s) => readStat(s, 'pts'),
  player_rebounds:                (s) => readStat(s, 'reb'),
  player_assists:                 (s) => readStat(s, 'ast'),
  player_threes:                  (s) => readStat(s, 'fg3m'),
  player_blocks:                  (s) => readStat(s, 'blk'),
  player_steals:                  (s) => readStat(s, 'stl'),
};

/** Markets needing play-by-play, which ALL-STAR does not include. */
export const UNSUPPORTED_PROPS = ['player_1st_td', 'player_last_td'];

export type PropVerdict = 'win' | 'loss' | 'push' | 'void' | 'pending';

/** A finished NFL box score has both teams and at least this many statlines. */
export const NFL_BOX_SCORE_MIN_ROWS = 20;

export interface PropOutcome {
  result: PropVerdict;
  detail: string;
  actual?: number | null;
  line?: number | null;
  stat_key?: string;
}

export interface ParsedPropSide {
  subject: string;
  direction: 'over' | 'under';
  line: number;
}

/**
 * "Mark Andrews Over 2.5" and the anytime-TD shape "Justin Herbert Anytime TD Yes".
 * Yes is over 0.5, No is under 0.5 — that is how sync_player_props stores it.
 */
export function parsePropSide(side: string): ParsedPropSide | null {
  const trimmed = side.trim().replace(/\s+/g, ' ');
  if (!trimmed) return null;
  const ou = trimmed.match(/^(.*)\s+(Over|Under)\s+([0-9]+(?:\.[0-9]+)?)$/i);
  if (ou) {
    return {
      subject: ou[1],
      direction: ou[2].toLowerCase() === 'over' ? 'over' : 'under',
      line: Number(ou[3]),
    };
  }
  const yn = trimmed.match(/^(.*)\s+(Yes|No)$/i);
  if (yn) {
    return {
      subject: yn[1],
      direction: yn[2].toLowerCase() === 'yes' ? 'over' : 'under',
      line: 0.5,
    };
  }
  return null;
}

/** Counting stats only tie an integer line. 8 vs 2.5 is never a push. */
export function isIntegerLine(line: number): boolean {
  return Number.isFinite(line) && Math.abs(line - Math.round(line)) < 1e-9;
}

export interface GradePropOptions {
  /**
   * False while the box score is still being written. A missing row in that
   * state is NOT a did-not-play — the row may simply not have landed yet.
   */
  statsFinal?: boolean;
}

/**
 * Settle one prop.
 *
 * `statline` is null when the player has NO row for this game, which is the
 * only signal that he did not play. Pass the row itself — even an all-zero one
 * — whenever it exists.
 *
 * Push only when the stat equals an integer line. A half-point line cannot
 * tie an integer stat. The only void is a player with no statline at all
 * after the box score is final and complete. An unknown stat, or a stat
 * field that is missing or not a number, stays pending for manual review.
 * Nothing in those cases is settled.
 */
export function gradeProp(
  marketKey: string,
  side: string,
  statline: Statline | null,
  options: GradePropOptions = {},
): PropOutcome {
  const statsFinal = options.statsFinal !== false;

  if (!statsFinal) {
    return {
      result: 'pending',
      detail: 'stats not final; left pending',
      stat_key: marketKey,
    };
  }

  const parsed = parsePropSide(side);
  if (!parsed) {
    return {
      result: 'pending',
      detail: `unparseable side "${side}"; left pending, not pushed`,
      stat_key: marketKey,
    };
  }
  const { subject, direction, line } = parsed;

  // An unknown market is manual review even when the player has no row.
  // Checking this after the void would refund a bet we cannot grade.
  const getter = PROP_STATS[marketKey];
  if (!getter) {
    const detail = `unknown stat ${marketKey}; left pending for manual review`;
    console.log(detail);
    return { result: 'pending', detail, line, stat_key: marketKey };
  }

  if (statline === null) {
    return {
      result: 'void',
      detail: `VOID ${subject} did not play (no statline after the box score was final); stake returned`,
      line,
      stat_key: marketKey,
    };
  }

  const actual = getter(statline);
  if (actual === null) {
    const detail = `${subject} ${marketKey} is absent on the statline; left pending for manual review`;
    console.log(detail);
    return { result: 'pending', detail, line, stat_key: marketKey };
  }
  if (!Number.isFinite(actual)) {
    const detail = `${subject} ${marketKey} is not a finite stat; left pending for manual review`;
    console.log(detail);
    return { result: 'pending', detail, line, stat_key: marketKey };
  }

  if (actual === line && isIntegerLine(line)) {
    return {
      result: 'push',
      detail: `${subject} ${actual} ties the integer line ${line}`,
      actual,
      line,
      stat_key: marketKey,
    };
  }
  const won = direction === 'over' ? actual > line : actual < line;
  return {
    result: won ? 'win' : 'loss',
    detail: `${subject} ${actual} vs ${direction} ${line}`,
    actual,
    line,
    stat_key: marketKey,
  };
}

export interface PropTarget {
  statKey: string;
  subjectPlayerId: number;
  side: string;
  source: 'snapshot' | 'market';
}

/**
 * Prefer the copy written onto the bet at submit. The market row is the
 * fallback, and it is often already gone: sync_games prunes finished games
 * and the bet's market_id is set null.
 */
export function resolvePropTarget(
  bet: {
    stat_key?: string | null;
    subject_player_id?: number | null;
    side?: string | null;
  },
  market: { stat_key?: string | null; subject_player_id?: number | null } | null,
): PropTarget | { error: string } {
  const side = bet.side ?? '';
  if (bet.stat_key && bet.subject_player_id != null) {
    return {
      statKey: bet.stat_key,
      subjectPlayerId: Number(bet.subject_player_id),
      side,
      source: 'snapshot',
    };
  }
  if (market?.stat_key && market.subject_player_id != null) {
    return {
      statKey: market.stat_key,
      subjectPlayerId: Number(market.subject_player_id),
      side,
      source: 'market',
    };
  }
  return { error: 'no stat snapshot and the market row is gone; left pending' };
}
