/**
 * What a bet row is allowed to store.
 *
 * A parlay leg was written with market = a market UUID and side = 'b'.
 * The score grader then had no market type, fell through to "manual grading
 * required", and settled the leg as a push. The client may send an indicator
 * ('a' / 'b'); the row must store the market type and one of the market's
 * own side labels.
 */

export const KNOWN_MARKET_TYPES = [
  'moneyline',
  'h2h',
  'spread',
  'spreads',
  'alternate_spread',
  'total',
  'totals',
  'over_under',
  'alternate_total',
  'team_total',
  'team_totals',
  'odd_even',
  'outright',
  'player_prop',
] as const;

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function isKnownMarketType(market: string | null | undefined): boolean {
  if (!market) return false;
  return (KNOWN_MARKET_TYPES as readonly string[]).includes(market.toLowerCase());
}

export interface OfferedSides {
  side_a: string | null;
  side_b: string | null;
}

/**
 * Error string when the values we are about to INSERT are not a real market.
 * `side` here is the label that will be stored, not the 'a'/'b' indicator.
 */
export function legStorageError(
  marketType: string | null | undefined,
  side: string | null | undefined,
  offered: OfferedSides,
): string | null {
  if (!isKnownMarketType(marketType)) {
    return `market must be a known market type, not "${marketType ?? ''}"`;
  }
  const label = (side ?? '').trim();
  if (!label) return 'side is missing';
  if (UUID_RE.test(label)) {
    return `side must be a selection on the market, not an id ("${label}")`;
  }
  if (label === 'a' || label === 'b') {
    return `side must be the selection label, not "${label}"`;
  }
  const offeredSides = [offered.side_a, offered.side_b].filter(
    (s): s is string => typeof s === 'string' && s.length > 0,
  );
  if (!offeredSides.includes(label)) {
    return `side "${label}" is not one of this market's sides`;
  }
  return null;
}

export interface MarketRow {
  id: string;
  type: string | null;
  side_a: string | null;
  side_b: string | null;
  stat_key?: string | null;
  subject_player_id?: number | null;
}

export interface PropSnapshot {
  stat_key: string | null;
  subject_player_id: number | null;
  prop_line: number | null;
}

/** Pull the numeric line out of "Name Over 2.5" / "Name Under 79.5". Yes/No is 0.5. */
export function lineFromSide(side: string): number | null {
  const ou = side.match(/\s+(?:Over|Under)\s+([0-9]+(?:\.[0-9]+)?)\s*$/i);
  if (ou) return Number(ou[1]);
  if (/\s+(?:Yes|No)\s*$/i.test(side)) return 0.5;
  return null;
}

export function propSnapshotFromMarket(market: MarketRow, side: string): PropSnapshot {
  if ((market.type ?? '').toLowerCase() !== 'player_prop') {
    return { stat_key: null, subject_player_id: null, prop_line: null };
  }
  return {
    stat_key: market.stat_key ?? null,
    subject_player_id: market.subject_player_id ?? null,
    prop_line: lineFromSide(side),
  };
}

export function propSnapshotError(marketType: string, snap: PropSnapshot): string | null {
  if (marketType.toLowerCase() !== 'player_prop') return null;
  if (!snap.stat_key || snap.subject_player_id == null || snap.prop_line == null) {
    return 'This prop is missing the stat needed to grade it';
  }
  return null;
}

export type ResolvedLeg =
  | { ok: true; market: string; side: string; snapshot: PropSnapshot }
  | { ok: false; error: string };

/**
 * Turn a client indicator into the row we store.
 * Missing market, unknown type, or a side that is not on the market is a 400.
 */
export function resolveStoredLeg(
  market: MarketRow | null | undefined,
  indicator: string | null | undefined,
): ResolvedLeg {
  if (!market) return { ok: false, error: 'Market not found' };
  if (indicator !== 'a' && indicator !== 'b') {
    return { ok: false, error: `side indicator must be 'a' or 'b', not "${indicator ?? ''}"` };
  }
  const side = indicator === 'a' ? market.side_a : market.side_b;
  const marketType = market.type;
  const storageError = legStorageError(marketType, side, market);
  if (storageError || !marketType || !side) {
    return { ok: false, error: storageError ?? 'market or side is missing' };
  }
  const snapshot = propSnapshotFromMarket(market, side);
  const snapError = propSnapshotError(marketType, snapshot);
  if (snapError) return { ok: false, error: snapError };
  return { ok: true, market: marketType, side, snapshot };
}
