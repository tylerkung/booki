import { corsHeaders } from '../_shared/cors.ts';
import { createServiceClient } from '../_shared/supabase.ts';
import { checkIdempotency, storeIdempotency } from '../_shared/idempotency.ts';
import { selectAllIn, selectAllPaged } from '../_shared/pagination.ts';
import { recordQuota, resetQuota, getQuotaSnapshot } from '../_shared/odds_quota.ts';

/**
 * Sports to sync from the Odds API.
 * These are the main US sports leagues.
 */
const SPORTS_TO_SYNC = [
  'basketball_nba',
  'basketball_ncaab',
  'americanfootball_nfl',
  'americanfootball_ncaaf',
  'baseball_mlb',
  'icehockey_nhl',
  'mma_mixed_martial_arts',
  'tennis_atp_australian_open',
  'tennis_atp_french_open',
  'tennis_atp_us_open',
  'tennis_atp_wimbledon',
  'tennis_wta_australian_open',
  'tennis_wta_french_open',
  'tennis_wta_us_open',
  'tennis_wta_wimbledon',
];

/**
 * Futures/championship markets to sync from the Odds API.
 */
const FUTURES_TO_SYNC = [
  'basketball_nba_championship_winner',
  'basketball_ncaab_championship_winner',
  'americanfootball_nfl_super_bowl_winner',
  'americanfootball_ncaaf_championship_winner',
  'baseball_mlb_world_series_winner',
  'icehockey_nhl_championship_winner',
  'golf_masters_tournament_winner',
  'golf_pga_championship_winner',
  'golf_the_open_championship_winner',
  'golf_us_open_winner',
];

/**
 * Maps API sport keys to app-friendly sport and league names.
 * This is the same mapping as OddsAPIMapper.swift in the iOS app.
 */
const SPORT_KEY_MAPPING: Record<string, { sport: string; league: string }> = {
  'americanfootball_nfl': { sport: 'Football', league: 'NFL' },
  'americanfootball_ncaaf': { sport: 'Football', league: 'NCAAF' },
  'basketball_nba': { sport: 'Basketball', league: 'NBA' },
  'basketball_ncaab': { sport: 'Basketball', league: 'NCAAB' },
  'basketball_wnba': { sport: 'Basketball', league: 'WNBA' },
  'baseball_mlb': { sport: 'Baseball', league: 'MLB' },
  'icehockey_nhl': { sport: 'Hockey', league: 'NHL' },
  'soccer_epl': { sport: 'Soccer', league: 'EPL' },
  'soccer_usa_mls': { sport: 'Soccer', league: 'MLS' },
  'soccer_germany_bundesliga': { sport: 'Soccer', league: 'Bundesliga' },
  'soccer_spain_la_liga': { sport: 'Soccer', league: 'La Liga' },
  'soccer_italy_serie_a': { sport: 'Soccer', league: 'Serie A' },
  'soccer_france_ligue_one': { sport: 'Soccer', league: 'Ligue 1' },
  'mma_mixed_martial_arts': { sport: 'MMA', league: 'UFC' },
  'boxing_boxing': { sport: 'Boxing', league: 'Boxing' },
  // Golf tournaments
  'golf_pga_championship': { sport: 'Golf', league: 'PGA' },
  'golf_masters_tournament': { sport: 'Golf', league: 'Masters' },
  'golf_the_open_championship': { sport: 'Golf', league: 'The Open' },
  'golf_us_open': { sport: 'Golf', league: 'US Open' },
  // Tennis - ATP tournaments
  'tennis_atp_australian_open': { sport: 'Tennis', league: 'ATP' },
  'tennis_atp_french_open': { sport: 'Tennis', league: 'ATP' },
  'tennis_atp_us_open': { sport: 'Tennis', league: 'ATP' },
  'tennis_atp_wimbledon': { sport: 'Tennis', league: 'ATP' },
  // Tennis - WTA tournaments
  'tennis_wta_australian_open': { sport: 'Tennis', league: 'WTA' },
  'tennis_wta_french_open': { sport: 'Tennis', league: 'WTA' },
  'tennis_wta_us_open': { sport: 'Tennis', league: 'WTA' },
  'tennis_wta_wimbledon': { sport: 'Tennis', league: 'WTA' },
  // Futures / Championship winners
  'basketball_nba_championship_winner': { sport: 'Basketball', league: 'NBA' },
  'basketball_ncaab_championship_winner': { sport: 'Basketball', league: 'NCAAB' },
  'americanfootball_nfl_super_bowl_winner': { sport: 'Football', league: 'NFL' },
  'americanfootball_ncaaf_championship_winner': { sport: 'Football', league: 'NCAAF' },
  'baseball_mlb_world_series_winner': { sport: 'Baseball', league: 'MLB' },
  'icehockey_nhl_championship_winner': { sport: 'Hockey', league: 'NHL' },
  'golf_masters_tournament_winner': { sport: 'Golf', league: 'Masters' },
  'golf_pga_championship_winner': { sport: 'Golf', league: 'PGA' },
  'golf_the_open_championship_winner': { sport: 'Golf', league: 'The Open' },
  'golf_us_open_winner': { sport: 'Golf', league: 'US Open' },
};

/**
 * Parses a sport key into sport and league when not in the mapping.
 * Format is usually "sport_league" like "basketball_nba".
 */
function parseSportKey(key: string): { sport: string; league: string } {
  const parts = key.split('_');
  if (parts.length >= 2) {
    const sport = parts[0].charAt(0).toUpperCase() + parts[0].slice(1);
    const league = parts.slice(1).join(' ').toUpperCase();
    return { sport, league };
  }
  return { sport: key.charAt(0).toUpperCase() + key.slice(1), league: '' };
}

/**
 * Gets sport and league from an API sport key.
 */
function getSportAndLeague(sportKey: string): { sport: string; league: string } {
  return SPORT_KEY_MAPPING[sportKey] || parseSportKey(sportKey);
}

/**
 * Odds API response types
 */
interface OddsOutcome {
  name: string;
  price: number;
  point?: number;
  /**
   * Present on markets whose subject is not the outcome itself: team_totals
   * puts the TEAM here and Over/Under in `name`, and player props put the
   * player here. Absent on h2h/spreads/totals.
   */
  description?: string;
}

interface OddsMarket {
  key: string;
  last_update: string;
  outcomes: OddsOutcome[];
}

interface OddsBookmaker {
  key: string;
  title: string;
  last_update: string;
  markets: OddsMarket[];
}

interface OddsEvent {
  id: string;
  sport_key: string;
  sport_title: string;
  commence_time: string;
  home_team: string | null;
  away_team: string | null;
  bookmakers?: OddsBookmaker[];
}

/**
 * How many Odds API requests may be in flight at once. The provider is fine
 * with modest concurrency; the cap exists to stay polite rather than to
 * satisfy a documented limit.
 */
const ODDS_FETCH_CONCURRENCY = 5;

/**
 * How far ahead odds are stored. Members see odds 48h ahead; storing a wider
 * window means a game already has lines when it becomes visible instead of
 * showing a blank price. Outrights are exempt — see the market sync below.
 */
const ODDS_STORAGE_WINDOW_MS = 7 * 24 * 60 * 60 * 1000;

/**
 * Sports that additionally get the per-event market bundle.
 *
 * The featured endpoint (h2h/spreads/totals) costs 3 credits and covers every
 * game of a sport at once. Everything below is served ONLY per event, so cost
 * is markets x games — deliberately limited to the two leagues where a deep
 * board is worth paying for. MLB at ~100 games a week and NCAAF Saturdays
 * would multiply this several times over for markets far fewer people bet.
 */
const DEEP_MARKET_SPORTS = ['americanfootball_nfl', 'basketball_nba'];

/**
 * Only markets that can be settled from the final score, which is all the
 * Odds API /scores endpoint returns — no period splits, no player statistics.
 *
 * Quarters, halves and player props are all purchasable and none of them can
 * be graded automatically, so they are deliberately absent: a market nobody can
 * settle is a support burden, not a feature.
 *
 * Measured cost on an NFL game: 4 credits, ~159 stored rows.
 */
// odd_even is DELIBERATELY ABSENT until iOS ships a MarketType case for it.
//
// The other three map to cases that already exist in Booki/Models/Market.swift,
// so shipped builds render them correctly. odd_even does not, and
// SyncService's `MarketType(rawValue:) ?? .moneyline` would coerce it: members
// on the current App Store build would see a "Moneyline" market whose two sides
// are Odd and Even. Grading is unaffected — the server reads market.type from
// the row — but it is visibly wrong, and it would start the moment NFL games
// enter the 3-day window.
//
// Re-add it in the same change that adds the iOS case. See tasks/ios-pending.md.
const DEEP_MARKETS = ['alternate_spreads', 'alternate_totals', 'team_totals'];

/**
 * How close to kickoff a game must be to earn its per-event fetch.
 *
 * Tighter than ODDS_STORAGE_WINDOW_MS on purpose. Alternate lines are ~157
 * rows per game against 6 for the core three, so fetching them for every game
 * inside the 7-day storage window would multiply the markets table by an order
 * of magnitude for lines nobody is looking at yet.
 */
const DEEP_MARKET_WINDOW_MS = 3 * 24 * 60 * 60 * 1000;

/**
 * Runs `fn` over `items` with at most `limit` promises in flight, preserving
 * input order in the result. Used to parallelise Odds API fetches, which are
 * the dominant cost of a sync run.
 */
async function mapWithConcurrency<T, R>(
  items: T[],
  limit: number,
  fn: (item: T) => Promise<R>,
): Promise<R[]> {
  const results = new Array<R>(items.length);
  let cursor = 0;

  const workers = Array.from(
    { length: Math.min(limit, items.length) },
    async () => {
      while (true) {
        const index = cursor++;
        if (index >= items.length) return;
        results[index] = await fn(items[index]);
      }
    },
  );

  await Promise.all(workers);
  return results;
}

/**
 * Existing events row, as loaded for the change-detection pass. Carries the
 * comparable columns so a sync can skip rows the provider has not changed.
 */
interface ExistingEventRow {
  id: string;
  external_id: string | null;
  name: string;
  sport: string;
  league: string | null;
  home_team: string;
  away_team: string;
  start_time: string;
  status: string;
}

/**
 * Score response types from The Odds API
 */
interface TeamScore {
  name: string;
  score: string;
}

interface ScoreEvent {
  id: string;
  sport_key: string;
  sport_title: string;
  commence_time: string;
  home_team: string;
  away_team: string;
  completed: boolean;
  scores: TeamScore[] | null;
}

/**
 * Fetches scores from The Odds API for a given sport.
 */
async function fetchScoresFromApi(
  apiKey: string,
  sportKey: string,
  daysFrom: number = 3
): Promise<ScoreEvent[]> {
  const url = new URL(`https://api.the-odds-api.com/v4/sports/${sportKey}/scores/`);
  url.searchParams.set('apiKey', apiKey);
  url.searchParams.set('daysFrom', daysFrom.toString());

  console.log(`Fetching scores for ${sportKey}...`);

  const response = await fetch(url.toString());
  // Read as text first so the payload can be measured. Egress is billed on
  // these bytes, and response.json() discards the length.
  // A response body can only be consumed once, so read it here and reuse it
  // for both the error path and the parse — calling .text() or .json() again
  // throws "Body already consumed".
  const body = await response.text();
  recordQuota(response, `scores:${sportKey}`, body.length);
  if (!response.ok) {
    console.error(`Scores API error for ${sportKey}: ${response.status} - ${body}`);
    return [];
  }

  const data: ScoreEvent[] = JSON.parse(body);
  console.log(`Got ${data.length} score events for ${sportKey}`);
  return data;
}

/**
 * Fetches odds from The Odds API for a given sport.
 */
async function fetchOddsFromApi(
  apiKey: string,
  sportKey: string
): Promise<OddsEvent[]> {
  const url = new URL(`https://api.the-odds-api.com/v4/sports/${sportKey}/odds/`);
  url.searchParams.set('apiKey', apiKey);
  url.searchParams.set('regions', 'us');
  url.searchParams.set('markets', 'h2h,spreads,totals');
  url.searchParams.set('oddsFormat', 'american');

  const response = await fetch(url.toString());
  // Read as text first so the payload can be measured. Egress is billed on
  // these bytes, and response.json() discards the length.
  const body = await response.text();
  recordQuota(response, `odds:${sportKey}`, body.length);

  if (!response.ok) {
    throw new Error(`Odds API error: ${response.status} ${response.statusText}`);
  }

  return JSON.parse(body);
}

/**
 * Fetches the per-event market bundle for one game.
 *
 * Separate from fetchOddsFromApi because the endpoint is different in kind:
 * /events/{id}/odds returns one game and bills markets x regions per call,
 * where /odds returns every game of a sport for the same price. That is the
 * whole reason these markets are gated by sport and by proximity to kickoff.
 *
 * Returns null rather than throwing: one game missing its alternate lines must
 * not fail a sync that is also carrying the core markets for 270 others.
 */
async function fetchEventMarketsFromApi(
  apiKey: string,
  sportKey: string,
  eventExternalId: string,
): Promise<OddsEvent | null> {
  const url = new URL(
    `https://api.the-odds-api.com/v4/sports/${sportKey}/events/${eventExternalId}/odds/`,
  );
  url.searchParams.set('apiKey', apiKey);
  url.searchParams.set('regions', 'us');
  url.searchParams.set('markets', DEEP_MARKETS.join(','));
  url.searchParams.set('oddsFormat', 'american');

  try {
    const response = await fetch(url.toString());
    const body = await response.text();
    recordQuota(response, `deep:${sportKey}`, body.length);

    if (!response.ok) {
      // 422 is the normal answer for a game that offers none of these markets
      // yet, not a fault worth surfacing.
      if (response.status !== 422) {
        console.error(`Deep markets ${eventExternalId}: ${response.status} ${body.slice(0, 120)}`);
      }
      return null;
    }
    return JSON.parse(body) as OddsEvent;
  } catch (err) {
    console.error(`Deep markets ${eventExternalId} failed:`, err);
    return null;
  }
}

/**
 * Fetches outright/futures odds from The Odds API for a given sport.
 * Uses markets=outrights instead of h2h,spreads,totals.
 */
async function fetchOutrightsFromApi(
  apiKey: string,
  sportKey: string
): Promise<OddsEvent[]> {
  const url = new URL(`https://api.the-odds-api.com/v4/sports/${sportKey}/odds/`);
  url.searchParams.set('apiKey', apiKey);
  url.searchParams.set('regions', 'us');
  url.searchParams.set('markets', 'outrights');
  url.searchParams.set('oddsFormat', 'american');

  const response = await fetch(url.toString());
  // Read as text first so the payload can be measured. Egress is billed on
  // these bytes, and response.json() discards the length.
  const body = await response.text();
  recordQuota(response, `outrights:${sportKey}`, body.length);

  if (!response.ok) {
    throw new Error(`Outrights API error: ${response.status} ${response.statusText}`);
  }

  return JSON.parse(body);
}

/**
 * Extracts outright markets from an Odds API event.
 * Each outcome becomes a separate market row.
 */
function extractOutrightMarkets(
  oddsEvent: OddsEvent,
  preferredBookmaker: string = 'draftkings'
): { type: string; side_a: string; side_b: string; odds_a: number; odds_b: number }[] {
  const bookmakers = oddsEvent.bookmakers;
  if (!bookmakers || bookmakers.length === 0) {
    return [];
  }

  const selectedBookmaker =
    bookmakers.find((b) => b.key === preferredBookmaker) || bookmakers[0];

  const outrightMarket = selectedBookmaker.markets.find((m) => m.key === 'outrights');
  if (!outrightMarket) {
    return [];
  }

  return outrightMarket.outcomes.map((outcome) => ({
    type: 'outright',
    side_a: outcome.name,
    side_b: oddsEvent.sport_title,
    odds_a: outcome.price,
    odds_b: 0,
  }));
}

/**
 * Database event record structure for upsert operations.
 */
interface EventRecord {
  id?: string; // UUID from database if existing
  external_id: string;
  external_source: string;
  bookie_id: null; // Shared events have NULL bookie_id
  name: string;
  sport: string;
  league: string;
  home_team: string;
  away_team: string;
  start_time: string; // ISO timestamp
  status: string;
  last_odds_update: string; // ISO timestamp
}

/**
 * Database market record structure for upsert operations.
 */
interface MarketRecord {
  id?: string; // UUID from database if existing
  event_id: string;
  bookie_id: null; // Shared markets have NULL bookie_id
  type: string; // 'moneyline', 'spread', 'total', 'alternate_spread', 'alternate_total'
  side_a: string;
  side_b: string;
  odds_a: number;
  odds_b: number;
}

/**
 * Formats a spread point value (e.g., 3.5 -> "+3.5", -3.5 -> "-3.5").
 */
function formatSpread(value: number): string {
  if (value > 0) {
    return `+${formatNumber(value)}`;
  }
  return formatNumber(value);
}

/**
 * Formats a number, removing unnecessary decimals.
 */
function formatNumber(value: number): string {
  if (Number.isInteger(value)) {
    return String(value);
  }
  return value.toFixed(1);
}

/**
 * Extracts the numeric line value from a side string for use as a composite key.
 * e.g., "Lakers -3.5" -> "-3.5", "Over 220.5" -> "220.5", "Lakers" -> ""
 */
function extractLineValue(sideA: string): string {
  const match = sideA.match(/-?\d+\.?\d*/);
  return match ? match[0] : '';
}

/**
 * Extracts markets from Odds API response for a specific event.
 * Returns array of market objects ready for database insertion.
 */
export function extractMarketsFromOddsEvent(
  oddsEvent: OddsEvent,
  preferredBookmaker: string = 'draftkings'
): { type: string; side_a: string; side_b: string; odds_a: number; odds_b: number }[] {
  const bookmakers = oddsEvent.bookmakers;
  if (!bookmakers || bookmakers.length === 0) {
    return [];
  }

  // Find preferred bookmaker or fall back to first available
  const selectedBookmaker =
    bookmakers.find((b) => b.key === preferredBookmaker) || bookmakers[0];

  const markets: { type: string; side_a: string; side_b: string; odds_a: number; odds_b: number }[] = [];

  for (const market of selectedBookmaker.markets) {
    switch (market.key) {
      case 'h2h': {
        // Moneyline
        const homeOutcome = market.outcomes.find((o) => o.name === oddsEvent.home_team);
        const awayOutcome = market.outcomes.find((o) => o.name === oddsEvent.away_team);
        if (homeOutcome && awayOutcome) {
          markets.push({
            type: 'moneyline',
            side_a: oddsEvent.away_team,
            side_b: oddsEvent.home_team,
            odds_a: awayOutcome.price,
            odds_b: homeOutcome.price,
          });
        }
        break;
      }
      case 'spreads': {
        // Spread
        const homeOutcome = market.outcomes.find((o) => o.name === oddsEvent.home_team);
        const awayOutcome = market.outcomes.find((o) => o.name === oddsEvent.away_team);
        if (homeOutcome && awayOutcome) {
          const awaySpread = formatSpread(awayOutcome.point ?? 0);
          const homeSpread = formatSpread(homeOutcome.point ?? 0);
          markets.push({
            type: 'spread',
            side_a: `${oddsEvent.away_team} ${awaySpread}`,
            side_b: `${oddsEvent.home_team} ${homeSpread}`,
            odds_a: awayOutcome.price,
            odds_b: homeOutcome.price,
          });
        }
        break;
      }
      case 'totals': {
        // Total (over/under)
        const overOutcome = market.outcomes.find((o) => o.name === 'Over');
        const underOutcome = market.outcomes.find((o) => o.name === 'Under');
        if (overOutcome && underOutcome) {
          const totalValue = overOutcome.point ?? underOutcome.point ?? 0;
          markets.push({
            type: 'total',
            side_a: `Over ${formatNumber(totalValue)}`,
            side_b: `Under ${formatNumber(totalValue)}`,
            odds_a: overOutcome.price,
            odds_b: underOutcome.price,
          });
        }
        break;
      }
      case 'alternate_spreads': {
        // Alternate spreads: group outcomes by |point| into home/away pairs
        const byPoint = new Map<number, { home?: OddsOutcome; away?: OddsOutcome }>();
        for (const outcome of market.outcomes) {
          if (outcome.point === undefined) continue;
          const key = Math.abs(outcome.point);
          const pair = byPoint.get(key) || {};
          if (outcome.name === oddsEvent.home_team) {
            pair.home = outcome;
          } else {
            pair.away = outcome;
          }
          byPoint.set(key, pair);
        }
        for (const [_, pair] of byPoint) {
          if (pair.home && pair.away) {
            const awaySpread = formatSpread(pair.away.point ?? 0);
            const homeSpread = formatSpread(pair.home.point ?? 0);
            markets.push({
              type: 'alternate_spread',
              side_a: `${oddsEvent.away_team} ${awaySpread}`,
              side_b: `${oddsEvent.home_team} ${homeSpread}`,
              odds_a: pair.away.price,
              odds_b: pair.home.price,
            });
          }
        }
        break;
      }
      case 'alternate_totals': {
        // Alternate totals: group outcomes by point into Over/Under pairs
        const byTotal = new Map<number, { over?: OddsOutcome; under?: OddsOutcome }>();
        for (const outcome of market.outcomes) {
          if (outcome.point === undefined) continue;
          const pair = byTotal.get(outcome.point) || {};
          if (outcome.name === 'Over') {
            pair.over = outcome;
          } else if (outcome.name === 'Under') {
            pair.under = outcome;
          }
          byTotal.set(outcome.point, pair);
        }
        for (const [pointVal, pair] of byTotal) {
          if (pair.over && pair.under) {
            markets.push({
              type: 'alternate_total',
              side_a: `Over ${formatNumber(pointVal)}`,
              side_b: `Under ${formatNumber(pointVal)}`,
              odds_a: pair.over.price,
              odds_b: pair.under.price,
            });
          }
        }
        break;
      }
      case 'team_totals': {
        // One market per team per line. The Odds API carries the team in
        // `description` here rather than in `name`, which holds Over/Under —
        // the opposite of the featured `totals` market, where `name` is the
        // side. Keying by team AND point matters: both teams commonly have a
        // line at the same number, and collapsing them would silently graft
        // one team's price onto the other's row.
        const byTeamPoint = new Map<string, { team: string; point: number; over?: OddsOutcome; under?: OddsOutcome }>();
        for (const outcome of market.outcomes) {
          const team = outcome.description;
          if (!team || outcome.point === undefined) continue;
          const key = `${team}|${outcome.point}`;
          const entry = byTeamPoint.get(key) ?? { team, point: outcome.point };
          if (outcome.name === 'Over') entry.over = outcome;
          else if (outcome.name === 'Under') entry.under = outcome;
          byTeamPoint.set(key, entry);
        }
        for (const entry of byTeamPoint.values()) {
          if (entry.over && entry.under) {
            markets.push({
              type: 'team_total',
              // The team name leads so gradeTeamTotalBet can identify which
              // side the line belongs to, and so the label reads as a bet.
              side_a: `${entry.team} Over ${formatNumber(entry.point)}`,
              side_b: `${entry.team} Under ${formatNumber(entry.point)}`,
              odds_a: entry.over.price,
              odds_b: entry.under.price,
            });
          }
        }
        break;
      }
      case 'odd_even': {
        // Whether the combined final score is odd or even. Settles from the
        // final score alone, which is the entire reason it is here and the
        // quarter, half and player-prop markets are not.
        const odd = market.outcomes.find((o) => /^odd$/i.test(o.name));
        const even = market.outcomes.find((o) => /^even$/i.test(o.name));
        if (odd && even) {
          markets.push({
            type: 'odd_even',
            side_a: 'Odd',
            side_b: 'Even',
            odds_a: odd.price,
            odds_b: even.price,
          });
        }
        break;
      }
    }
  }

  return markets;
}



/**
 * The discriminator that makes a market row unique within its event and type.
 *
 * For spreads and totals the line value is enough: an event has one away side
 * and one home side, so -3.5 identifies a row. For TEAM totals it is not —
 * both teams routinely carry a line at the same number, and keying on the
 * number alone would collide, letting one team's price silently overwrite the
 * other's. Those use the full side label, which carries the team.
 *
 * Existing types keep their exact previous key. Changing it would make every
 * stored market look new on the next run and duplicate the table.
 */
export function marketDiscriminator(type: string, sideA: string): string {
  return type === 'team_total' ? sideA : String(extractLineValue(sideA));
}

/**
 * Merge a per-event market bundle into the event the mapper will read.
 *
 * The mapper reads exactly one bookmaker per event (DraftKings, else the
 * first), and the deep markets are spread unevenly across books. On the probed
 * NFL game DraftKings quoted alternate spreads, alternate totals and odd/even
 * but NOT team totals, while FanDuel quoted team totals and no odd/even. A
 * strict same-book rule would therefore have dropped team totals from every
 * game DraftKings prices, which is all of them.
 *
 * So each market key is filled from the selected book when it has it, and
 * otherwise from ONE fallback book — the one carrying the most of what is
 * still missing. That keeps a whole market's two sides priced by a single
 * book. What it deliberately does not do is compare prices across books per
 * line and take the best: that would assemble a board better than any real
 * book offers and hand members an edge the organizer never agreed to carry.
 */
export function mergeDeepMarkets(
  target: OddsEvent,
  deep: OddsEvent,
  preferredBookmaker: string = 'draftkings',
): number {
  const bookmakers = target.bookmakers;
  if (!bookmakers?.length) return 0;

  const selected = bookmakers.find((b) => b.key === preferredBookmaker) ?? bookmakers[0];
  const deepBooks = deep.bookmakers ?? [];
  if (!deepBooks.length) return 0;

  const present = new Set(selected.markets.map((m) => m.key));
  let added = 0;

  // First pass: the selected book's own deep markets.
  const sameBook = deepBooks.find((b) => b.key === selected.key);
  for (const market of sameBook?.markets ?? []) {
    if (present.has(market.key)) continue;
    selected.markets.push(market);
    present.add(market.key);
    added++;
  }

  // Second pass: fill what is still missing from a single other book.
  const missing = DEEP_MARKETS.filter((k) => !present.has(k));
  if (missing.length > 0) {
    const fallback = deepBooks
      .filter((b) => b.key !== selected.key)
      .map((b) => ({ book: b, hits: (b.markets ?? []).filter((m) => missing.includes(m.key)).length }))
      .sort((a, b) => b.hits - a.hits)[0];

    for (const market of fallback?.book.markets ?? []) {
      if (present.has(market.key) || !missing.includes(market.key)) continue;
      selected.markets.push(market);
      present.add(market.key);
      added++;
    }
  }

  return added;
}

/**
 * Maps an OddsEvent to an EventRecord for database upsert.
 */
function mapOddsEventToRecord(oddsEvent: OddsEvent): EventRecord {
  const { sport, league } = getSportAndLeague(oddsEvent.sport_key);

  // Outrights have null home/away — use sport_title as home_team, "Outright" as sentinel
  const homeTeam = oddsEvent.home_team ?? oddsEvent.sport_title;
  const awayTeam = oddsEvent.away_team ?? 'Outright';
  const name = awayTeam === 'Outright' ? homeTeam : `${awayTeam} @ ${homeTeam}`;

  return {
    external_id: oddsEvent.id,
    external_source: 'the-odds-api',
    bookie_id: null, // Shared across all bookies
    name,
    sport,
    league,
    home_team: homeTeam,
    away_team: awayTeam,
    start_time: oddsEvent.commence_time,
    status: 'scheduled',
    last_odds_update: new Date().toISOString(),
  };
}

/**
 * Generates an idempotency key for sync_games operations.
 * Format: sync_games_{YYYY-MM-DD}_{window}
 * Window is 'morning' (before 12:00 UTC) or 'afternoon' (12:00 UTC and later)
 */
function generateIdempotencyKey(): string {
  const now = new Date();
  const year = now.getUTCFullYear();
  const month = String(now.getUTCMonth() + 1).padStart(2, '0');
  const day = String(now.getUTCDate()).padStart(2, '0');
  const dateStr = `${year}-${month}-${day}`;

  // 4-hour buckets, aligned to the cron (00,04,08,12,16,20 UTC).
  //
  // MUST match the cron cadence. This was previously a half-day window
  // (morning/afternoon), which meant that if the schedule were made more
  // frequent, every run after the first in each half-day would find the key
  // already stored and silently skip the odds sync — doing only scores and
  // finalization. The schedule would look busier while odds stayed 12h stale.
  //
  // If the cron in migration 035 changes, change this to match.
  const bucket = String(Math.floor(now.getUTCHours() / 4) * 4).padStart(2, '0');
  return `sync_games_${dateStr}_h${bucket}`;
}

/**
 * sync_games Edge Function
 *
 * Automatically fetches games from the Odds API and stores them in the events table.
 * All events are created with bookie_id = NULL (shared across all bookies).
 *
 * Called twice daily via cron (morning and afternoon).
 *
 * Authorization: Requires service role key or valid JWT token.
 */

interface SyncStats {
  sports_fetched: number;
  events_inserted: number;
  events_updated: number;
  events_skipped: number;
  markets_inserted: number;
  markets_updated: number;
  /** Games given the per-event market bundle this run. */
  deep_games_enriched?: number;
  errors: string[];
}

Deno.serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  // Isolates are reused between invocations, so per-run counters must be
  // cleared or they accumulate across unrelated runs.
  resetQuota();

  try {
    // No auth check - this function is called by cron and only manages shared events
    // Similar to auto_refresh_games which also has no auth requirement
    const client = createServiceClient();

    // Parse request body for force flag
    let force = false;
    try {
      const body = await req.json();
      force = body?.force === true;
    } catch {
      // No body or invalid JSON — that's fine
    }

    // Idempotency check (skip if force=true)
    const idempotencyKey = generateIdempotencyKey();
    const operation = 'sync_games';

    let skipOddsSync = false;
    if (!force) {
      const cachedResponse = await checkIdempotency(client, idempotencyKey, operation);
      skipOddsSync = !!cachedResponse;
    }

    if (skipOddsSync) {
      console.log(`Idempotency key ${idempotencyKey} exists, skipping odds sync but will still fetch scores`);
    } else if (force) {
      console.log('Force mode: bypassing idempotency check');
    }

    // Check for ODDS_API_KEY
    const oddsApiKey = Deno.env.get('ODDS_API_KEY');
    if (!oddsApiKey) {
      return new Response(
        JSON.stringify({
          success: false,
          error: 'ODDS_API_KEY is not configured',
        }),
        {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      );
    }

    // Initialize stats
    const stats: SyncStats = {
      sports_fetched: 0,
      events_inserted: 0,
      events_updated: 0,
      events_skipped: 0,
      markets_inserted: 0,
      markets_updated: 0,
      errors: [],
    };

    // US-002: Fetch games from Odds API for each sport (skip if already ran this window)
    const allFetchedEvents: OddsEvent[] = [];

    if (!skipOddsSync) {
      // Fetched with bounded concurrency, not one at a time. 15 sports plus 10
      // futures is 25 sequential Odds API round trips, which alone consumed
      // most of the 150s edge-function budget and made the run fail outright
      // depending on upstream latency. Concurrency is capped rather than
      // unbounded to stay polite to the provider's rate limits.
      const sportResults = await mapWithConcurrency(
        SPORTS_TO_SYNC,
        ODDS_FETCH_CONCURRENCY,
        async (sportKey) => {
          try {
            const events = await fetchOddsFromApi(oddsApiKey, sportKey);
            console.log(`Fetched ${events.length} events for ${sportKey}`);
            return { sportKey, events, error: null as string | null };
          } catch (error) {
            const errorMessage = error instanceof Error ? error.message : 'Unknown error';
            console.error(`Error fetching ${sportKey}: ${errorMessage}`);
            return { sportKey, events: [] as OddsEvent[], error: errorMessage };
          }
        },
      );

      for (const result of sportResults) {
        if (result.error) {
          stats.errors.push(`${result.sportKey}: ${result.error}`);
          continue; // Continue with other sports
        }
        allFetchedEvents.push(...result.events);
        stats.sports_fetched++;
      }

      console.log(`Total events fetched: ${allFetchedEvents.length}`);

      // ── Per-event market bundle for the deep-board sports ────────────────
      //
      // Runs only here, inside the odds-sync branch, and only for games that
      // are both in an eligible league and close to kickoff. Cost is markets x
      // games rather than a flat 3 per sport, so both gates are load-bearing:
      // dropping either would multiply the bill and the markets table by an
      // order of magnitude.
      const deepCutoff = Date.now() + DEEP_MARKET_WINDOW_MS;
      const deepCandidates = allFetchedEvents.filter((e) =>
        DEEP_MARKET_SPORTS.includes(e.sport_key) &&
        e.away_team !== null &&
        new Date(e.commence_time).getTime() <= deepCutoff &&
        new Date(e.commence_time).getTime() > Date.now(),
      );

      if (deepCandidates.length > 0) {
        console.log(`Deep markets: ${deepCandidates.length} eligible games`);
        let enriched = 0;
        let addedMarkets = 0;

        // Same concurrency as the sport fetches — this is the step most likely
        // to push the function toward the 150s ceiling, since it is one request
        // per game rather than per sport.
        const deepResults = await mapWithConcurrency(deepCandidates, 5, async (event) => {
          const bundle = await fetchEventMarketsFromApi(oddsApiKey, event.sport_key, event.id);
          return { event, bundle };
        });

        for (const { event, bundle } of deepResults) {
          if (!bundle) continue;
          const added = mergeDeepMarkets(event, bundle);
          if (added > 0) { enriched++; addedMarkets += added; }
        }
        console.log(`Deep markets: enriched ${enriched} games with ${addedMarkets} market groups`);
        stats.deep_games_enriched = enriched;
      }

    // US-003: Upsert events to database
    // First, get all external_ids from fetched events to query existing records
    const externalIds = allFetchedEvents.map((e) => e.id);

    // Load the id -> external_id map for the whole table.
    //
    // MUST be paginated: a plain select is capped at 1000 rows, and anything
    // past the cap looks new and gets inserted again as a duplicate.
    //
    // Reading the whole table beats chunking an .in() list here. A chunked IN
    // over ~2,000 fetched ids is 10-20 sequential round trips; the full table
    // is ~6 (1000 rows each) and only two narrow columns. Round trips are what
    // push this function toward the 150s edge-function ceiling. This stays
    // cheap as long as retention keeps the table small — see Phase 3 of
    // docs/games-sync-redesign.md.
    const { data: existingEvents, error: existingEventsError } =
      await selectAllPaged<ExistingEventRow>(
        () => client.from('events').select(
          'id, external_id, name, sport, league, home_team, away_team, start_time, status'));

    if (existingEventsError) {
      console.error('Error querying existing events:', existingEventsError);
      stats.errors.push(`Database error: ${existingEventsError.message}`);
    }

    // Build a map of external_id -> existing row
    const existingEventsMap = new Map<string, ExistingEventRow>();
    if (existingEvents) {
      for (const event of existingEvents) {
        if (event.external_id) {
          existingEventsMap.set(event.external_id, event);
        }
      }
    }

    // Track which events were inserted vs updated
    const eventsToInsert: EventRecord[] = [];
    const eventsToUpdate: { id: string; record: Partial<EventRecord> }[] = [];
    let unchanged = 0;

    for (const oddsEvent of allFetchedEvents) {
      const existing = existingEventsMap.get(oddsEvent.id);
      const eventRecord = mapOddsEventToRecord(oddsEvent);

      if (existing) {
        // Skip rows the provider has not actually changed.
        //
        // Updates run one request per row, and a sync touches hundreds of
        // games whose name/teams/start time are identical to what is already
        // stored. Those writes are pure round-trip cost and push the function
        // toward the 150s ceiling. Semantics are unchanged — an update that
        // sets a column to its current value is a no-op.
        //
        // last_odds_update is intentionally excluded from the comparison: it
        // changes on every fetch and would defeat the check entirely.
        // start_time is compared as an instant, not as a string. The Odds API
        // returns "2026-11-09T01:20:00Z" while PostgREST returns
        // "2026-11-09T01:20:00+00:00" — the same moment, different text. A
        // string comparison marks every event as changed and defeats the skip.
        const same =
          existing.name === eventRecord.name &&
          existing.sport === eventRecord.sport &&
          existing.league === eventRecord.league &&
          existing.home_team === eventRecord.home_team &&
          existing.away_team === eventRecord.away_team &&
          Date.parse(existing.start_time) === Date.parse(eventRecord.start_time);

        // Final events are never updated (the query below also guards this).
        if (same || existing.status === 'final') {
          unchanged++;
          continue;
        }

        // Event exists - update it (don't overwrite id or status if already final)
        eventsToUpdate.push({
          id: existing.id,
          record: {
            name: eventRecord.name,
            sport: eventRecord.sport,
            league: eventRecord.league,
            home_team: eventRecord.home_team,
            away_team: eventRecord.away_team,
            start_time: eventRecord.start_time,
            last_odds_update: eventRecord.last_odds_update,
            // Don't update: external_id, external_source, bookie_id, status
          },
        });
      } else {
        // New event - insert it
        eventsToInsert.push(eventRecord);
      }
    }

    console.log(`Events: ${eventsToInsert.length} to insert, ${eventsToUpdate.length} to update, ${unchanged} unchanged`);

    // Insert new events.
    //
    // Upsert with ignoreDuplicates rather than a plain insert: the unique index
    // on events.external_id (migration 032) is the last line of defence against
    // the duplication bug, and without this a single stale existence-check would
    // turn into a hard 23505 that fails the whole batch. Here a row that already
    // exists is simply skipped.
    //
    // NOTE: deliberately NOT a blanket upsert of every field. The update path
    // below preserves `status` and skips events already marked final — a full
    // upsert would overwrite status and un-finalize graded games.
    const insertedEventRows: { id: string; external_id: string | null }[] = [];
    if (eventsToInsert.length > 0) {
      const { data: insertedRows, error: insertError } = await client
        .from('events')
        .upsert(eventsToInsert, { onConflict: 'external_id', ignoreDuplicates: true })
        .select('id, external_id');

      if (insertError) {
        console.error('Error inserting events:', insertError);
        stats.errors.push(`Insert error: ${insertError.message}`);
      } else {
        insertedEventRows.push(...(insertedRows ?? []));
        const actual = insertedRows?.length ?? 0;
        stats.events_inserted = actual;
        const skipped = eventsToInsert.length - actual;
        console.log(`Inserted ${actual} new events${skipped > 0 ? ` (${skipped} already existed, skipped)` : ''}`);
        if (skipped > 0) {
          // Should be 0 — a non-zero value means the existence check missed rows.
          console.warn(`Existence check missed ${skipped} events — investigate pagination`);
        }
      }
    }

    // Update existing events
    for (const { id, record } of eventsToUpdate) {
      const { error: updateError } = await client
        .from('events')
        .update(record)
        .eq('id', id)
        .neq('status', 'final'); // Don't update events that are already final

      if (updateError) {
        console.error(`Error updating event ${id}:`, updateError);
        stats.errors.push(`Update error for ${id}: ${updateError.message}`);
      } else {
        stats.events_updated++;
      }
    }

    console.log(`Events: ${stats.events_inserted} inserted, ${stats.events_updated} updated`);

    // US-004: Upsert markets for each event
    //
    // No re-query needed. The map loaded before the insert already covers every
    // pre-existing event, and the upsert above returned the ids of the rows it
    // created — merging the two is exact and saves a second full table read.
    const eventIdMap = new Map<string, string>(
      Array.from(existingEventsMap, ([ext, row]) => [ext, row.id]),
    );
    for (const row of insertedEventRows) {
      if (row.external_id) {
        eventIdMap.set(row.external_id, row.id);
      }
    }

    // Get existing markets for all events to determine insert vs update
    const eventDbIds = Array.from(eventIdMap.values());
    const { data: existingMarkets, error: existingMarketsError } =
      await selectAllIn<{ id: string; event_id: string; type: string; side_a: string }>(
        client, 'markets', 'id, event_id, type, side_a', 'event_id', eventDbIds);

    if (existingMarketsError) {
      console.error('Error querying existing markets:', existingMarketsError);
      stats.errors.push(`Markets query error: ${existingMarketsError.message}`);
    }

    // Build a map of event_id+type+lineValue -> market id for existing markets
    // This composite key supports multiple alternate lines per type per event
    const existingMarketsMap = new Map<string, string>();
    if (existingMarkets) {
      for (const market of existingMarkets) {
        const key = `${market.event_id}_${market.type}_${marketDiscriminator(market.type, market.side_a)}`;
        existingMarketsMap.set(key, market.id);
      }
    }

    // Process markets for each fetched event
    const marketsToInsert: MarketRecord[] = [];
    // Carries full rows, not partials: these are written back with a batched
    // upsert on the primary key, and the INSERT arm of that statement needs
    // every NOT NULL column to be present even though it never fires for rows
    // that already exist.
    const marketsToUpdate: (MarketRecord & { id: string })[] = [];

    let marketsSkippedFarOut = 0;

    for (const oddsEvent of allFetchedEvents) {
      const eventId = eventIdMap.get(oddsEvent.id);
      if (!eventId) {
        // Event wasn't found in database - skip markets
        continue;
      }

      // Odds are only stored inside the storage window. Members see odds 48h
      // ahead; the window is wider so a game already has lines by the time it
      // becomes visible, rather than appearing with a blank price.
      //
      // Outrights are exempt — futures are long-dated by definition and would
      // be wiped out entirely by a start-time rule.
      const startsAt = Date.parse(oddsEvent.commence_time);
      const isOutright = oddsEvent.away_team === null || oddsEvent.home_team === null;
      if (!isOutright && startsAt > Date.now() + ODDS_STORAGE_WINDOW_MS) {
        marketsSkippedFarOut++;
        continue;
      }

      // Extract markets from the odds event
      const extractedMarkets = extractMarketsFromOddsEvent(oddsEvent);
      if (extractedMarkets.length === 0) {
        // No odds data available for this event - skip
        stats.events_skipped++;
        continue;
      }

      for (const market of extractedMarkets) {
        const marketKey = `${eventId}_${market.type}_${marketDiscriminator(market.type, market.side_a)}`;
        const existingMarketId = existingMarketsMap.get(marketKey);

        if (existingMarketId) {
          // Market exists - update it
          marketsToUpdate.push({
            id: existingMarketId,
            event_id: eventId,
            bookie_id: null, // Shared markets
            type: market.type,
            side_a: market.side_a,
            side_b: market.side_b,
            odds_a: market.odds_a,
            odds_b: market.odds_b,
          });
        } else {
          // New market - insert it
          marketsToInsert.push({
            event_id: eventId,
            bookie_id: null, // Shared markets
            type: market.type,
            side_a: market.side_a,
            side_b: market.side_b,
            odds_a: market.odds_a,
            odds_b: market.odds_b,
          });
        }
      }
    }

    // Insert new markets
    if (marketsToInsert.length > 0) {
      const { error: insertMarketsError } = await client
        .from('markets')
        .insert(marketsToInsert);

      if (insertMarketsError) {
        console.error('Error inserting markets:', insertMarketsError);
        stats.errors.push(`Markets insert error: ${insertMarketsError.message}`);
      } else {
        stats.markets_inserted = marketsToInsert.length;
        console.log(`Inserted ${marketsToInsert.length} new markets`);
      }
    }

    // Update existing markets.
    //
    // Batched, not one request per row. This loop was the reason a sync could
    // not finish inside the 150s edge-function budget: odds move constantly,
    // so a steady-state run refreshes thousands of markets, and issuing one
    // UPDATE per market meant thousands of sequential round trips. The single
    // run that ever completed did so only because every market was new that
    // day (1,449 inserted, 0 updated) and this loop never executed.
    //
    // Upserting on the primary key is an UPDATE for every row here, since all
    // of them already exist. Chunked to keep any single request modest.
    const MARKET_UPSERT_CHUNK = 500;
    for (let i = 0; i < marketsToUpdate.length; i += MARKET_UPSERT_CHUNK) {
      const chunk = marketsToUpdate.slice(i, i + MARKET_UPSERT_CHUNK);
      const { error: updateMarketError } = await client
        .from('markets')
        .upsert(chunk, { onConflict: 'id' });

      if (updateMarketError) {
        console.error(`Error updating markets (chunk at ${i}):`, updateMarketError);
        stats.errors.push(`Market update error: ${updateMarketError.message}`);
      } else {
        stats.markets_updated += chunk.length;
      }
    }

    console.log(`Markets: ${stats.markets_inserted} inserted, ${stats.markets_updated} updated`);

    // ========================================
    // Futures / Outright Markets Sync
    // ========================================
    console.log('Starting futures sync...');
    let futuresEventsInserted = 0;
    let futuresMarketsInserted = 0;

    // Prefetch every futures feed concurrently, then process sequentially.
    // Only the API calls are parallelised — the per-event database work below
    // is left serial, since interleaving those writes has no latency benefit
    // and would make failures much harder to reason about.
    const futuresFetched = await mapWithConcurrency(
      FUTURES_TO_SYNC,
      ODDS_FETCH_CONCURRENCY,
      async (futuresKey) => {
        try {
          const events = await fetchOutrightsFromApi(oddsApiKey, futuresKey);
          console.log(`Fetched ${events.length} futures events for ${futuresKey}`);
          return { futuresKey, events, error: null as string | null };
        } catch (error) {
          const errorMessage = error instanceof Error ? error.message : 'Unknown error';
          console.error(`Error fetching futures ${futuresKey}: ${errorMessage}`);
          return { futuresKey, events: [] as OddsEvent[], error: errorMessage };
        }
      },
    );

    for (const { futuresKey, events: futuresEvents, error: fetchError } of futuresFetched) {
      if (fetchError) {
        stats.errors.push(`futures ${futuresKey}: ${fetchError}`);
        continue;
      }
      try {

        for (const oddsEvent of futuresEvents) {
          const eventRecord = mapOddsEventToRecord(oddsEvent);

          // Check if event already exists
          const { data: existingFuturesEvent } = await client
            .from('events')
            .select('id')
            .eq('external_id', oddsEvent.id)
            .maybeSingle();

          let eventDbId: string;

          if (existingFuturesEvent) {
            eventDbId = existingFuturesEvent.id;
            // Update the event record
            await client
              .from('events')
              .update({
                name: eventRecord.name,
                sport: eventRecord.sport,
                league: eventRecord.league,
                home_team: eventRecord.home_team,
                away_team: eventRecord.away_team,
                start_time: eventRecord.start_time,
                last_odds_update: eventRecord.last_odds_update,
              })
              .eq('id', eventDbId)
              .neq('status', 'final');
          } else {
            const { data: inserted, error: insertErr } = await client
              .from('events')
              .insert(eventRecord)
              .select('id')
              .single();

            if (insertErr || !inserted) {
              console.error(`Error inserting futures event ${oddsEvent.id}:`, insertErr);
              continue;
            }
            eventDbId = inserted.id;
            futuresEventsInserted++;
          }

          // Extract outright markets
          const outrightMarkets = extractOutrightMarkets(oddsEvent);
          if (outrightMarkets.length === 0) continue;

          // Get existing outright markets for this event
          const { data: existingOutrightMarkets } = await client
            .from('markets')
            .select('id, side_a')
            .eq('event_id', eventDbId)
            .eq('type', 'outright');

          const existingOutrightMap = new Map<string, string>();
          if (existingOutrightMarkets) {
            for (const m of existingOutrightMarkets) {
              existingOutrightMap.set(m.side_a, m.id);
            }
          }

          const outrightToInsert: MarketRecord[] = [];

          for (const market of outrightMarkets) {
            const existingId = existingOutrightMap.get(market.side_a);
            if (existingId) {
              // Update existing market odds
              await client
                .from('markets')
                .update({ odds_a: market.odds_a })
                .eq('id', existingId);
            } else {
              outrightToInsert.push({
                event_id: eventDbId,
                bookie_id: null,
                type: 'outright',
                side_a: market.side_a,
                side_b: market.side_b,
                odds_a: market.odds_a,
                odds_b: 0,
              });
            }
          }

          if (outrightToInsert.length > 0) {
            const { error: insertOutrightErr } = await client
              .from('markets')
              .insert(outrightToInsert);

            if (insertOutrightErr) {
              console.error(`Error inserting outright markets for ${oddsEvent.id}:`, insertOutrightErr);
            } else {
              futuresMarketsInserted += outrightToInsert.length;
            }
          }
        }
      } catch (error) {
        const errorMessage = error instanceof Error ? error.message : 'Unknown error';
        console.error(`Error fetching futures ${futuresKey}: ${errorMessage}`);
        stats.errors.push(`futures_${futuresKey}: ${errorMessage}`);
      }
    }

    console.log(`Futures: ${futuresEventsInserted} events inserted, ${futuresMarketsInserted} markets inserted`);
    (stats as any).futures_events_inserted = futuresEventsInserted;
    (stats as any).futures_markets_inserted = futuresMarketsInserted;

    } // End of !skipOddsSync block

    // US-005: Mark past events as final
    // Any event with start_time in the past that's still 'scheduled' should be 'final'
    const cutoffTime = new Date();
    cutoffTime.setHours(cutoffTime.getHours() - 3); // 3 hours after start time

    const { data: updatedToFinal, error: finalizeError } = await client
      .from('events')
      .update({ status: 'final', updated_at: new Date().toISOString() })
      .eq('status', 'scheduled')
      .lt('start_time', cutoffTime.toISOString())
      .select('id');

    if (finalizeError) {
      console.error('Error finalizing past events:', finalizeError);
      stats.errors.push(`Finalize error: ${finalizeError.message}`);
    } else {
      const finalizedCount = updatedToFinal?.length || 0;
      console.log(`Marked ${finalizedCount} past events as final`);
      (stats as any).events_finalized = finalizedCount;
    }

    // Drop the odds for games that have finished.
    //
    // Grading never reads these: every bet stores its own market, side and
    // odds at placement, so a settled bet renders identically without them.
    // Left in place they accumulate indefinitely — 16,643 of 19,813 markets
    // were odds on games already played before this was added.
    //
    // This is a sweep over every final game, NOT a hook on the finalization
    // step above. Three separate code paths mark a game final: that step, plus
    // refresh_live_scores and auto_refresh_games when a real result lands.
    // Hooking only the step here missed the other two — which are precisely
    // the games people bet on, since those are the ones actively watched for
    // a result. Sweeping catches all three regardless of who set the status.
    //
    // Cheap: the markets table holds ~1,300 rows in steady state, so reading it
    // whole costs a couple of requests.
    //
    // Self-contained on purpose. This also runs when the odds sync was skipped
    // by the idempotency window, so it must not reference anything scoped to
    // that branch. It starts from the markets that exist and asks which of
    // their events are final, rather than starting from events.
    //
    // Outrights are exempt. A futures market stays live long after its
    // nominal start_time has passed.
    const { data: liveMarkets, error: liveMarketsError } =
      await selectAllPaged<{ id: string; event_id: string }>(
        () => client.from('markets').select('id, event_id').neq('type', 'outright'));

    let prunedMarkets = 0;
    if (liveMarketsError) {
      console.error('Error loading markets for prune:', liveMarketsError);
      stats.errors.push(`Market prune query error: ${liveMarketsError.message}`);
    } else {
      const marketEventIds = Array.from(new Set(liveMarkets.map((m) => m.event_id)));

      // Status is read fresh rather than from the snapshot taken earlier in the
      // run: the finalization step above, refresh_live_scores, and
      // auto_refresh_games can each have marked a game final since then.
      const finalEventIds = new Set<string>();
      let statusQueryFailed = false;
      for (let i = 0; i < marketEventIds.length; i += 200) {
        const chunk = marketEventIds.slice(i, i + 200);
        const { data: rows, error: statusError } = await client
          .from('events')
          .select('id')
          .in('id', chunk)
          .eq('status', 'final');

        if (statusError) {
          console.error('Error loading event status for prune:', statusError);
          stats.errors.push(`Market prune status error: ${statusError.message}`);
          statusQueryFailed = true;
          break;
        }
        for (const row of rows ?? []) finalEventIds.add(row.id);
      }

      const staleMarketIds = statusQueryFailed ? [] : liveMarkets
        .filter((m) => finalEventIds.has(m.event_id))
        .map((m) => m.id);

      for (let i = 0; i < staleMarketIds.length; i += 200) {
        const chunk = staleMarketIds.slice(i, i + 200);
        const { error: pruneError } = await client
          .from('markets')
          .delete()
          .in('id', chunk);

        if (pruneError) {
          console.error('Error pruning markets for finished games:', pruneError);
          stats.errors.push(`Market prune error: ${pruneError.message}`);
          break;
        }
        prunedMarkets += chunk.length;
      }
      if (prunedMarkets > 0) {
        console.log(`Pruned ${prunedMarkets} markets from finished games`);
      }
    }
    (stats as any).markets_pruned = prunedMarkets;

    // US-006: Fetch scores for final events that don't have scores yet
    // Only fetch for events with external_id (imported from The Odds API)
    const { data: eventsNeedingScores, error: needingScoresError } = await client
      .from('events')
      .select('id, external_id, sport, league, home_team, away_team')
      .eq('status', 'final')
      .is('final_score', null)
      .not('external_id', 'is', null)
      .limit(20); // Limit to avoid too many API calls

    let scoresUpdated = 0;
    if (needingScoresError) {
      console.error('Error fetching events needing scores:', needingScoresError);
    } else if (eventsNeedingScores && eventsNeedingScores.length > 0) {
      console.log(`Found ${eventsNeedingScores.length} events needing scores`);

      // Group events by sport key for efficient API calls
      const sportGroups = new Map<string, typeof eventsNeedingScores>();
      for (const event of eventsNeedingScores) {
        // Reverse map sport+league to API key
        const sportKey = Object.entries(SPORT_KEY_MAPPING).find(
          ([_, v]) => v.sport === event.sport && v.league === event.league
        )?.[0];

        if (sportKey) {
          if (!sportGroups.has(sportKey)) {
            sportGroups.set(sportKey, []);
          }
          sportGroups.get(sportKey)!.push(event);
        }
      }

      // Fetch scores for each sport
      for (const [sportKey, events] of sportGroups) {
        try {
          const scoreEvents = await fetchScoresFromApi(oddsApiKey, sportKey, 3);

          // Match scores to our events
          for (const event of events) {
            const matchingScore = scoreEvents.find(
              se => se.id === event.external_id && se.completed && se.scores
            );

            if (matchingScore && matchingScore.scores) {
              const homeScoreData = matchingScore.scores.find(s => s.name === event.home_team);
              const awayScoreData = matchingScore.scores.find(s => s.name === event.away_team);

              if (homeScoreData && awayScoreData) {
                const homeScore = parseInt(homeScoreData.score, 10);
                const awayScore = parseInt(awayScoreData.score, 10);

                if (!isNaN(homeScore) && !isNaN(awayScore)) {
                  const { error: updateError } = await client
                    .from('events')
                    .update({
                      home_score: homeScore,
                      away_score: awayScore,
                      final_score: `${awayScore}-${homeScore}`,
                      updated_at: new Date().toISOString(),
                    })
                    .eq('id', event.id);

                  if (!updateError) {
                    scoresUpdated++;
                    console.log(`Updated score for ${event.away_team} @ ${event.home_team}: ${awayScore}-${homeScore}`);
                  } else {
                    console.error(`Failed to update score for event ${event.id}:`, updateError);
                  }
                }
              }
            }
          }
        } catch (error) {
          console.error(`Error fetching scores for ${sportKey}:`, error);
        }
      }
    }

    console.log(`Scores updated: ${scoresUpdated}`);
    (stats as any).scores_updated = scoresUpdated;

    // Build response
    const responseBody = {
      success: true,
      message: 'Games sync completed',
      stats,
      quota: getQuotaSnapshot(),
    };

    const responseString = JSON.stringify(responseBody);

    // Store idempotency key only if we actually ran the odds sync
    if (!skipOddsSync) {
      await storeIdempotency(
        client,
        idempotencyKey,
        operation,
        'system',
        responseString
      );
    }

    console.log(`sync_games completed. Stats: ${JSON.stringify(stats)}`);

    return new Response(responseString, {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (error) {
    console.error('Error in sync_games:', error);
    return new Response(
      JSON.stringify({
        success: false,
        error: error instanceof Error ? error.message : 'Internal server error',
      }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    );
  }
});
