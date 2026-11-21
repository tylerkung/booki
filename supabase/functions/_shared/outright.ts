/**
 * Futures (outright) identity and the manual-settlement key.
 *
 * An outright event is stored with away_team 'Outright'. The pick's own
 * `side` is the selection name. market_id is not an identity: a refresh can
 * delete the market row and the bet's market_id becomes NULL.
 */

export function isOutrightEvent(awayTeam: string | null | undefined): boolean {
  return awayTeam === 'Outright';
}

/**
 * sync_games marks a scheduled game final 3 hours after start. A future
 * stays scheduled (and closed for betting, which submit already enforces)
 * until settle_outright records a result and sets status final itself.
 */
export function shouldClockFinalize(
  event: { status?: string | null; away_team?: string | null; start_time?: string | null },
  cutoff: Date,
): boolean {
  if (event.status !== 'scheduled') return false;
  if (isOutrightEvent(event.away_team)) return false;
  if (!event.start_time) return false;
  const start = new Date(event.start_time).getTime();
  return Number.isFinite(start) && start < cutoff.getTime();
}

export function isOutrightMarket(market: string | null | undefined): boolean {
  const name = (market ?? '').toLowerCase();
  return name === 'outright' || name === 'futures';
}

/**
 * Stable across retries of grade_bet. A new click sends a new request
 * idempotency key; the settlement key does not, so the second click finds
 * the settlement settle_bet_tx already posted.
 */
export function manualSingleSettlementKey(betId: string): string {
  return `manual_settle_${betId}_v1`;
}

/** The key settle_outright_tx passes to settle_bet_tx. One per single, forever. */
export function outrightSettlementKey(betId: string): string {
  return `outright_settle_${betId}_v1`;
}

/**
 * Compare a pick's side to the recorded winner.
 *
 * Accents and punctuation fold, and a trailing price is ignored in either
 * form (" +12000" or "(+2000)"). "St. Louis Blues" matches "St Louis Blues".
 * "Warriors" does not match "Golden State Warriors".
 *
 * The accent map is the same string as normalize_outright_selection in
 * migration 067. outright_match_vectors.json is the shared contract.
 */
const ACCENT_FROM =
  'ÁÀÂÄÃÅĀĂĄáàâäãåāăąÉÈÊËĒĔĖĘéèêëēĕėęÍÌÎÏĪĬĮíìîïīĭįÓÒÔÖÕŌŎŐóòôöõōŏőÚÙÛÜŪŬŮŰúùûüūŭůűÝŸýÿÑñÇçČčĆćŠšŽž';
const ACCENT_TO =
  'AAAAAAAAAaaaaaaaaaEEEEEEEEeeeeeeeeIIIIIIIiiiiiiiOOOOOOOOooooooooUUUUUUUUuuuuuuuuYYyyNnCcCcCcSsZz';

function foldAccents(value: string): string {
  let out = '';
  for (const ch of value) {
    const at = ACCENT_FROM.indexOf(ch);
    out += at >= 0 ? ACCENT_TO[at] : ch;
  }
  return out;
}

export function outrightSideKey(value: string | null | undefined): string {
  return foldAccents(value ?? '')
    .toLowerCase()
    .replace(/\s*\(\s*[+-]\d+(?:\.\d+)?\s*\)\s*$/u, '')
    .replace(/\s+[+-]\d+(?:\.\d+)?\s*$/u, '')
    .replace(/[^a-z0-9]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

export function normalizeOutrightSelection(value: string | null | undefined): string {
  return outrightSideKey(value);
}

export function outrightSelectionMatches(
  side: string | null | undefined,
  winner: string | null | undefined,
): boolean {
  const left = outrightSideKey(side);
  const right = outrightSideKey(winner);
  return left !== '' && left === right;
}

/** Void the whole event, or win on a name match and loss otherwise. No dead heat. */
export function outrightGrade(
  side: string | null | undefined,
  winner: string | null | undefined,
  voidEvent: boolean,
): 'win' | 'loss' | 'void' {
  if (voidEvent) return 'void';
  return outrightSelectionMatches(side, winner) ? 'win' : 'loss';
}

export interface AwaitingFuture {
  event_id: string;
  name: string;
  sport: string;
  league: string | null;
  start_time: string;
  status: string;
  open_picks: number;
  open_stake: number;
  selections: string[];
}

export interface AwaitingInputs {
  bets: Array<{ event_id: string | null; side: string | null; stake: number | string | null }>;
  events: Array<{
    id: string;
    away_team: string | null;
    home_team: string | null;
    name?: string | null;
    start_time: string;
    status: string;
    sport: string | null;
    league: string | null;
  }>;
  markets: Array<{ event_id: string | null; type: string | null; side_a: string | null }>;
  results: Array<{ event_id: string }>;
}

/**
 * Futures that still have an open pick and no recorded result.
 * Selections are the pick sides plus any outright market names still stored,
 * so a deleted market row does not hide the team someone actually picked.
 */
export function futuresAwaitingResult(input: AwaitingInputs): AwaitingFuture[] {
  const recorded = new Set(input.results.map((row) => row.event_id.toLowerCase()));
  const eventsById = new Map(
    input.events
      .filter((event) => isOutrightEvent(event.away_team))
      .map((event) => [event.id.toLowerCase(), event]),
  );
  const grouped = new Map<string, { picks: number; stake: number; sides: Set<string> }>();

  for (const bet of input.bets) {
    const id = (bet.event_id ?? '').toLowerCase();
    if (!eventsById.has(id) || recorded.has(id)) continue;
    const row = grouped.get(id) ?? { picks: 0, stake: 0, sides: new Set<string>() };
    row.picks += 1;
    row.stake += Number(bet.stake) || 0;
    if (bet.side) row.sides.add(bet.side);
    grouped.set(id, row);
  }

  for (const market of input.markets) {
    if ((market.type ?? '').toLowerCase() !== 'outright') continue;
    const id = (market.event_id ?? '').toLowerCase();
    const row = grouped.get(id);
    if (!row || !market.side_a) continue;
    row.sides.add(market.side_a);
  }

  return [...grouped.entries()]
    .map(([id, row]) => {
      const event = eventsById.get(id)!;
      return {
        event_id: event.id,
        name: event.home_team || event.name || 'Future',
        sport: event.sport ?? '',
        league: event.league,
        start_time: event.start_time,
        status: event.status,
        open_picks: row.picks,
        open_stake: Math.round(row.stake * 100) / 100,
        selections: [...row.sides].sort((a, b) => a.localeCompare(b)),
      };
    })
    .sort((a, b) => b.open_picks - a.open_picks || a.start_time.localeCompare(b.start_time));
}
