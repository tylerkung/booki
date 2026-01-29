import { corsHeaders } from '../_shared/cors.ts';
import { createServiceClient } from '../_shared/supabase.ts';
import { emitAuditEvent } from '../_shared/audit.ts';

/**
 * auto_refresh_games Edge Function
 *
 * Automatically refreshes odds and scores for up to 2 games with accepted bets.
 * Called twice daily via cron (morning and afternoon).
 *
 * Game selection criteria:
 * - Has at least one accepted bet
 * - Status is not 'final' (not completed)
 * - Not locked (status not in ['live', 'canceled'])
 * - Ordered by start_time ASC, then by total wagered amount DESC
 * - Limited to 2 games maximum
 */

interface SelectedGame {
  id: string;
  external_id: string | null;
  sport: string;
  league: string;
  home_team: string;
  away_team: string;
  start_time: string;
  status: string;
  bookie_id: string;
  bookie_auth_user_id: string | null;
  total_wagered: number;
  accepted_bet_count: number;
}

/**
 * Maps app-friendly sport/league names back to Odds API sport keys.
 * This is the reverse of OddsAPIMapper.sportKeyMapping in Swift.
 */
const sportLeagueToApiKey: Record<string, string> = {
  'Football_NFL': 'americanfootball_nfl',
  'Football_NCAAF': 'americanfootball_ncaaf',
  'Basketball_NBA': 'basketball_nba',
  'Basketball_NCAAB': 'basketball_ncaab',
  'Basketball_WNBA': 'basketball_wnba',
  'Baseball_MLB': 'baseball_mlb',
  'Hockey_NHL': 'icehockey_nhl',
  'Soccer_EPL': 'soccer_epl',
  'Soccer_MLS': 'soccer_usa_mls',
  'Soccer_Bundesliga': 'soccer_germany_bundesliga',
  'Soccer_La Liga': 'soccer_spain_la_liga',
  'Soccer_Serie A': 'soccer_italy_serie_a',
  'Soccer_Ligue 1': 'soccer_france_ligue_one',
  'MMA_UFC': 'mma_mixed_martial_arts',
  'Boxing_Boxing': 'boxing_boxing',
  'Golf_PGA': 'golf_pga_championship',
  'Tennis_ATP': 'tennis_atp_australian_open',
};

/**
 * Converts sport + league to Odds API sport key.
 */
function getSportApiKey(sport: string, league: string): string | null {
  const key = `${sport}_${league}`;
  return sportLeagueToApiKey[key] || null;
}

/**
 * Market data from Odds API response.
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
 * Extracts markets from Odds API response for a specific event.
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
    }
  }

  return markets;
}

Deno.serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // Read ODDS_API_KEY from environment
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

    const client = createServiceClient();

    // Query games that meet the selection criteria:
    // 1. Has at least one accepted bet
    // 2. Status is not 'final', 'live', or 'canceled' (i.e., still eligible for refresh)
    // 3. Order by start_time ASC, then total wagered DESC
    // 4. Limit to 2 games
    //
    // We use a raw query to aggregate bet data and filter properly
    const { data: selectedGames, error: queryError } = await client.rpc(
      'select_games_for_auto_refresh',
      { max_games: 2 }
    );

    // If RPC doesn't exist yet, fall back to a manual query approach
    if (queryError?.code === 'PGRST202') {
      // RPC function not found, use alternative query approach
      // First, get events with accepted bets
      const { data: eventsWithBets, error: eventsError } = await client
        .from('bets')
        .select('event_id, stake')
        .eq('status', 'accepted');

      if (eventsError) {
        console.error('Error fetching bets:', eventsError);
        return new Response(
          JSON.stringify({ success: false, error: 'Failed to query bets' }),
          {
            status: 500,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          }
        );
      }

      if (!eventsWithBets || eventsWithBets.length === 0) {
        return new Response(
          JSON.stringify({
            success: true,
            message: 'No games with accepted bets found',
            games_selected: 0,
            selected_games: [],
          }),
          {
            status: 200,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          }
        );
      }

      // Aggregate bet data by event_id
      const eventAggregates = new Map<
        string,
        { totalWagered: number; betCount: number }
      >();
      for (const bet of eventsWithBets) {
        const eventId = bet.event_id;
        const existing = eventAggregates.get(eventId) || {
          totalWagered: 0,
          betCount: 0,
        };
        existing.totalWagered += parseFloat(bet.stake) || 0;
        existing.betCount += 1;
        eventAggregates.set(eventId, existing);
      }

      const eventIds = Array.from(eventAggregates.keys());

      // Fetch events that are not final/live/canceled, with bookie auth_user_id
      const { data: events, error: eventsQueryError } = await client
        .from('events')
        .select('id, external_id, sport, league, home_team, away_team, start_time, status, bookie_id, bookies!inner(auth_user_id)')
        .in('id', eventIds)
        .not('status', 'in', '("final","live","canceled")')
        .order('start_time', { ascending: true });

      if (eventsQueryError) {
        console.error('Error fetching events:', eventsQueryError);
        return new Response(
          JSON.stringify({ success: false, error: 'Failed to query events' }),
          {
            status: 500,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          }
        );
      }

      if (!events || events.length === 0) {
        return new Response(
          JSON.stringify({
            success: true,
            message: 'No eligible games found for refresh',
            games_selected: 0,
            selected_games: [],
          }),
          {
            status: 200,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          }
        );
      }

      // Combine event data with aggregate bet data
      const gamesWithStats: SelectedGame[] = events.map((event) => {
        const agg = eventAggregates.get(event.id) || {
          totalWagered: 0,
          betCount: 0,
        };
        // Extract bookie auth_user_id from joined data
        const bookieData = event.bookies as { auth_user_id: string } | null;
        return {
          id: event.id,
          external_id: event.external_id,
          sport: event.sport,
          league: event.league,
          home_team: event.home_team,
          away_team: event.away_team,
          start_time: event.start_time,
          status: event.status,
          bookie_id: event.bookie_id,
          bookie_auth_user_id: bookieData?.auth_user_id || null,
          total_wagered: agg.totalWagered,
          accepted_bet_count: agg.betCount,
        };
      });

      // Sort by start_time ASC (already done), then by total_wagered DESC for tie-breaking
      gamesWithStats.sort((a, b) => {
        const timeA = new Date(a.start_time).getTime();
        const timeB = new Date(b.start_time).getTime();
        if (timeA !== timeB) {
          return timeA - timeB;
        }
        // Tie-breaker: higher total wagered first
        return b.total_wagered - a.total_wagered;
      });

      // Limit to 2 games
      const finalSelection = gamesWithStats.slice(0, 2);

      // ========================================
      // US-004: Odds Refresh Logic
      // ========================================
      const now = new Date();
      let oddsRefreshed = 0;
      const oddsErrors: { eventId: string; error: string }[] = [];

      // Group games by sport key for efficient API calls
      const gamesBySportKey = new Map<string, SelectedGame[]>();
      for (const game of finalSelection) {
        // Skip odds refresh if event has already started
        const startTime = new Date(game.start_time);
        if (startTime <= now) {
          console.log(`Skipping odds refresh for ${game.id} - event has started`);
          continue;
        }

        // Get the sport API key
        const sportKey = getSportApiKey(game.sport, game.league);
        if (!sportKey) {
          console.log(`Unknown sport/league mapping for ${game.sport}/${game.league}`);
          oddsErrors.push({
            eventId: game.id,
            error: `Unknown sport/league mapping: ${game.sport}/${game.league}`,
          });
          continue;
        }

        const existing = gamesBySportKey.get(sportKey) || [];
        existing.push(game);
        gamesBySportKey.set(sportKey, existing);
      }

      // Fetch odds for each sport and update markets
      for (const [sportKey, games] of gamesBySportKey) {
        try {
          console.log(`Fetching odds for sport: ${sportKey}`);
          const oddsEvents = await fetchOddsFromApi(oddsApiKey, sportKey);

          for (const game of games) {
            try {
              // Find matching odds event by external_id
              const oddsEvent = oddsEvents.find((e) => e.id === game.external_id);
              if (!oddsEvent) {
                console.log(`No odds found for event ${game.id} (external_id: ${game.external_id})`);
                continue;
              }

              // Extract markets from the odds event
              const newMarkets = extractMarketsFromOddsEvent(oddsEvent);
              if (newMarkets.length === 0) {
                console.log(`No markets extracted for event ${game.id}`);
                continue;
              }

              // Delete existing markets for this event
              const { error: deleteError } = await client
                .from('markets')
                .delete()
                .eq('event_id', game.id);

              if (deleteError) {
                console.error(`Error deleting markets for ${game.id}:`, deleteError);
                oddsErrors.push({ eventId: game.id, error: 'Failed to delete existing markets' });
                continue;
              }

              // Insert new markets
              const marketsToInsert = newMarkets.map((m) => ({
                bookie_id: game.bookie_id,
                event_id: game.id,
                type: m.type,
                side_a: m.side_a,
                side_b: m.side_b,
                odds_a: m.odds_a,
                odds_b: m.odds_b,
              }));

              const { error: insertError } = await client
                .from('markets')
                .insert(marketsToInsert);

              if (insertError) {
                console.error(`Error inserting markets for ${game.id}:`, insertError);
                oddsErrors.push({ eventId: game.id, error: 'Failed to insert new markets' });
                continue;
              }

              // Update event's last_auto_odds_refresh timestamp
              const refreshTimestamp = now.toISOString();
              const { error: updateError } = await client
                .from('events')
                .update({
                  last_auto_odds_refresh: refreshTimestamp,
                  last_odds_update: refreshTimestamp,
                })
                .eq('id', game.id);

              if (updateError) {
                console.error(`Error updating last_auto_odds_refresh for ${game.id}:`, updateError);
                oddsErrors.push({ eventId: game.id, error: 'Failed to update refresh timestamp' });
                continue;
              }

              // Emit audit event for successful odds refresh
              // Only emit if we have a valid auth_user_id
              if (game.bookie_auth_user_id) {
                await emitAuditEvent(client, {
                  bookieId: game.bookie_id,
                  actorUserId: game.bookie_auth_user_id,
                  entityType: 'event',
                  entityId: game.id,
                  actionType: 'odds_refreshed_auto',
                  previousState: null,
                  newState: {
                    markets_count: newMarkets.length,
                    last_auto_odds_refresh: refreshTimestamp,
                  },
                });
              }

              oddsRefreshed++;
              console.log(`Successfully refreshed odds for event ${game.id}`);
            } catch (gameError) {
              console.error(`Error refreshing odds for game ${game.id}:`, gameError);
              oddsErrors.push({
                eventId: game.id,
                error: gameError instanceof Error ? gameError.message : 'Unknown error',
              });
              // Continue processing other games
            }
          }
        } catch (sportError) {
          console.error(`Error fetching odds for sport ${sportKey}:`, sportError);
          // Add errors for all games that couldn't be refreshed
          for (const game of games) {
            oddsErrors.push({
              eventId: game.id,
              error: `API error for ${sportKey}: ${sportError instanceof Error ? sportError.message : 'Unknown error'}`,
            });
          }
          // Continue processing other sports
        }
      }

      return new Response(
        JSON.stringify({
          success: true,
          games_selected: finalSelection.length,
          selected_games: finalSelection,
          odds_refreshed: oddsRefreshed,
          odds_errors: oddsErrors,
        }),
        {
          status: 200,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      );
    }

    // If RPC exists and works
    if (queryError) {
      console.error('Error selecting games:', queryError);
      return new Response(
        JSON.stringify({
          success: false,
          error: 'Failed to select games for refresh',
        }),
        {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      );
    }

    // RPC path - TODO: implement odds refresh here as well when RPC is available
    return new Response(
      JSON.stringify({
        success: true,
        games_selected: selectedGames?.length || 0,
        selected_games: selectedGames || [],
      }),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    );
  } catch (error) {
    console.error('Error in auto_refresh_games:', error);
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
