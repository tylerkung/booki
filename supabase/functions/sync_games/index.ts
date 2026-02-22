import { corsHeaders } from '../_shared/cors.ts';
import { createServiceClient } from '../_shared/supabase.ts';
import { checkIdempotency, storeIdempotency } from '../_shared/idempotency.ts';

/**
 * Sports to sync from the Odds API.
 * These are the main US sports leagues.
 */
const SPORTS_TO_SYNC = [
  'basketball_nba',
  'americanfootball_nfl',
  'baseball_mlb',
  'icehockey_nhl',
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
  'golf_pga_championship': { sport: 'Golf', league: 'PGA' },
  'tennis_atp_australian_open': { sport: 'Tennis', league: 'ATP' },
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
  home_team: string;
  away_team: string;
  bookmakers?: OddsBookmaker[];
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
  if (!response.ok) {
    const errorText = await response.text();
    console.error(`Scores API error for ${sportKey}: ${response.status} - ${errorText}`);
    return [];
  }

  const data: ScoreEvent[] = await response.json();
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

  if (!response.ok) {
    throw new Error(`Odds API error: ${response.status} ${response.statusText}`);
  }

  return await response.json();
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
function extractMarketsFromOddsEvent(
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
    }
  }

  return markets;
}

/**
 * Maps an OddsEvent to an EventRecord for database upsert.
 */
function mapOddsEventToRecord(oddsEvent: OddsEvent): EventRecord {
  const { sport, league } = getSportAndLeague(oddsEvent.sport_key);
  const name = `${oddsEvent.away_team} @ ${oddsEvent.home_team}`;

  return {
    external_id: oddsEvent.id,
    external_source: 'the-odds-api',
    bookie_id: null, // Shared across all bookies
    name,
    sport,
    league,
    home_team: oddsEvent.home_team,
    away_team: oddsEvent.away_team,
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
  const window = now.getUTCHours() < 12 ? 'morning' : 'afternoon';
  return `sync_games_${dateStr}_${window}`;
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
  errors: string[];
}

Deno.serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

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
      for (const sportKey of SPORTS_TO_SYNC) {
        try {
          console.log(`Fetching odds for sport: ${sportKey}`);
          const events = await fetchOddsFromApi(oddsApiKey, sportKey);
          console.log(`Fetched ${events.length} events for ${sportKey}`);
          allFetchedEvents.push(...events);
          stats.sports_fetched++;
        } catch (error) {
          const errorMessage = error instanceof Error ? error.message : 'Unknown error';
          console.error(`Error fetching ${sportKey}: ${errorMessage}`);
          stats.errors.push(`${sportKey}: ${errorMessage}`);
          // Continue with other sports
        }
      }

      console.log(`Total events fetched: ${allFetchedEvents.length}`);

    // US-003: Upsert events to database
    // First, get all external_ids from fetched events to query existing records
    const externalIds = allFetchedEvents.map((e) => e.id);

    // Query existing events by external_id
    const { data: existingEvents, error: existingEventsError } = await client
      .from('events')
      .select('id, external_id')
      .in('external_id', externalIds);

    if (existingEventsError) {
      console.error('Error querying existing events:', existingEventsError);
      stats.errors.push(`Database error: ${existingEventsError.message}`);
    }

    // Build a map of external_id -> database id for existing events
    const existingEventsMap = new Map<string, string>();
    if (existingEvents) {
      for (const event of existingEvents) {
        if (event.external_id) {
          existingEventsMap.set(event.external_id, event.id);
        }
      }
    }

    // Track which events were inserted vs updated
    const eventsToInsert: EventRecord[] = [];
    const eventsToUpdate: { id: string; record: Partial<EventRecord> }[] = [];

    for (const oddsEvent of allFetchedEvents) {
      const existingId = existingEventsMap.get(oddsEvent.id);
      const eventRecord = mapOddsEventToRecord(oddsEvent);

      if (existingId) {
        // Event exists - update it (don't overwrite id or status if already final)
        eventsToUpdate.push({
          id: existingId,
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

    // Insert new events
    if (eventsToInsert.length > 0) {
      const { error: insertError } = await client
        .from('events')
        .insert(eventsToInsert);

      if (insertError) {
        console.error('Error inserting events:', insertError);
        stats.errors.push(`Insert error: ${insertError.message}`);
      } else {
        stats.events_inserted = eventsToInsert.length;
        console.log(`Inserted ${eventsToInsert.length} new events`);
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
    // First, we need to re-query events to get their database IDs for newly inserted events
    const { data: allEventsWithIds, error: eventsWithIdsError } = await client
      .from('events')
      .select('id, external_id')
      .in('external_id', externalIds);

    if (eventsWithIdsError) {
      console.error('Error querying events for market upsert:', eventsWithIdsError);
      stats.errors.push(`Events query error for markets: ${eventsWithIdsError.message}`);
    }

    // Build map of external_id -> database id for all events
    const eventIdMap = new Map<string, string>();
    if (allEventsWithIds) {
      for (const event of allEventsWithIds) {
        if (event.external_id) {
          eventIdMap.set(event.external_id, event.id);
        }
      }
    }

    // Get existing markets for all events to determine insert vs update
    const eventDbIds = Array.from(eventIdMap.values());
    const { data: existingMarkets, error: existingMarketsError } = await client
      .from('markets')
      .select('id, event_id, type, side_a')
      .in('event_id', eventDbIds);

    if (existingMarketsError) {
      console.error('Error querying existing markets:', existingMarketsError);
      stats.errors.push(`Markets query error: ${existingMarketsError.message}`);
    }

    // Build a map of event_id+type+lineValue -> market id for existing markets
    // This composite key supports multiple alternate lines per type per event
    const existingMarketsMap = new Map<string, string>();
    if (existingMarkets) {
      for (const market of existingMarkets) {
        const key = `${market.event_id}_${market.type}_${extractLineValue(market.side_a)}`;
        existingMarketsMap.set(key, market.id);
      }
    }

    // Process markets for each fetched event
    const marketsToInsert: MarketRecord[] = [];
    const marketsToUpdate: { id: string; record: Partial<MarketRecord> }[] = [];

    for (const oddsEvent of allFetchedEvents) {
      const eventId = eventIdMap.get(oddsEvent.id);
      if (!eventId) {
        // Event wasn't found in database - skip markets
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
        const marketKey = `${eventId}_${market.type}_${extractLineValue(market.side_a)}`;
        const existingMarketId = existingMarketsMap.get(marketKey);

        if (existingMarketId) {
          // Market exists - update it
          marketsToUpdate.push({
            id: existingMarketId,
            record: {
              side_a: market.side_a,
              side_b: market.side_b,
              odds_a: market.odds_a,
              odds_b: market.odds_b,
            },
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

    // Update existing markets
    for (const { id, record } of marketsToUpdate) {
      const { error: updateMarketError } = await client
        .from('markets')
        .update(record)
        .eq('id', id);

      if (updateMarketError) {
        console.error(`Error updating market ${id}:`, updateMarketError);
        stats.errors.push(`Market update error for ${id}: ${updateMarketError.message}`);
      } else {
        stats.markets_updated++;
      }
    }

    console.log(`Markets: ${stats.markets_inserted} inserted, ${stats.markets_updated} updated`);
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
