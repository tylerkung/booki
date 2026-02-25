import { corsHeaders } from '../_shared/cors.ts';
import { createServiceClient } from '../_shared/supabase.ts';
import { emitAuditEvent } from '../_shared/audit.ts';
import { checkIdempotency, storeIdempotency } from '../_shared/idempotency.ts';
import { gradeBet, type BetInfo, type EventScores } from '../_shared/grading.ts';

/**
 * Generates an idempotency key for auto-refresh operations.
 * Format: auto_refresh_{YYYY-MM-DD}_{HH}
 * Uses the current UTC hour so each cron run gets its own key.
 */
function generateIdempotencyKey(): string {
  const now = new Date();
  const year = now.getUTCFullYear();
  const month = String(now.getUTCMonth() + 1).padStart(2, '0');
  const day = String(now.getUTCDate()).padStart(2, '0');
  const hour = String(now.getUTCHours()).padStart(2, '0');
  const dateStr = `${year}-${month}-${day}`;
  return `auto_refresh_${dateStr}_${hour}`;
}

/**
 * auto_refresh_games Edge Function
 *
 * Automatically refreshes odds and scores for up to 50 games with accepted bets.
 * Called every 2 hours via cron (9 runs/day, 8AM-midnight PT).
 *
 * Game selection criteria:
 * - Has at least one accepted bet
 * - Status is not 'final' (not completed)
 * - Not locked (status not in ['live', 'canceled'])
 * - Ordered by start_time ASC, then by total wagered amount DESC
 * - Limited to 50 games maximum
 *
 * Also includes catch-up grading: grades any accepted bets on events that are
 * already 'final' with scores (handles cases where events finalized between runs).
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
  // Golf tournaments
  'Golf_PGA': 'golf_pga_championship',
  'Golf_Masters': 'golf_masters_tournament',
  'Golf_The Open': 'golf_the_open_championship',
  'Golf_US Open': 'golf_us_open',
  // Tennis - ATP tournaments (use first available key for score lookups)
  'Tennis_ATP': 'tennis_atp_australian_open',
  // Tennis - WTA tournaments
  'Tennis_WTA': 'tennis_wta_australian_open',
};

/**
 * Maps sport/league to futures API keys for outright events.
 * Used when event.away_team === 'Outright'.
 */
const sportLeagueToFuturesKey: Record<string, string> = {
  'Basketball_NBA': 'basketball_nba_championship_winner',
  'Basketball_NCAAB': 'basketball_ncaab_championship_winner',
  'Football_NFL': 'americanfootball_nfl_super_bowl_winner',
  'Football_NCAAF': 'americanfootball_ncaaf_championship_winner',
  'Baseball_MLB': 'baseball_mlb_world_series_winner',
  'Hockey_NHL': 'icehockey_nhl_championship_winner',
  'Golf_Masters': 'golf_masters_tournament_winner',
  'Golf_PGA': 'golf_pga_championship_winner',
  'Golf_The Open': 'golf_the_open_championship_winner',
  'Golf_US Open': 'golf_us_open_winner',
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
  home_team: string | null;
  away_team: string | null;
  bookmakers?: OddsBookmaker[];
}

/**
 * Score data from Odds API response.
 */
interface ScoreTeam {
  name: string;
  score: string;
}

interface ScoreEvent {
  id: string;
  sport_key: string;
  sport_title: string;
  commence_time: string;
  completed: boolean;
  home_team: string;
  away_team: string;
  scores: ScoreTeam[] | null;
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
 * Fetches scores from The Odds API for a given sport.
 * Returns scores for games within the last few days.
 */
async function fetchScoresFromApi(
  apiKey: string,
  sportKey: string,
  daysFrom: number = 3
): Promise<ScoreEvent[]> {
  const url = new URL(`https://api.the-odds-api.com/v4/sports/${sportKey}/scores/`);
  url.searchParams.set('apiKey', apiKey);
  url.searchParams.set('daysFrom', String(daysFrom));

  const response = await fetch(url.toString());

  if (!response.ok) {
    throw new Error(`Scores API error: ${response.status} ${response.statusText}`);
  }

  return await response.json();
}

/**
 * Fetches outright/futures odds from The Odds API.
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

  if (!response.ok) {
    throw new Error(`Outrights API error: ${response.status} ${response.statusText}`);
  }

  return await response.json();
}

/**
 * Extracts outright markets from an Odds API event.
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

/**
 * Catch-up grading: finds accepted bets on already-final events and grades+settles them.
 * Also voids pending bets on final events (never accepted before game ended).
 * No API calls needed — purely database work.
 */
async function runCatchupGrading(client: ReturnType<typeof createServiceClient>): Promise<{
  catchupBetsSettled: number;
  catchupEventsProcessed: number;
  catchupBetsVoided: number;
  debug: Record<string, unknown>;
}> {
  let catchupBetsSettled = 0;
  let catchupEventsProcessed = 0;
  let catchupBetsVoided = 0;
  const debug: Record<string, unknown> = {};

  // 1. Grade accepted bets on final events
  try {
    const { data: strandedBets, error: strandedError } = await client
      .from('bets')
      .select('id, event_id, market, side, bookie_id, player_id, stake, odds, is_parlay, ticket_id')
      .eq('status', 'accepted');

    debug.acceptedBetsFound = strandedBets?.length ?? 0;

    if (!strandedError && strandedBets && strandedBets.length > 0) {
      const strandedEventIds = [...new Set(strandedBets.map((b) => b.event_id))];

      const { data: finalEvents, error: finalEventsError } = await client
        .from('events')
        .select('id, home_team, away_team, home_score, away_score')
        .in('id', strandedEventIds)
        .eq('status', 'final')
        .not('home_score', 'is', null)
        .not('away_score', 'is', null);

      debug.finalEventsWithScores = finalEvents?.length ?? 0;

      if (!finalEventsError && finalEvents && finalEvents.length > 0) {
        for (const event of finalEvents) {
          const eventBets = strandedBets.filter((b) => b.event_id === event.id);
          if (eventBets.length === 0) continue;

          const bookieId = eventBets[0].bookie_id;
          const { data: bookie } = await client
            .from('bookies')
            .select('auth_user_id, manual_bet_grading')
            .eq('id', bookieId)
            .single();

          if (bookie?.manual_bet_grading) {
            console.log(`Catch-up: skipping event ${event.id} - manual grading enabled`);
            continue;
          }

          const eventScores: EventScores = {
            homeScore: event.home_score!,
            awayScore: event.away_score!,
            homeTeam: event.home_team,
            awayTeam: event.away_team,
          };

          for (const bet of eventBets) {
            try {
              const betInfo: BetInfo = { id: bet.id, market: bet.market, side: bet.side };
              const gradeOutcome = gradeBet(betInfo, eventScores);

              // Parlay legs: grade only (don't settle individually — settle as ticket later)
              if (bet.is_parlay) {
                const { error: gradeError } = await client
                  .from('bets')
                  .update({
                    status: 'graded',
                    grade_result: gradeOutcome.result,
                    updated_at: new Date().toISOString(),
                  })
                  .eq('id', bet.id);
                if (!gradeError) {
                  console.log(`Catch-up: graded parlay leg ${bet.id}: ${gradeOutcome.result} (ticket ${bet.ticket_id})`);
                }
                continue;
              }

              const { error: updateError } = await client
                .from('bets')
                .update({
                  status: 'settled',
                  grade_result: gradeOutcome.result,
                  updated_at: new Date().toISOString(),
                })
                .eq('id', bet.id);

              if (updateError) {
                console.error(`Catch-up: error settling bet ${bet.id}:`, updateError);
                continue;
              }

              const stake = Number(bet.stake);
              const odds = Number(bet.odds);
              let payoutAmount = 0;
              if (gradeOutcome.result === 'win') {
                const profit = odds > 0
                  ? stake * (odds / 100)
                  : stake * (100 / Math.abs(odds));
                payoutAmount = -profit;
              } else if (gradeOutcome.result === 'loss') {
                payoutAmount = stake;
              }

              const descriptionMap: Record<string, string> = { win: 'Bet won', loss: 'Bet lost', push: 'Bet pushed', void: 'Bet voided' };
              const description = descriptionMap[gradeOutcome.result] || 'Bet settled';
              const { data: ledgerEntry, error: ledgerError } = await client
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

              // Write settlement_events row for audit trail
              if (ledgerEntry && !ledgerError) {
                try {
                  await client
                    .from('settlement_events')
                    .insert({
                      bookie_id: bet.bookie_id,
                      bet_id: bet.id,
                      mode: 'auto',
                      actor_user_id: bookie?.auth_user_id ?? null,
                      idempotency_key: `auto_settle_catchup_${bet.id}_${Date.now()}`,
                      ledger_entry_ids: [ledgerEntry.id],
                    });
                } catch (seError) {
                  console.error(`Catch-up: error writing settlement_event for bet ${bet.id}:`, seError);
                }
              }

              if (bookie?.auth_user_id) {
                await emitAuditEvent(client, {
                  bookieId: bet.bookie_id,
                  actorUserId: bookie.auth_user_id,
                  entityType: 'bet',
                  entityId: bet.id,
                  actionType: 'bet_auto_settled',
                  previousState: { status: 'accepted' },
                  newState: {
                    status: 'settled',
                    grade_result: gradeOutcome.result,
                    grade_details: gradeOutcome.gradeDetails,
                    payout_amount: payoutAmount,
                    catchup: true,
                  },
                });
              }

              catchupBetsSettled++;
              console.log(`Catch-up: settled bet ${bet.id}: ${gradeOutcome.result}`);
            } catch (betError) {
              console.error(`Catch-up: error grading bet ${bet.id}:`, betError);
            }
          }
          catchupEventsProcessed++;
        }
      }
    }
  } catch (catchupError) {
    console.error('Catch-up grading error:', catchupError);
    debug.gradingError = catchupError instanceof Error ? catchupError.message : 'Unknown';
  }

  // 2. Void pending bets on final events
  try {
    const { data: pendingBets, error: pendingError } = await client
      .from('bets')
      .select('id, event_id, bookie_id')
      .eq('status', 'pending');

    debug.pendingBetsFound = pendingBets?.length ?? 0;

    if (!pendingError && pendingBets && pendingBets.length > 0) {
      const pendingEventIds = [...new Set(pendingBets.map((b) => b.event_id))];

      // Check for final events OR events that started more than 6 hours ago (likely finished)
      const { data: finalEvents, error: finalError } = await client
        .from('events')
        .select('id, status, start_time')
        .in('id', pendingEventIds)
        .eq('status', 'final');

      debug.pendingBetsFinalEvents = finalEvents?.length ?? 0;

      // Also check for events that started long ago but aren't marked final (no scores fetched)
      const sixHoursAgo = new Date(Date.now() - 6 * 60 * 60 * 1000).toISOString();
      const { data: startedEvents } = await client
        .from('events')
        .select('id')
        .in('id', pendingEventIds)
        .neq('status', 'final')
        .neq('status', 'canceled')
        .lt('start_time', sixHoursAgo);

      debug.pendingBetsStartedEvents = startedEvents?.length ?? 0;

      const voidableEventIds = new Set([
        ...(finalEvents?.map((e) => e.id) ?? []),
        ...(startedEvents?.map((e) => e.id) ?? []),
      ]);

      const betsToVoid = pendingBets.filter((b) => voidableEventIds.has(b.event_id));
      debug.betsToVoid = betsToVoid.length;

      for (const bet of betsToVoid) {
        try {
          const { error: voidError } = await client
            .from('bets')
            .update({
              status: 'void',
              grade_result: 'void',
              updated_at: new Date().toISOString(),
            })
            .eq('id', bet.id);

          if (voidError) {
            console.error(`Catch-up: error voiding bet ${bet.id}:`, voidError);
            continue;
          }

          const { data: bookie } = await client
            .from('bookies')
            .select('auth_user_id')
            .eq('id', bet.bookie_id)
            .single();

          if (bookie?.auth_user_id) {
            await emitAuditEvent(client, {
              bookieId: bet.bookie_id,
              actorUserId: bookie.auth_user_id,
              entityType: 'bet',
              entityId: bet.id,
              actionType: 'bet_auto_voided',
              previousState: { status: 'pending' },
              newState: {
                status: 'void',
                reason: 'Event finalized or started while bet was still pending',
              },
            });
          }

          catchupBetsVoided++;
          console.log(`Catch-up: voided pending bet ${bet.id}`);
        } catch (voidBetError) {
          console.error(`Catch-up: error voiding bet ${bet.id}:`, voidBetError);
        }
      }
    }
  } catch (voidError) {
    console.error('Catch-up void error:', voidError);
    debug.voidError = voidError instanceof Error ? voidError.message : 'Unknown';
  }

  return { catchupBetsSettled, catchupEventsProcessed, catchupBetsVoided, debug };
}

/**
 * Auto-settle parlays where all legs are graded.
 * Finds tickets with all legs in 'graded' status, calculates combined odds,
 * creates one ledger entry per ticket, and marks all legs as 'settled'.
 */
async function autoSettleParlays(client: ReturnType<typeof createServiceClient>): Promise<number> {
  let parlaysSettled = 0;

  // Find all graded parlay legs
  const { data: gradedLegs, error } = await client
    .from('bets')
    .select('id, ticket_id, bookie_id, player_id, stake, odds, grade_result, is_parlay')
    .eq('status', 'graded')
    .eq('is_parlay', true);

  if (error || !gradedLegs || gradedLegs.length === 0) return 0;

  // Group by ticket_id
  const ticketMap = new Map<string, typeof gradedLegs>();
  for (const leg of gradedLegs) {
    const existing = ticketMap.get(leg.ticket_id) ?? [];
    existing.push(leg);
    ticketMap.set(leg.ticket_id, existing);
  }

  for (const [ticketId, legs] of ticketMap.entries()) {
    try {
      // Check ALL legs of this ticket are graded (some may still be accepted/pending)
      const { count: totalLegs } = await client
        .from('bets')
        .select('*', { count: 'exact', head: true })
        .eq('ticket_id', ticketId);

      if ((totalLegs ?? 0) !== legs.length) {
        // Not all legs graded yet — skip
        continue;
      }

      const stake = Number(legs[0].stake);
      const bookieId = legs[0].bookie_id;
      const playerId = legs[0].player_id;

      // Determine parlay outcome
      const hasLoss = legs.some((l) => l.grade_result === 'loss');
      const pushVoidLegs = legs.filter((l) => l.grade_result === 'push' || l.grade_result === 'void');
      const winLegs = legs.filter((l) => l.grade_result === 'win');

      let outcome: 'win' | 'loss' | 'push';
      let payoutAmount: number;

      if (hasLoss) {
        outcome = 'loss';
        payoutAmount = stake; // Player owes bookie
      } else if (pushVoidLegs.length === 0) {
        // All legs won
        outcome = 'win';
        const combinedDecimalOdds = winLegs.reduce((acc, leg) => {
          const odds = Number(leg.odds);
          return acc * (odds > 0 ? 1 + odds / 100 : 1 + 100 / Math.abs(odds));
        }, 1);
        const profit = stake * combinedDecimalOdds - stake;
        payoutAmount = -profit; // Bookie owes player
      } else if (winLegs.length === 0) {
        // All push/void
        outcome = 'push';
        payoutAmount = 0;
      } else {
        // Mixed win + push/void — reduceLegReprice (exclude push/void legs)
        outcome = 'win';
        const combinedDecimalOdds = winLegs.reduce((acc, leg) => {
          const odds = Number(leg.odds);
          return acc * (odds > 0 ? 1 + odds / 100 : 1 + 100 / Math.abs(odds));
        }, 1);
        const profit = stake * combinedDecimalOdds - stake;
        payoutAmount = -profit;
      }

      const outcomeLabel = outcome === 'win' ? 'won' : outcome === 'loss' ? 'lost' : 'pushed';
      const description = `Multi-Pick (${legs.length} legs) ${outcomeLabel}`;

      // Create single ledger entry for the parlay
      const { data: ledgerEntry, error: ledgerError } = await client
        .from('ledger_entries')
        .insert({
          bookie_id: bookieId,
          player_id: playerId,
          bet_id: legs[0].id,
          amount: payoutAmount,
          type: 'settlement',
          description: description,
        })
        .select()
        .single();

      if (ledgerError || !ledgerEntry) {
        console.error(`Auto-settle parlay: error creating ledger entry for ticket ${ticketId}:`, ledgerError);
        continue;
      }

      // Update all legs to 'settled'
      const legIds = legs.map((l) => l.id);
      const { error: updateError } = await client
        .from('bets')
        .update({ status: 'settled', updated_at: new Date().toISOString() })
        .in('id', legIds);

      if (updateError) {
        console.error(`Auto-settle parlay: error updating legs for ticket ${ticketId}:`, updateError);
        continue;
      }

      // Write settlement_events row
      try {
        const { data: bookie } = await client
          .from('bookies')
          .select('auth_user_id')
          .eq('id', bookieId)
          .single();

        await client
          .from('settlement_events')
          .insert({
            bookie_id: bookieId,
            bet_id: legs[0].id,
            mode: 'auto',
            actor_user_id: bookie?.auth_user_id ?? null,
            idempotency_key: `auto_settle_parlay_${ticketId}_${Date.now()}`,
            ledger_entry_ids: [ledgerEntry.id],
          });

        if (bookie?.auth_user_id) {
          await emitAuditEvent(client, {
            bookieId: bookieId,
            actorUserId: bookie.auth_user_id,
            entityType: 'bet',
            entityId: legs[0].id,
            actionType: 'parlay_auto_settled',
            previousState: { ticket_id: ticketId, leg_count: legs.length },
            newState: {
              ticket_id: ticketId,
              outcome,
              payout: payoutAmount,
              legs_settled: legs.length,
              ledger_entry_id: ledgerEntry.id,
            },
          });
        }
      } catch (err) {
        console.error(`Auto-settle parlay: error writing settlement_event for ticket ${ticketId}:`, err);
      }

      parlaysSettled++;
      console.log(`Auto-settled parlay ticket ${ticketId}: ${outcome}, payout=${payoutAmount}`);
    } catch (err) {
      console.error(`Auto-settle parlay: error processing ticket ${ticketId}:`, err);
    }
  }

  return parlaysSettled;
}

Deno.serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // Parse request body for force flag
    let force = false;
    try {
      const body = await req.json();
      force = body?.force === true;
    } catch {
      // No body or invalid JSON — that's fine
    }

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

    // ========================================
    // US-007: Idempotency Check (skip if force=true)
    // ========================================
    const idempotencyKey = generateIdempotencyKey();
    const operation = 'auto_refresh_games';

    if (!force) {
      // Check if this refresh window has already been processed
      const cachedResponse = await checkIdempotency(client, idempotencyKey, operation);
      if (cachedResponse) {
        console.log(`Idempotency key ${idempotencyKey} already exists, returning cached response`);
        return new Response(cachedResponse, {
          status: 200,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }
    } else {
      console.log('Force mode: skipping idempotency check');
    }

    // Query games that meet the selection criteria:
    // 1. Has at least one accepted bet
    // 2. Status is not 'final', 'live', or 'canceled' (i.e., still eligible for refresh)
    // 3. Order by start_time ASC, then total wagered DESC
    // 4. Limit to 25 games
    //
    // We use a raw query to aggregate bet data and filter properly
    const { data: selectedGames, error: queryError } = await client.rpc(
      'select_games_for_auto_refresh',
      { max_games: 25 }
    );

    // If RPC doesn't exist yet, fall back to a manual query approach
    if (queryError?.code === 'PGRST202') {
      // RPC function not found, use alternative query approach
      // First, get events with accepted or pending bets (pending need score refresh for void logic)
      const { data: eventsWithBets, error: eventsError } = await client
        .from('bets')
        .select('event_id, stake, bookie_id')
        .in('status', ['accepted', 'pending']);

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
        // Still run catch-up grading for already-final events
        const catchup = await runCatchupGrading(client);
        const responseBody = {
          success: true,
          message: 'No games with open bets found',
          games_selected: 0,
          odds_refreshed: 0,
          scores_refreshed: 0,
          events_finalized: 0,
          bets_transitioned: 0,
          bets_graded: 0,
          bets_settled: catchup.catchupBetsSettled,
          catchup_bets_settled: catchup.catchupBetsSettled,
          catchup_bets_voided: catchup.catchupBetsVoided,
          catchup_events_processed: catchup.catchupEventsProcessed,
          catchup_debug: catchup.debug,
          errors: [],
        };
        const responseString = JSON.stringify(responseBody);
        // Store idempotency key even for empty results
        await storeIdempotency(client, idempotencyKey, operation, 'system', responseString);
        return new Response(responseString, {
          status: 200,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }

      // Aggregate bet data by event_id
      const eventAggregates = new Map<
        string,
        { totalWagered: number; betCount: number; bookieId: string }
      >();
      for (const bet of eventsWithBets) {
        const eventId = bet.event_id;
        const existing = eventAggregates.get(eventId) || {
          totalWagered: 0,
          betCount: 0,
          bookieId: bet.bookie_id,
        };
        existing.totalWagered += parseFloat(bet.stake) || 0;
        existing.betCount += 1;
        eventAggregates.set(eventId, existing);
      }

      const eventIds = Array.from(eventAggregates.keys());

      // Fetch events that are not final/live/canceled (no bookie join — events are shared with bookie_id=NULL)
      const { data: events, error: eventsQueryError } = await client
        .from('events')
        .select('id, external_id, sport, league, home_team, away_team, start_time, status, bookie_id')
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
        // Still run catch-up grading for already-final events
        const catchup = await runCatchupGrading(client);
        const responseBody = {
          success: true,
          message: 'No eligible games found for refresh',
          games_selected: 0,
          odds_refreshed: 0,
          scores_refreshed: 0,
          events_finalized: 0,
          bets_transitioned: 0,
          bets_graded: 0,
          bets_settled: catchup.catchupBetsSettled,
          catchup_bets_settled: catchup.catchupBetsSettled,
          catchup_bets_voided: catchup.catchupBetsVoided,
          catchup_events_processed: catchup.catchupEventsProcessed,
          catchup_debug: catchup.debug,
          errors: [],
        };
        const responseString = JSON.stringify(responseBody);
        // Store idempotency key even for empty results
        await storeIdempotency(client, idempotencyKey, operation, 'system', responseString);
        return new Response(responseString, {
          status: 200,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }

      // Combine event data with aggregate bet data
      // Look up bookie auth_user_ids from the bets' bookie_ids
      const uniqueBookieIds = [...new Set(Array.from(eventAggregates.values()).map((a) => a.bookieId))];
      const { data: bookies } = await client
        .from('bookies')
        .select('id, auth_user_id')
        .in('id', uniqueBookieIds);
      const bookieAuthMap = new Map((bookies ?? []).map((b) => [b.id, b.auth_user_id]));

      const gamesWithStats: SelectedGame[] = events.map((event) => {
        const agg = eventAggregates.get(event.id) || {
          totalWagered: 0,
          betCount: 0,
          bookieId: '',
        };
        return {
          id: event.id,
          external_id: event.external_id,
          sport: event.sport,
          league: event.league,
          home_team: event.home_team,
          away_team: event.away_team,
          start_time: event.start_time,
          status: event.status,
          bookie_id: agg.bookieId || event.bookie_id,
          bookie_auth_user_id: bookieAuthMap.get(agg.bookieId) || null,
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

      // Limit to 50 games
      const finalSelection = gamesWithStats.slice(0, 50);

      // ========================================
      // US-004: Odds Refresh Logic
      // ========================================
      const now = new Date();
      let oddsRefreshed = 0;
      const oddsErrors: { eventId: string; error: string }[] = [];

      // Group games by sport key for efficient API calls
      // Outright events use separate futures API keys
      const gamesBySportKey = new Map<string, SelectedGame[]>();
      const gamesByFuturesKey = new Map<string, SelectedGame[]>();
      for (const game of finalSelection) {
        // Skip odds refresh if event has already started (but not outrights — they have distant future dates)
        const isOutright = game.away_team === 'Outright';
        if (!isOutright) {
          const startTime = new Date(game.start_time);
          if (startTime <= now) {
            console.log(`Skipping odds refresh for ${game.id} - event has started`);
            continue;
          }
        }

        if (isOutright) {
          // Use futures API key for outright events
          const futuresKey = sportLeagueToFuturesKey[`${game.sport}_${game.league}`];
          if (!futuresKey) {
            console.log(`Unknown futures mapping for ${game.sport}/${game.league}`);
            oddsErrors.push({
              eventId: game.id,
              error: `Unknown futures mapping: ${game.sport}/${game.league}`,
            });
            continue;
          }
          const existing = gamesByFuturesKey.get(futuresKey) || [];
          existing.push(game);
          gamesByFuturesKey.set(futuresKey, existing);
        } else {
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

      // ========================================
      // Futures Odds Refresh (outright events)
      // ========================================
      for (const [futuresKey, games] of gamesByFuturesKey) {
        try {
          console.log(`Fetching outright odds for: ${futuresKey}`);
          const oddsEvents = await fetchOutrightsFromApi(oddsApiKey, futuresKey);

          for (const game of games) {
            try {
              const oddsEvent = oddsEvents.find((e) => e.id === game.external_id);
              if (!oddsEvent) {
                console.log(`No outright odds found for event ${game.id}`);
                continue;
              }

              const newMarkets = extractOutrightMarkets(oddsEvent);
              if (newMarkets.length === 0) continue;

              // For outrights, update existing markets by side_a (outcome name)
              const { data: existingMarkets } = await client
                .from('markets')
                .select('id, side_a')
                .eq('event_id', game.id)
                .eq('type', 'outright');

              const existingMap = new Map<string, string>();
              if (existingMarkets) {
                for (const m of existingMarkets) {
                  existingMap.set(m.side_a, m.id);
                }
              }

              for (const market of newMarkets) {
                const existingId = existingMap.get(market.side_a);
                if (existingId) {
                  await client
                    .from('markets')
                    .update({ odds_a: market.odds_a })
                    .eq('id', existingId);
                } else {
                  await client
                    .from('markets')
                    .insert({
                      event_id: game.id,
                      bookie_id: null,
                      type: 'outright',
                      side_a: market.side_a,
                      side_b: market.side_b,
                      odds_a: market.odds_a,
                      odds_b: 0,
                    });
                }
              }

              // Update refresh timestamp
              await client
                .from('events')
                .update({
                  last_auto_odds_refresh: now.toISOString(),
                  last_odds_update: now.toISOString(),
                })
                .eq('id', game.id);

              oddsRefreshed++;
              console.log(`Refreshed outright odds for event ${game.id} (${newMarkets.length} outcomes)`);
            } catch (gameError) {
              console.error(`Error refreshing outright odds for ${game.id}:`, gameError);
              oddsErrors.push({
                eventId: game.id,
                error: gameError instanceof Error ? gameError.message : 'Unknown error',
              });
            }
          }
        } catch (sportError) {
          console.error(`Error fetching outright odds for ${futuresKey}:`, sportError);
          for (const game of games) {
            oddsErrors.push({
              eventId: game.id,
              error: `Outrights API error for ${futuresKey}: ${sportError instanceof Error ? sportError.message : 'Unknown error'}`,
            });
          }
        }
      }

      // ========================================
      // US-005: Score Refresh Logic
      // ========================================
      let scoresRefreshed = 0;
      const scoreErrors: { eventId: string; error: string }[] = [];

      // ========================================
      // US-006: Track finalized events and graded bets
      // ========================================
      let eventsFinalized = 0;
      let betsTransitioned = 0;
      let betsGraded = 0;
      let betsSettled = 0;

      // Group games by sport key for score fetching
      const gamesForScoresBySportKey = new Map<string, SelectedGame[]>();
      for (const game of finalSelection) {
        // Skip score refresh for outright events (no scores)
        if (game.away_team === 'Outright') {
          console.log(`Skipping score refresh for ${game.id} - outright/futures event`);
          continue;
        }

        // Only fetch scores for games that have an external_id (imported from API)
        if (!game.external_id) {
          console.log(`Skipping score refresh for ${game.id} - no external_id`);
          continue;
        }

        // Get the sport API key
        const sportKey = getSportApiKey(game.sport, game.league);
        if (!sportKey) {
          console.log(`Unknown sport/league mapping for scores: ${game.sport}/${game.league}`);
          scoreErrors.push({
            eventId: game.id,
            error: `Unknown sport/league mapping: ${game.sport}/${game.league}`,
          });
          continue;
        }

        const existing = gamesForScoresBySportKey.get(sportKey) || [];
        existing.push(game);
        gamesForScoresBySportKey.set(sportKey, existing);
      }

      // Fetch scores for each sport and update events
      for (const [sportKey, games] of gamesForScoresBySportKey) {
        try {
          console.log(`Fetching scores for sport: ${sportKey}`);
          const scoreEvents = await fetchScoresFromApi(oddsApiKey, sportKey, 3);

          for (const game of games) {
            try {
              // Find matching score event by external_id
              const scoreEvent = scoreEvents.find((e) => e.id === game.external_id);
              if (!scoreEvent) {
                console.log(`No scores found for event ${game.id} (external_id: ${game.external_id})`);
                continue;
              }

              // Parse scores from the response
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

              // Build update object
              const refreshTimestamp = now.toISOString();
              const updateData: Record<string, unknown> = {
                last_auto_score_refresh: refreshTimestamp,
              };

              // Update scores if available
              if (homeScore !== null) {
                updateData.home_score = homeScore;
              }
              if (awayScore !== null) {
                updateData.away_score = awayScore;
              }

              // If game is completed, set status to final and build final_score string
              if (scoreEvent.completed && homeScore !== null && awayScore !== null) {
                updateData.status = 'final';
                // Format: away-home (matches Swift convention)
                updateData.final_score = `${awayScore}-${homeScore}`;
              }

              // Update the event
              const { error: updateError } = await client
                .from('events')
                .update(updateData)
                .eq('id', game.id);

              if (updateError) {
                console.error(`Error updating scores for ${game.id}:`, updateError);
                scoreErrors.push({ eventId: game.id, error: 'Failed to update scores' });
                continue;
              }

              // Emit audit event for successful score refresh
              if (game.bookie_auth_user_id) {
                await emitAuditEvent(client, {
                  bookieId: game.bookie_id,
                  actorUserId: game.bookie_auth_user_id,
                  entityType: 'event',
                  entityId: game.id,
                  actionType: 'score_refreshed_auto',
                  previousState: null,
                  newState: {
                    home_score: homeScore,
                    away_score: awayScore,
                    completed: scoreEvent.completed,
                    status: scoreEvent.completed ? 'final' : game.status,
                    last_auto_score_refresh: refreshTimestamp,
                  },
                });
              }

              scoresRefreshed++;
              console.log(`Successfully refreshed scores for event ${game.id}: ${awayScore}-${homeScore} (completed: ${scoreEvent.completed})`);

              // ========================================
              // US-005: Auto-grade bets when event finalizes
              // US-009: Check bookie's manual_bet_grading setting
              // ========================================
              if (scoreEvent.completed && homeScore !== null && awayScore !== null) {
                // Event just became final - check if auto-grading is enabled for this bookie
                try {
                  // Check bookie's manual_bet_grading setting
                  const { data: bookie } = await client
                    .from('bookies')
                    .select('manual_bet_grading')
                    .eq('id', game.bookie_id)
                    .single();

                  // If manual grading is enabled, skip auto-grading
                  if (bookie?.manual_bet_grading) {
                    console.log(`Skipping auto-grading for event ${game.id} - bookie has manual grading enabled`);
                    eventsFinalized++;
                    // Still emit audit event for event finalization
                    if (game.bookie_auth_user_id) {
                      await emitAuditEvent(client, {
                        bookieId: game.bookie_id,
                        actorUserId: game.bookie_auth_user_id,
                        entityType: 'event',
                        entityId: game.id,
                        actionType: 'event_finalized_auto',
                        previousState: null,
                        newState: {
                          final_score: `${awayScore}-${homeScore}`,
                          bets_graded: 0,
                          manual_grading_enabled: true,
                        },
                      });
                    }
                    continue;
                  }

                  // Query all bets for this event with status 'accepted', including market/side/financial info
                  const { data: acceptedBets, error: betsQueryError } = await client
                    .from('bets')
                    .select('id, market, side, bookie_id, player_id, stake, odds, is_parlay, ticket_id')
                    .eq('event_id', game.id)
                    .eq('status', 'accepted');

                  if (betsQueryError) {
                    console.error(`Error querying accepted bets for event ${game.id}:`, betsQueryError);
                  } else if (acceptedBets && acceptedBets.length > 0) {
                    // Prepare event scores for grading
                    const eventScores: EventScores = {
                      homeScore: homeScore,
                      awayScore: awayScore,
                      homeTeam: game.home_team,
                      awayTeam: game.away_team,
                    };

                    let gradedCount = 0;
                    const gradingErrors: string[] = [];

                    // Grade each bet individually
                    for (const bet of acceptedBets) {
                      try {
                        const betInfo: BetInfo = {
                          id: bet.id,
                          market: bet.market,
                          side: bet.side,
                        };

                        // Get grade result from grading logic
                        const gradeOutcome = gradeBet(betInfo, eventScores);

                        // Parlay legs: grade only (settle as ticket later)
                        if (bet.is_parlay) {
                          const { error: gradeError } = await client
                            .from('bets')
                            .update({
                              status: 'graded',
                              grade_result: gradeOutcome.result,
                              updated_at: new Date().toISOString(),
                            })
                            .eq('id', bet.id);
                          if (!gradeError) {
                            gradedCount++;
                            console.log(`Graded parlay leg ${bet.id}: ${gradeOutcome.result} (ticket ${bet.ticket_id})`);
                          }
                          continue;
                        }

                        // Update bet with grade result — go straight to 'settled'
                        const { error: updateError } = await client
                          .from('bets')
                          .update({
                            status: 'settled',
                            grade_result: gradeOutcome.result,
                            updated_at: new Date().toISOString(),
                          })
                          .eq('id', bet.id);

                        if (updateError) {
                          console.error(`Error settling bet ${bet.id}:`, updateError);
                          gradingErrors.push(`Bet ${bet.id}: ${updateError.message}`);
                          continue;
                        }

                        // Create ledger entry for the settlement
                        const stake = Number(bet.stake);
                        const odds = Number(bet.odds);
                        let payoutAmount = 0;
                        if (gradeOutcome.result === 'win') {
                          // Player wins: profit is negative (bookie owes player)
                          const profit = odds > 0
                            ? stake * (odds / 100)
                            : stake * (100 / Math.abs(odds));
                          payoutAmount = -profit;
                        } else if (gradeOutcome.result === 'loss') {
                          // Player loses: stake is positive (player owes bookie)
                          payoutAmount = stake;
                        }
                        // Always create ledger entry — including $0 for push/void
                        const descriptionMap: Record<string, string> = { win: 'Bet won', loss: 'Bet lost', push: 'Bet pushed', void: 'Bet voided' };
                        const description = descriptionMap[gradeOutcome.result] || 'Bet settled';
                        const { data: ledgerEntry, error: ledgerError } = await client
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

                        if (ledgerError) {
                          console.error(`Error creating ledger entry for bet ${bet.id}:`, ledgerError);
                          gradingErrors.push(`Bet ${bet.id}: ledger entry failed - ${ledgerError.message}`);
                        }

                        // Write settlement_events row for audit trail
                        if (ledgerEntry && !ledgerError) {
                          try {
                            await client
                              .from('settlement_events')
                              .insert({
                                bookie_id: bet.bookie_id,
                                bet_id: bet.id,
                                mode: 'auto',
                                actor_user_id: game.bookie_auth_user_id ?? null,
                                idempotency_key: `auto_settle_${bet.id}_${Date.now()}`,
                                ledger_entry_ids: [ledgerEntry.id],
                              });
                          } catch (seError) {
                            console.error(`Error writing settlement_event for bet ${bet.id}:`, seError);
                          }
                        }

                        // Emit audit event for auto-graded and settled bet
                        if (game.bookie_auth_user_id) {
                          await emitAuditEvent(client, {
                            bookieId: bet.bookie_id,
                            actorUserId: game.bookie_auth_user_id,
                            entityType: 'bet',
                            entityId: bet.id,
                            actionType: 'bet_auto_settled',
                            previousState: { status: 'accepted' },
                            newState: {
                              status: 'settled',
                              grade_result: gradeOutcome.result,
                              grade_details: gradeOutcome.gradeDetails,
                              payout_amount: payoutAmount,
                            },
                          });
                        }

                        gradedCount++;
                        betsSettled++;
                        console.log(`Settled bet ${bet.id}: ${gradeOutcome.result} - ${gradeOutcome.gradeDetails}`);
                      } catch (betGradeError) {
                        console.error(`Error grading bet ${bet.id}:`, betGradeError);
                        gradingErrors.push(`Bet ${bet.id}: ${betGradeError instanceof Error ? betGradeError.message : 'Unknown error'}`);
                        // Continue grading other bets
                      }
                    }

                    betsGraded += gradedCount;
                    betsTransitioned += acceptedBets.length;
                    eventsFinalized++;
                    console.log(`Graded ${gradedCount}/${acceptedBets.length} bets for event ${game.id}`);

                    // Emit audit event for event finalization with grading summary
                    if (game.bookie_auth_user_id) {
                      await emitAuditEvent(client, {
                        bookieId: game.bookie_id,
                        actorUserId: game.bookie_auth_user_id,
                        entityType: 'event',
                        entityId: game.id,
                        actionType: 'event_finalized_auto',
                        previousState: null,
                        newState: {
                          final_score: `${awayScore}-${homeScore}`,
                          bets_graded: gradedCount,
                          bets_total: acceptedBets.length,
                          grading_errors: gradingErrors.length > 0 ? gradingErrors : null,
                        },
                      });
                    }
                  } else {
                    // Event finalized but no accepted bets
                    eventsFinalized++;
                    console.log(`Event ${game.id} finalized but no accepted bets to grade`);

                    // Still emit audit event for tracking
                    if (game.bookie_auth_user_id) {
                      await emitAuditEvent(client, {
                        bookieId: game.bookie_id,
                        actorUserId: game.bookie_auth_user_id,
                        entityType: 'event',
                        entityId: game.id,
                        actionType: 'event_finalized_auto',
                        previousState: null,
                        newState: {
                          final_score: `${awayScore}-${homeScore}`,
                          bets_graded: 0,
                        },
                      });
                    }
                  }
                } catch (gradingError) {
                  console.error(`Error grading bets for event ${game.id}:`, gradingError);
                  // Don't fail the whole score refresh for grading errors
                }
              }
            } catch (gameError) {
              console.error(`Error refreshing scores for game ${game.id}:`, gameError);
              scoreErrors.push({
                eventId: game.id,
                error: gameError instanceof Error ? gameError.message : 'Unknown error',
              });
              // Continue processing other games
            }
          }
        } catch (sportError) {
          console.error(`Error fetching scores for sport ${sportKey}:`, sportError);
          // Add errors for all games that couldn't be refreshed
          for (const game of games) {
            scoreErrors.push({
              eventId: game.id,
              error: `Scores API error for ${sportKey}: ${sportError instanceof Error ? sportError.message : 'Unknown error'}`,
            });
          }
          // Continue processing other sports
        }
      }

      // ========================================
      // US-007: Emit auto_refresh_failed audit events for errors
      // ========================================
      const allErrors: { eventId: string; error: string; type: 'odds' | 'scores' }[] = [
        ...oddsErrors.map((e) => ({ ...e, type: 'odds' as const })),
        ...scoreErrors.map((e) => ({ ...e, type: 'scores' as const })),
      ];

      // Emit audit events for each error
      for (const errorEntry of allErrors) {
        // Find the game to get bookie info for the audit event
        const game = finalSelection.find((g) => g.id === errorEntry.eventId);
        if (game?.bookie_auth_user_id) {
          try {
            await emitAuditEvent(client, {
              bookieId: game.bookie_id,
              actorUserId: game.bookie_auth_user_id,
              entityType: 'event',
              entityId: errorEntry.eventId,
              actionType: 'auto_refresh_failed',
              previousState: null,
              newState: {
                error_type: errorEntry.type,
                error_message: errorEntry.error,
                idempotency_key: idempotencyKey,
              },
            });
          } catch (auditError) {
            console.error(`Error emitting auto_refresh_failed audit event for ${errorEntry.eventId}:`, auditError);
          }
        }
      }

      // Run catch-up grading for any accepted bets on already-final events
      const catchup = await runCatchupGrading(client);

      // Auto-settle any parlays where all legs are now graded
      const parlaysAutoSettled = await autoSettleParlays(client);

      // Build response object
      const responseBody = {
        success: true,
        games_selected: finalSelection.length,
        odds_refreshed: oddsRefreshed,
        scores_refreshed: scoresRefreshed,
        events_finalized: eventsFinalized,
        bets_transitioned: betsTransitioned,
        bets_graded: betsGraded,
        bets_settled: betsSettled + catchup.catchupBetsSettled,
        parlays_auto_settled: parlaysAutoSettled,
        catchup_bets_settled: catchup.catchupBetsSettled,
        catchup_bets_voided: catchup.catchupBetsVoided,
        catchup_events_processed: catchup.catchupEventsProcessed,
        catchup_debug: catchup.debug,
        errors: allErrors,
      };

      const responseString = JSON.stringify(responseBody);

      // ========================================
      // US-007: Store idempotency key with response
      // ========================================
      // Use a system user ID for auto refresh operations (no specific user)
      await storeIdempotency(
        client,
        idempotencyKey,
        operation,
        'system', // Auto-refresh is a system operation, not tied to a specific user
        responseString
      );
      console.log(`Stored idempotency key: ${idempotencyKey}`);

      return new Response(responseString, {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
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
