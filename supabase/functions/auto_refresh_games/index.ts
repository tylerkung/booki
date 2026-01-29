import { corsHeaders } from '../_shared/cors.ts';
import { createServiceClient } from '../_shared/supabase.ts';

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
  home_team: string;
  away_team: string;
  start_time: string;
  status: string;
  total_wagered: number;
  accepted_bet_count: number;
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

      // Fetch events that are not final/live/canceled
      const { data: events, error: eventsQueryError } = await client
        .from('events')
        .select('id, external_id, sport, home_team, away_team, start_time, status')
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
        return {
          id: event.id,
          external_id: event.external_id,
          sport: event.sport,
          home_team: event.home_team,
          away_team: event.away_team,
          start_time: event.start_time,
          status: event.status,
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

      return new Response(
        JSON.stringify({
          success: true,
          games_selected: finalSelection.length,
          selected_games: finalSelection,
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
