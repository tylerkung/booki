import { corsHeaders } from '../_shared/cors.ts';
import { createServiceClient } from '../_shared/supabase.ts';
import { gradeBet, type BetInfo, type EventScores } from '../_shared/grading.ts';
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
  recordQuota(response, `scores:${sportKey}`);
  if (!response.ok) {
    throw new Error(`Scores API error: ${response.status} ${response.statusText}`);
  }
  return await response.json();
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
      return new Response(
        JSON.stringify({ success: true, message: 'No open bets', skipped: true, api_calls: 0 }),
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
      return new Response(
        JSON.stringify({ success: true, message: 'No live events with bets', skipped: true, api_calls: 0 }),
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

      return new Response(
        JSON.stringify({
          success: true,
          message: 'No games in finishing window',
          skipped: true,
          api_calls: 0,
          live_games: liveEvents.length,
          game_timings: gameTimings,
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
                    const betInfo: BetInfo = { id: bet.id, market: bet.market, side: bet.side };
                    const gradeOutcome = gradeBet(betInfo, eventScores);

                    // Parlay legs: grade only
                    if (bet.is_parlay && bet.ticket_id) {
                      await client.from('bets').update({
                        status: 'graded',
                        grade_result: gradeOutcome.result,
                        grade_details: gradeOutcome.gradeDetails,
                      }).eq('id', bet.id);
                      betsGraded++;
                      console.log(`Live scores: graded parlay leg ${bet.id}: ${gradeOutcome.result}`);
                      continue;
                    }

                    // Singles: grade + settle + ledger entry
                    // Convention: positive = player owes bookie, negative = bookie owes player
                    let payoutAmount = 0;
                    if (gradeOutcome.result === 'win') {
                      const stake = typeof bet.stake === 'number' ? bet.stake : parseFloat(String(bet.stake));
                      const odds = typeof bet.odds === 'number' ? bet.odds : parseFloat(String(bet.odds));
                      const profit = odds > 0
                        ? stake * (odds / 100)
                        : stake * (100 / Math.abs(odds));
                      payoutAmount = -profit; // Bookie owes player
                    } else if (gradeOutcome.result === 'loss') {
                      const stake = typeof bet.stake === 'number' ? bet.stake : parseFloat(String(bet.stake));
                      payoutAmount = stake; // Player owes bookie
                    }

                    await client.from('bets').update({
                      status: 'settled',
                      grade_result: gradeOutcome.result,
                      grade_details: gradeOutcome.gradeDetails,
                      settled_amount: payoutAmount,
                    }).eq('id', bet.id).eq('status', 'accepted');

                    // Check for existing ledger entry to prevent duplicates
                    const { data: existingLedger } = await client
                      .from('ledger_entries')
                      .select('id')
                      .eq('bet_id', bet.id)
                      .eq('type', 'settlement')
                      .limit(1);

                    if (existingLedger && existingLedger.length > 0) {
                      console.log(`Live scores: skipping ledger entry for bet ${bet.id} — already exists`);
                      betsGraded++;
                      continue;
                    }

                    const descriptionMap: Record<string, string> = { win: 'Bet won', loss: 'Bet lost', push: 'Bet pushed', void: 'Bet voided' };
                    const description = descriptionMap[gradeOutcome.result] || 'Bet settled';

                    const { data: ledgerEntry } = await client
                      .from('ledger_entries')
                      .insert({
                        bookie_id: bet.bookie_id,
                        player_id: bet.player_id,
                        bet_id: bet.id,
                        amount: payoutAmount,
                        type: 'settlement',
                        description: description,
                      })
                      .select()
                      .single();

                    if (ledgerEntry) {
                      try {
                        await client.from('settlement_events').insert({
                          bookie_id: bet.bookie_id,
                          bet_id: bet.id,
                          mode: 'auto',
                          idempotency_key: `live_settle_${bet.id}_${Date.now()}`,
                          ledger_entry_ids: [ledgerEntry.id],
                        });
                      } catch (seError) {
                        console.error(`Error writing settlement_event for bet ${bet.id}:`, seError);
                      }
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

    // Auto-settle parlays where all legs are now graded
    let parlaysSettled = 0;
    try {
      const { data: gradedLegs } = await client
        .from('bets')
        .select('id, ticket_id, bookie_id, player_id, stake, odds, grade_result, is_parlay')
        .eq('status', 'graded')
        .eq('is_parlay', true);

      if (gradedLegs && gradedLegs.length > 0) {
        const ticketMap = new Map<string, typeof gradedLegs>();
        for (const leg of gradedLegs) {
          if (!leg.ticket_id) continue;
          const existing = ticketMap.get(leg.ticket_id) || [];
          existing.push(leg);
          ticketMap.set(leg.ticket_id, existing);
        }

        for (const [ticketId, legs] of ticketMap) {
          const { count: totalLegs } = await client
            .from('bets')
            .select('*', { count: 'exact', head: true })
            .eq('ticket_id', ticketId);

          if (totalLegs !== legs.length) continue;

          const bookieId = legs[0].bookie_id;
          const playerId = legs[0].player_id;
          const stake = typeof legs[0].stake === 'number' ? legs[0].stake : parseFloat(String(legs[0].stake));

          const hasLoss = legs.some((l) => l.grade_result === 'loss');
          const winLegs = legs.filter((l) => l.grade_result === 'win');

          let payoutAmount = 0;
          let ticketResult = 'loss';

          // Convention: positive = player owes bookie, negative = bookie owes player
          if (!hasLoss && winLegs.length > 0) {
            let combinedMultiplier = 1;
            for (const leg of winLegs) {
              const odds = typeof leg.odds === 'number' ? leg.odds : parseFloat(String(leg.odds));
              if (odds > 0) combinedMultiplier *= (1 + odds / 100);
              else if (odds < 0) combinedMultiplier *= (1 + 100 / Math.abs(odds));
            }
            const profit = stake * (combinedMultiplier - 1);
            payoutAmount = -profit; // Bookie owes player
            ticketResult = 'win';
          } else if (hasLoss) {
            payoutAmount = stake; // Player owes bookie
            ticketResult = 'loss';
          }

          for (const leg of legs) {
            await client.from('bets').update({
              status: 'settled',
              settled_amount: leg.grade_result === 'win' ? payoutAmount / winLegs.length : 0,
            }).eq('id', leg.id);
          }

          const description = ticketResult === 'win' ? `Parlay won (${legs.length} legs)` : `Parlay lost (${legs.length} legs)`;

          const { data: ledgerEntry } = await client
            .from('ledger_entries')
            .insert({
              bookie_id: bookieId,
              player_id: playerId,
              amount: payoutAmount,
              type: 'settlement',
              description: description,
            })
            .select()
            .single();

          if (ledgerEntry) {
            try {
              await client.from('settlement_events').insert({
                bookie_id: bookieId,
                mode: 'auto',
                idempotency_key: `live_settle_parlay_${ticketId}_${Date.now()}`,
                ledger_entry_ids: [ledgerEntry.id],
              });
            } catch (seError) {
              console.error(`Error writing settlement_event for parlay ${ticketId}:`, seError);
            }
          }

          parlaysSettled++;
          console.log(`Live scores: settled parlay ${ticketId}: ${ticketResult}`);
        }
      }
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
