/**
 * Moneyline (h2h) selection.
 *
 * sync_games used to keep an h2h market only when both outcome names were
 * exactly the event's home_team and away_team, and only from DraftKings or,
 * if DraftKings was absent, whichever book the API listed first. College
 * names are not that stable. On 20 Nov 2026 the board had no moneyline for
 * Loyola (MD), Wagner, Le Moyne, MVSU, E. Illinois, Wofford, Ole Miss,
 * Chattanooga, Samford, and Nebraska @ Iowa, while the spread and total for
 * several of those games were written. A bookmaker's outcome name ("Loyola
 * Maryland", "Eastern Illinois", "Mississippi", "LeMoyne") is the same school
 * as the event name and was being dropped.
 *
 * The moneyline is one price from one book. DraftKings first, then Fanatics,
 * then the other books in the order the API sent them. Both sides come from
 * that one book. A home price from DraftKings and an away price from Fanatics
 * is not a market anyone is offering.
 *
 * A price worse than -10000 on either side is off the board (Tennessee
 * -20000). That book is skipped in case another book has a real line. If
 * none does, the moneyline is not written and the previous one is retired.
 * Two moderate minus prices (a pick'em, -110/-110 or -105/-115) stay up.
 */

export const BOOK_PREFERENCE = ['draftkings', 'fanatics'] as const;

/** Strictly worse than this American price is off the board. -10000 itself stays. */
export const OFF_BOARD_AMERICAN = -10000;

/**
 * How old a stored moneyline may be and still be offered.
 *
 * sync_games runs every 4 hours and the mid-tier refresh is every 4 hours, so
 * a line that is being kept is well under this. 18 hours is four missed
 * cycles plus slack: one failed run does not blank the board, and a price
 * last written two days ago (the 18 Nov UFC lines still up on 20 Nov) is off
 * the board.
 */
export const MONEYLINE_MAX_AGE_MS = 18 * 60 * 60 * 1000;

export interface H2HOutcome {
  name: string;
  price: number;
  point?: number;
}

export interface H2HMarket {
  key: string;
  outcomes?: H2HOutcome[];
  bookmaker?: string;
}

export interface H2HBook {
  key: string;
  markets?: H2HMarket[];
}

export interface MoneylinePick {
  bookmaker: string;
  /** Away side, stored as odds_a. */
  awayPrice: number;
  /** Home side, stored as odds_b. */
  homePrice: number;
}

const STATE_ABBREV: Record<string, string> = {
  al: 'alabama', ak: 'alaska', az: 'arizona', ar: 'arkansas', ca: 'california',
  co: 'colorado', ct: 'connecticut', dc: 'district of columbia', fl: 'florida',
  ga: 'georgia', hi: 'hawaii', ia: 'iowa', id: 'idaho', il: 'illinois',
  in: 'indiana', ks: 'kansas', ky: 'kentucky', la: 'louisiana', ma: 'massachusetts',
  md: 'maryland', me: 'maine', mi: 'michigan', mn: 'minnesota', mo: 'missouri',
  ms: 'mississippi', mt: 'montana', nc: 'north carolina', nd: 'north dakota',
  ne: 'nebraska', nh: 'new hampshire', nj: 'new jersey', nm: 'new mexico',
  nv: 'nevada', ny: 'new york', oh: 'ohio', ok: 'oklahoma', or: 'oregon',
  pa: 'pennsylvania', ri: 'rhode island', sc: 'south carolina', sd: 'south dakota',
  tn: 'tennessee', tx: 'texas', ut: 'utah', va: 'virginia', vt: 'vermont',
  wa: 'washington', wi: 'wisconsin', wv: 'west virginia', wy: 'wyoming',
};

/**
 * Names that are the same school after punctuation and mascots are gone.
 * Keys are the normalized form. Values are the form both sides compare as.
 * Mississippi State is not here: it is not Ole Miss.
 */
const ALIASES: Record<string, string> = {
  'ole miss': 'mississippi',
  'mvsu': 'mississippi valley state',
  'mississippi valley': 'mississippi valley state',
  'miss valley state': 'mississippi valley state',
  'lemoyne': 'le moyne',
  'loyola md': 'loyola maryland',
  'e illinois': 'eastern illinois',
  'w illinois': 'western illinois',
  'n illinois': 'northern illinois',
  's illinois': 'southern illinois',
  'e michigan': 'eastern michigan',
  'w michigan': 'western michigan',
  'c michigan': 'central michigan',
  'n michigan': 'northern michigan',
  'e kentucky': 'eastern kentucky',
  'w kentucky': 'western kentucky',
  'e washington': 'eastern washington',
  'w virginia': 'west virginia',
  'n carolina': 'north carolina',
  's carolina': 'south carolina',
  'e carolina': 'east carolina',
  'w carolina': 'western carolina',
  'n iowa': 'northern iowa',
  's alabama': 'south alabama',
  'n alabama': 'north alabama',
  'n texas': 'north texas',
  's miss': 'southern mississippi',
  'uconn': 'connecticut',
  'lsu': 'louisiana state',
  'usc': 'southern california',
  'smu': 'southern methodist',
  'tcu': 'texas christian',
  'ucf': 'central florida',
  'byu': 'brigham young',
  'unlv': 'nevada las vegas',
  'utep': 'texas el paso',
  'utsa': 'texas san antonio',
  'fau': 'florida atlantic',
  'fiu': 'florida international',
  'niu': 'northern illinois',
  'siu': 'southern illinois',
  'wku': 'western kentucky',
  'etsu': 'east tennessee state',
  'app state': 'appalachian state',
  'umass': 'massachusetts',
  'pitt': 'pittsburgh',
  'st johns': 'saint johns',
  'texas a and m': 'texas am',
  'texas am': 'texas am',
};

/** Trailing words that are a nickname, not a different school. */
const MASCOTS = new Set([
  'aggies', 'aztecs', 'badgers', 'bearcats', 'bears', 'beavers', 'billikens',
  'bison', 'blazers', 'bluejays', 'bobcats', 'boilermakers', 'braves', 'broncos',
  'bruins', 'buckeyes', 'bulldogs', 'cardinal', 'cardinals', 'catamounts',
  'cavaliers', 'chanticleers', 'chippewas', 'colonials', 'cornhuskers', 'cougars',
  'cowboys', 'cyclones', 'deacons', 'demon', 'devils', 'dolphins', 'ducks',
  'dukes', 'eagles', 'explorers', 'falcons', 'flashes', 'flyers', 'friars',
  'frogs', 'gamecocks', 'gaels', 'gators', 'golden', 'gophers', 'governors',
  'greyhounds', 'hawkeyes', 'hawks', 'heels', 'hilltoppers', 'hokies', 'hoosiers',
  'hornets', 'hurricanes', 'huskies', 'illini', 'irish', 'jackets', 'jaguars',
  'jaspers', 'jayhawks', 'knights', 'leathernecks', 'lions', 'lobos', 'longhorns',
  'midshipmen', 'miners', 'minutemen', 'mocs', 'monarchs', 'mountaineers',
  'musketeers', 'mustangs', 'nittany', 'orange', 'owls', 'panthers', 'patriots',
  'peacocks', 'penguins', 'phoenix', 'pirates', 'privateers', 'racers', 'raiders',
  'rams', 'razorbacks', 'rebels', 'redbirds', 'redhawks', 'retrievers', 'rockets',
  'salukis', 'scarlet', 'seahawks', 'seminoles', 'shockers', 'skyhawks',
  'sooners', 'spartans', 'spiders', 'sun', 'terriers', 'tide', 'tigers',
  'titans', 'trojans', 'utes', 'volunteers', 'warriors', 'wave', 'wildcats',
  'wolfpack', 'wolverines', 'yellow', 'zips', 'fighting', 'crimson', 'blue',
  'red', 'mean', 'green', 'tar', 'horned',
]);

/**
 * Extra tokens that mean a different school, not a nickname.
 * "Miami" is not "Miami Ohio". "Mississippi" is not "Mississippi State".
 */
const DISTINGUISHERS = new Set([
  'state', 'eastern', 'western', 'northern', 'southern', 'central',
  'north', 'south', 'east', 'west', 'tech', 'am', 'marymount', 'ohio',
  'florida', 'alabama', 'carolina', 'illinois', 'michigan', 'kentucky',
  'virginia', 'texas', 'iowa', 'mississippi', 'california', 'georgia',
  'dakota', 'international',
  ...Object.values(STATE_ABBREV),
]);

export function isOffBoardAmerican(price: unknown): boolean {
  return typeof price !== 'number' || !Number.isFinite(price) || price < OFF_BOARD_AMERICAN;
}

export function moneylineTooOld(
  updatedAt: string | null | undefined,
  nowMs: number,
): boolean {
  const at = Date.parse(updatedAt ?? '');
  if (!Number.isFinite(at)) return true;
  return nowMs - at > MONEYLINE_MAX_AGE_MS;
}

/**
 * A moneyline the server must refuse. Spreads and totals are not checked:
 * a pick'em moneyline (both sides moderate minus prices) is not this, and
 * neither is -10000 exactly. Worse than -10000 on either stored side, a
 * submitted moneyline price that bad, or a moneyline older than
 * MONEYLINE_MAX_AGE_MS, is off the board.
 */
export function moneylineOffBoardError(
  market: {
    type?: string | null;
    odds_a?: number | null;
    odds_b?: number | null;
    updated_at?: string | null;
  },
  submittedOdds: number | undefined,
  nowMs: number,
): 'off_the_board' | null {
  if (market.type !== 'moneyline' && market.type !== 'h2h') return null;
  if (isOffBoardAmerican(market.odds_a) || isOffBoardAmerican(market.odds_b)) {
    return 'off_the_board';
  }
  if (submittedOdds !== undefined && isOffBoardAmerican(submittedOdds)) {
    return 'off_the_board';
  }
  if (moneylineTooOld(market.updated_at, nowMs)) return 'off_the_board';
  return null;
}

/** Shared bettable rows to retire when the latest feed has no acceptable moneyline. */
export function bettableSharedIds(
  rows: readonly { id: string; bookie_id?: string | null; bettable?: boolean | null }[],
): string[] {
  return rows
    .filter((r) => (r.bookie_id ?? null) == null && r.bettable !== false)
    .map((r) => r.id);
}

export function normalizeTeamName(raw: string | null | undefined): string {
  if (!raw) return '';
  let s = raw.normalize('NFD').replace(/\p{M}/gu, '');
  s = s.toLowerCase().replace(/&/g, ' and ');
  s = s.replace(/\(([^)]*)\)/g, (_, inner: string) => {
    const token = String(inner).trim().toLowerCase().replace(/\./g, '');
    return ` ${STATE_ABBREV[token] ?? token} `;
  });
  s = s.replace(/[.'’`]/g, '');
  s = s.replace(/[-/]/g, ' ');
  s = s.replace(/\s+/g, ' ').trim();
  s = s.replace(/ st$/, ' state');
  return s;
}

function stripTrailingMascots(name: string): string {
  const tokens = name.split(' ').filter(Boolean);
  while (tokens.length > 1 && MASCOTS.has(tokens[tokens.length - 1])) tokens.pop();
  return tokens.join(' ');
}

export function canonicalTeamName(raw: string | null | undefined): string {
  let s = normalizeTeamName(raw);
  s = ALIASES[s] ?? s;
  s = stripTrailingMascots(s);
  s = ALIASES[s] ?? s;
  return s;
}

function leftoverScore(shorter: string, longer: string): number {
  const a = shorter.split(' ').filter(Boolean);
  const b = longer.split(' ').filter(Boolean);
  if (a.length === 0 || a.length >= b.length) return 0;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return 0;
  const extra = b.slice(a.length);
  if (extra.some((token) => DISTINGUISHERS.has(token))) return 0;
  if (extra.length === 1 && extra[0].length >= 3) return 80;
  if (extra.length > 1 && extra.every((token) => MASCOTS.has(token))) return 80;
  return 0;
}

/** 100 same school, 80 same school plus a nickname, 0 not the same school. */
export function matchScore(
  a: string | null | undefined,
  b: string | null | undefined,
): number {
  const left = canonicalTeamName(a);
  const right = canonicalTeamName(b);
  if (!left || !right) return 0;
  if (left === right) return 100;
  if (left.replace(/ /g, '') === right.replace(/ /g, '')) return 95;
  return Math.max(leftoverScore(left, right), leftoverScore(right, left));
}

export function sameTeam(
  a: string | null | undefined,
  b: string | null | undefined,
): boolean {
  return matchScore(a, b) >= 80;
}

const NOT_A_TEAM = new Set(['over', 'under', 'draw', 'odd', 'even']);

/**
 * Map outcomes onto home and away. Exact names win. Aliases and nicknames
 * are next. A tie between the two ways of assigning the outcomes is a
 * refusal: guessing the side would put the home price on the away team.
 */
export function pairTeamOutcomes<T extends { name: string }>(
  outcomes: readonly T[],
  home: string | null | undefined,
  away: string | null | undefined,
): { home: T; away: T } | null {
  if (!home || !away) return null;
  const sides = outcomes.filter((o) => o.name && !NOT_A_TEAM.has(o.name.trim().toLowerCase()));
  let best: { home: T; away: T; score: number } | null = null;
  let tied = false;
  for (let i = 0; i < sides.length; i++) {
    for (let j = 0; j < sides.length; j++) {
      if (i === j) continue;
      const homeScore = matchScore(sides[i].name, home);
      const awayScore = matchScore(sides[j].name, away);
      if (homeScore < 80 || awayScore < 80) continue;
      const score = homeScore + awayScore;
      if (!best || score > best.score) {
        best = { home: sides[i], away: sides[j], score };
        tied = false;
      } else if (score === best.score && (sides[i] !== best.home || sides[j] !== best.away)) {
        tied = true;
      }
    }
  }
  if (!best || tied) return null;
  return { home: best.home, away: best.away };
}

export function orderBookmakers<T extends { key: string }>(books: readonly T[]): T[] {
  return books
    .map((book, index) => ({ book, index }))
    .sort((a, b) => {
      const ai = BOOK_PREFERENCE.indexOf(a.book.key as typeof BOOK_PREFERENCE[number]);
      const bi = BOOK_PREFERENCE.indexOf(b.book.key as typeof BOOK_PREFERENCE[number]);
      const ar = ai === -1 ? BOOK_PREFERENCE.length : ai;
      const br = bi === -1 ? BOOK_PREFERENCE.length : bi;
      if (ar !== br) return ar - br;
      return a.index - b.index;
    })
    .map((row) => row.book);
}

/**
 * One moneyline, both sides from the same book.
 * DraftKings, then Fanatics, then the rest. A book whose names do not map
 * onto both teams is skipped. A book with either side worse than -10000 is
 * skipped so a sane book behind it can still price the game. Null means off
 * the board: do not insert, and retire the one we had.
 */
export function selectMoneyline(
  books: readonly H2HBook[] | null | undefined,
  home: string | null | undefined,
  away: string | null | undefined,
): MoneylinePick | null {
  if (!books || !home || !away) return null;
  for (const book of orderBookmakers(books)) {
    const market = (book.markets ?? []).find((m) => m.key === 'h2h');
    if (!market?.outcomes?.length) continue;
    const paired = pairTeamOutcomes(market.outcomes, home, away);
    if (!paired) continue;
    if (isOffBoardAmerican(paired.home.price) || isOffBoardAmerican(paired.away.price)) continue;
    return {
      bookmaker: book.key,
      awayPrice: paired.away.price,
      homePrice: paired.home.price,
    };
  }
  return null;
}
