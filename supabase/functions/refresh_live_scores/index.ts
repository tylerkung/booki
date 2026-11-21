import { corsHeaders } from '../_shared/cors.ts';
import { createServiceClient } from '../_shared/supabase.ts';
import { gradeBet, isDeferredMarket, leaveOpen, type BetInfo, type EventScores } from '../_shared/grading.ts';
import { settleReadyParlays } from '../_shared/parlay_apply.ts';
import { settleBetTx } from '../_shared/settle_tx.ts';
import { emitAuditEvent } from '../_shared/audit.ts';
import { recordQuota, resetQuota, getQuotaSnapshot } from '../_shared/odds_quota.ts';

/**
 * refresh_live_scores Edge Function
 *
 * Smart scores-only refresh that estimates when games are ending.
 * Runs every 5 minutes via cron but only calls the Odds API when
 * games with bets are in their "finishing window" or past estimated end.
 *
 * Most runs cost 0 API calls (just a DB query to check timing).
 * When games are finishing: 1 call per sport with ending games.
 *
 * Sport duration estimates (minutes):
 *   NBA: 150, NCAAB: 120, NFL: 210, NCAAF: 210,
 *   MLB: 180, NHL: 150, MMA: 240, Soccer: 120
 *
 * Finishing window = last 30 min of estimated duration + any time past estimated end.
 */

interface ScoreEvent {
  id: string;
  sport_key: string;
  home_team: string;
  away_team: string;
  commence_time: string;
  completed: boolean;
  scores: { name: string; score: string }[] | null;
}

/** Maps app sport/league names back to Odds API sport keys */
const SPORT_LEAGUE_TO_API_KEY: Record<string, string> = {
  'Basketball/NBA': 'basketball_nba',
  'Basketball/NCAAB': 'basketball_ncaab',
  'Football/NFL': 'americanfootball_nfl',
  'Football/NCAAF': 'americanfootball_ncaaf',
  'Baseball/MLB': 'baseball_mlb',
  'Hockey/NHL': 'icehockey_nhl',
  'MMA/MMA': 'mma_mixed_martial_arts',
  'Soccer/EPL': 'soccer_epl',
  'Soccer/La Liga': 'soccer_spain_la_liga',
  'Soccer/Serie A': 'soccer_italy_serie_a',
  'Soccer/Bundesliga': 'soccer_germany_bundesliga',
  'Soccer/Ligue 1': 'soccer_france_ligue_one',
  'Soccer/MLS': 'soccer_usa_mls',
};

/** Estimated game duration in minutes by sport */
const SPORT_DURATION_MINUTES: Record<string, number> = {
  'Basketball': 150,   // 2.5 hours
  'NCAAB': 120,        // 2 hours
  'Football': 210,     // 3.5 hours
  'Baseball': 180,     // 3 hours
  'Hockey': 150,       // 2.5 hours
  'MMA': 240,          // 4 hours
  'Soccer': 120,       // 2 hours
  'Tennis': 180,       // 3 hours (varies widely)
};

/** Minutes before estimated end to start aggressive fetching */
const FINISHING_WINDOW_MINUTES = 30;

function getSportApiKey(sport: string, league: string): string | null {
  return SPORT_LEAGUE_TO_API_KEY[`${sport}/${league}`] || null;
}

function getEstimatedDurationMinutes(sport: string): number {
  return SPORT_DURATION_MINUTES[sport] || 180; // default 3 hours
}

/**
 * Determines if a game is in its finishing window.
 * Returns true if elapsed time >= (estimated duration - finishing window).
 * Also returns true if game is past estimated end (overtime / delayed final).
 */
function isInFinishingWindow(startTime: string, sport: string, now: Date): boolean {
  const start = new Date(startTime);
  const elapsedMinutes = (now.getTime() - start.getTime()) / (1000 * 60);
  const estimatedDuration = getEstimatedDurationMinutes(sport);
  const windowStart = estimatedDuration - FINISHING_WINDOW_MINUTES;

  return elapsedMinutes >= windowStart;
}

async function fetchScoresFromApi(apiKey: string, sportKey: string, daysFrom: number = 3): Promise<ScoreEvent[]> {
  const url = new URL(`https://api.the-odds-api.com/v4/sports/${sportKey}/scores/`);
  url.searchParams.set('apiKey', apiKey);
  url.searchParams.set('daysFrom', String(daysFrom));

  const response = await fetch(url.toString());
  // Read as text first so the payload can be measured. Egress is billed on
  // these bytes, and response.json() discards the length.
  const body = await response.text();
  recordQuota(response, `scores:${sportKey}`, body.length);
  if (!response.ok) {
    throw new Error(`Scores API error: ${response.status} ${response.statusText}`);
  }

  return JSON.parse(body);
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  // Isolates are reused between invocations, so per-run counters must be
  // cleared or they accumulate across unrelated runs.
  resetQuota();

  try {
    const client = createServiceClient();
    const oddsApiKey = Deno.env.get('ODDS_API_KEY');

    if (!oddsApiKey) {
      return new Response(
        JSON.stringify({ success: false, error: 'ODDS_API_KEY not configured' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const now = new Date();

    // Find events with open bets that have started but aren't final
    const { data: liveBets, error: betsError } = await client
      .from('bets')
      .select('event_id, bookie_id')
      .in('status', ['accepted', 'pending']);

    if (betsError) {
      return new Response(
        JSON.stringify({ success: false, error: 'Failed to query bets' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    if (!liveBets || liveBets.length === 0) {
      const parlaysSettled = await settleReadyParlays(client);
      return new Response(
        JSON.stringify({ success: true, message: 'No open bets', skipped: true, api_calls: 0, parlays_settled: parlaysSettled }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const eventIds = [...new Set(liveBets.map((b) => b.event_id))];

    const { data: liveEvents, error: eventsError } = await client
      .from('events')
      .select('id, external_id, sport, league, home_team, away_team, start_time, status')
      .in('id', eventIds)
      .lt('start_time', now.toISOString())
      .not('status', 'in', '("final","canceled")');

    if (eventsError || !liveEvents || liveEvents.length === 0) {
      const parlaysSettled = await settleReadyParlays(client);
      return new Response(
        JSON.stringify({ success: true, message: 'No live events with bets', skipped: true, api_calls: 0, parlays_settled: parlaysSettled }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Filter to only games in their finishing window
    const finishingGames = liveEvents.filter((e) =>
      isInFinishingWindow(e.start_time, e.sport, now)
    );

    const skippedGames = liveEvents.length - finishingGames.length;

    if (finishingGames.length === 0) {
      // Log timing info for visibility
      const gameTimings = liveEvents.map((e) => {
        const elapsed = Math.round((now.getTime() - new Date(e.start_time).getTime()) / (1000 * 60));
        const est = getEstimatedDurationMinutes(e.sport);
        return `${e.sport}/${e.league}: ${elapsed}min elapsed of ~${est}min`;
      });

      const parlaysSettled = await settleReadyParlays(client);
      return new Response(
        JSON.stringify({
          success: true,
          message: 'No games in finishing window',
          skipped: true,
          api_calls: 0,
          live_games: liveEvents.length,
          game_timings: gameTimings,
          parlays_settled: parlaysSettled,
        }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Group finishing games by sport key
    const gamesBySport = new Map<string, typeof finishingGames>();
    for (const event of finishingGames) {
      if (!event.external_id) continue;
      const sportKey = getSportApiKey(event.sport, event.league);
      if (!sportKey) continue;
      const existing = gamesBySport.get(sportKey) || [];
      existing.push(event);
      gamesBySport.set(sportKey, existing);
    }

    let scoresRefreshed = 0;
    let eventsFinalized = 0;
    let betsGraded = 0;
    let apiCalls = 0;
    const errors: string[] = [];

    for (const [sportKey, games] of gamesBySport) {
      try {
        const scoreEvents = await fetchScoresFromApi(oddsApiKey, sportKey, 3);
        apiCalls++;

        for (const game of games) {
          try {
            const scoreEvent = scoreEvents.find((e) => e.id === game.external_id);
            if (!scoreEvent) continue;

            let homeScore: number | null = null;
            let awayScore: number | null = null;

            if (scoreEvent.scores && scoreEvent.scores.length > 0) {
              const homeTeamScore = scoreEvent.scores.find((s) => s.name === scoreEvent.home_team);
              const awayTeamScore = scoreEvent.scores.find((s) => s.name === scoreEvent.away_team);
              if (homeTeamScore?.score) {
                homeScore = parseInt(homeTeamScore.score, 10);
                if (isNaN(homeScore)) homeScore = null;
              }
              if (awayTeamScore?.score) {
                awayScore = parseInt(awayTeamScore.score, 10);
                if (isNaN(awayScore)) awayScore = null;
              }
            }

            const updateData: Record<string, unknown> = {
              last_auto_score_refresh: now.toISOString(),
            };

            if (homeScore !== null) updateData.home_score = homeScore;
            if (awayScore !== null) updateData.away_score = awayScore;

            const justFinalized = scoreEvent.completed && homeScore !== null && awayScore !== null;
            if (justFinalized) {
              updateData.status = 'final';
              updateData.final_score = `${awayScore}-${homeScore}`;
            }

            await client.from('events').update(updateData).eq('id', game.id);
            scoresRefreshed++;

            // Auto-grade bets if event just finalized
            if (justFinalized) {
              eventsFinalized++;

              const eventScores: EventScores = {
                homeScore: homeScore!,
                awayScore: awayScore!,
                homeTeam: game.home_team,
                awayTeam: game.away_team,
              };

              const { data: acceptedBets } = await client
                .from('bets')
                .select('id, market, side, bookie_id, player_id, stake, odds, is_parlay, ticket_id')
                .eq('event_id', game.id)
                .eq('status', 'accepted');

              if (acceptedBets && acceptedBets.length > 0) {
                for (const bet of acceptedBets) {
                  try {
                    // Props and futures are not score markets. Grading them
                    // here settled props as a push before grade_player_props
                    // could see them. A future is settle_outright's, after an
                    // admin records the winner. Leave the row exactly as it is.
                    if (isDeferredMarket(bet.market)) {
                      const owner = bet.market === 'outright' || bet.market === 'futures'
                        ? 'settle_outright'
                        : 'grade_player_props';
                      console.log(`Live scores: leaving ${bet.market} bet ${bet.id} for ${owner}`);
                      continue;
                    }

                    const betInfo: BetInfo = { id: bet.id, market: bet.market, side: bet.side };
                    const gradeOutcome = gradeBet(betInfo, eventScores);
                    if (leaveOpen(gradeOutcome.result)) {
                      const owner = bet.market === 'outright' || bet.market === 'futures'
                        ? 'settle_outright'
                        : 'manual review';
                      console.log(`Live scores: leaving ${bet.market} bet ${bet.id} for ${owner}`);
                      continue;
                    }

                    // Parlay legs: grade only. The ticket is settled below.
                    if (bet.is_parlay && bet.ticket_id) {
                      const { error: parlayUpdateError } = await client.from('bets').update({
                        status: 'graded',
                        grade_result: gradeOutcome.result,
                      }).eq('id', bet.id);
                      if (parlayUpdateError) {
                        console.error(`Live scores: parlay leg ${bet.id} was not graded:`, parlayUpdateError);
                        errors.push(`Bet ${bet.id}: ${parlayUpdateError.message}`);
                        continue;
                      }
                      betsGraded++;
                      console.log(`Live scores: graded parlay leg ${bet.id}: ${gradeOutcome.result}`);
                      continue;
                    }

                    // Record the grade, then let settle_bet_tx flip status and
                    // post the ledger in one transaction. grade_details and
                    // settled_amount are not columns; sending them made this
                    // update 400 and the old code wrote the ledger anyway.
                    const { error: gradeError } = await client.from('bets').update({
                      grade_result: gradeOutcome.result,
                      updated_at: new Date().toISOString(),
                    }).eq('id', bet.id).eq('status', 'accepted');
                    if (gradeError) {
                      console.error(`Live scores: bet ${bet.id} was not graded, ledger not written:`, gradeError);
                      errors.push(`Bet ${bet.id}: ${gradeError.message}`);
                      continue;
                    }

                    const posted = await settleBetTx(client, {
                      betId: bet.id,
                      actorUserId: null,
                      idempotencyKey: `live_settle_${bet.id}`,
                      mode: 'auto',
                    });
                    if (posted.error) {
                      console.error(`Live scores: bet ${bet.id} was not settled:`, posted.error);
                      errors.push(`Bet ${bet.id}: ${posted.error}`);
                      continue;
                    }

                    betsGraded++;
                    console.log(`Live scores: settled bet ${bet.id}: ${gradeOutcome.result}`);
                  } catch (betError) {
                    errors.push(`Bet ${bet.id}: ${betError instanceof Error ? betError.message : 'Unknown error'}`);
                  }
                }
              }
            }
          } catch (gameError) {
            errors.push(`Event ${game.id}: ${gameError instanceof Error ? gameError.message : 'Unknown error'}`);
          }
        }
      } catch (sportError) {
        errors.push(`Sport ${sportKey}: ${sportError instanceof Error ? sportError.message : 'Unknown error'}`);
      }
    }

    let parlaysSettled = 0;
    try {
      parlaysSettled = await settleReadyParlays(client);
    } catch (parlayError) {
      errors.push(`Parlay settlement: ${parlayError instanceof Error ? parlayError.message : 'Unknown error'}`);
    }

    const response = {
      success: true,
      quota: getQuotaSnapshot(),
      live_games_total: liveEvents.length,
      games_in_finishing_window: finishingGames.length,
      games_skipped_not_near_end: skippedGames,
      sports_queried: gamesBySport.size,
      api_calls: apiCalls,
      scores_refreshed: scoresRefreshed,
      events_finalized: eventsFinalized,
      bets_graded: betsGraded,
      parlays_settled: parlaysSettled,
      errors: errors,
    };

    console.log('refresh_live_scores complete:', JSON.stringify(response));

    return new Response(JSON.stringify(response), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (error) {
    console.error('Error in refresh_live_scores:', error);
    return new Response(
      JSON.stringify({ success: false, error: error instanceof Error ? error.message : 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
