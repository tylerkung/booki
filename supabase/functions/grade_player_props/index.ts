import { corsHeaders } from '../_shared/cors.ts';
import { createServiceClient } from '../_shared/supabase.ts';
import {
  gradeProp,
  NFL_BOX_SCORE_MIN_ROWS,
  resolvePropTarget,
  type Statline,
} from '../_shared/prop_stats.ts';
import { settleReadyParlays } from '../_shared/parlay_apply.ts';

/**
 * Settle player props from a balldontlie box score.
 *
 * This is the only prop grader. refresh_live_scores and the catch-up job
 * must not grade props: they run first, and a push settlement takes the bet
 * out of the open set this function reads.
 *
 * The stat source is the box score fetched here. The database does not store
 * player stats. The bet's own stat_key / subject_player_id / side snapshot
 * is what we grade from, so a pruned market row does not matter. Bets placed
 * before that snapshot existed fall back to the market row, and if that row
 * is already gone they are left pending — this function does not guess, and
 * it does not rewrite bets that are already settled.
 *
 * Singles go through settle_bet_tx (migration 015), which is the one ledger
 * write. Parlay legs are graded onto the leg and paid once by
 * settleReadyParlays, not per leg.
 *
 * NFL only. Any other sport is logged and left pending. NBA's field map
 * exists on the pure grader (the spike verified it) but this job does not
 * fetch NBA. MLB's stat endpoint returns 401 on the current plan.
 */

const BDL_BASE = 'https://api.balldontlie.io/nfl/v1';

/** How long after a game is marked final before the first grading attempt. */
const SETTLING_DELAY_MS = 30 * 60 * 1000;

/** After this long, stop retrying and hand the game to a human. */
const GIVE_UP_AFTER_MS = 24 * 60 * 60 * 1000;

interface BdlStatRow {
  player: { id: number };
  team?: { id: number };
  [k: string]: unknown;
}

interface OpenBet {
  id: string;
  player_id: string;
  bookie_id: string;
  market: string | null;
  side: string | null;
  odds: number | string;
  stake: number | string;
  status: string;
  grade_result: string | null;
  market_id: string | null;
  is_parlay: boolean | null;
  ticket_id: string | null;
  stat_key: string | null;
  subject_player_id: number | null;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  const json = (b: unknown, s = 200) =>
    new Response(JSON.stringify(b), { status: s, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

  try {
    const bdlKey = Deno.env.get('BALLDONTLIE_API_KEY');
    if (!bdlKey) return json({ error: 'BALLDONTLIE_API_KEY missing' }, 500);

    const body = req.method === 'POST' ? await req.json().catch(() => ({})) : {};
    const dryRun = body.dry_run === true;
    // Bypasses the settling delay only. Never bypasses completeness, and
    // never writes when dry_run is set. The admin report is grade_dry_run;
    // this flag is the existing operator switch and it must not settle.
    const force = body.force === true;

    const client = createServiceClient();
    const now = Date.now();

    const stats = {
      games_considered: 0,
      games_waiting_settle: 0,
      games_incomplete: 0,
      games_graded: 0,
      games_gave_up: 0,
      bets_settled: 0,
      bets_void: 0,
      bets_left_pending: 0,
      parlays_settled: 0,
      dry_run: dryRun,
      notes: [] as string[],
    };

    // Sports this job cannot grade. Leave the bets open and say so. The
    // score graders used to push these; they no longer do.
    const { data: openProps } = await client
      .from('bets')
      .select('id, event_id')
      .eq('market', 'player_prop')
      .in('status', ['accepted', 'pending'])
      .limit(500);
    const openEventIds = [...new Set((openProps ?? []).map((bet) => bet.event_id).filter(Boolean))];
    if (openEventIds.length > 0) {
      const { data: openEvents } = await client
        .from('events')
        .select('id, league, status')
        .in('id', openEventIds.slice(0, 200));
      const skipped = new Set<string>();
      for (const event of openEvents ?? []) {
        if (event.status !== 'final' || event.league === 'NFL' || skipped.has(event.id)) continue;
        skipped.add(event.id);
        const note = `${event.league} event ${event.id}: no stat feed, props left pending`;
        stats.notes.push(note);
        console.log(note);
      }
    }

    const { data: events, error: eventsError } = await client
      .from('events')
      .select('id, home_team, away_team, start_time, status, bdl_game_id, updated_at, league')
      .eq('league', 'NFL')
      .eq('status', 'final')
      .not('bdl_game_id', 'is', null)
      .gt('updated_at', new Date(now - GIVE_UP_AFTER_MS).toISOString());

    if (eventsError) return json({ error: `events: ${eventsError.message}` }, 500);
    stats.games_considered = events?.length ?? 0;

    for (const event of events ?? []) {
      const { data: runRow } = await client
        .from('prop_grading_runs')
        .select('*')
        .eq('event_id', event.id)
        .maybeSingle();

      if (runRow?.status === 'graded') continue;

      const { data: bets, error: betsError } = await client
        .from('bets')
        .select('id, player_id, bookie_id, market, side, odds, stake, status, grade_result, market_id, is_parlay, ticket_id, stat_key, subject_player_id')
        .eq('event_id', event.id)
        .in('status', ['accepted', 'pending', 'graded']);
      if (betsError) {
        const note = `event ${event.id}: could not read bets (${betsError.message}). Left pending. Migration 061 must be applied before this function can read prop snapshots.`;
        stats.notes.push(note);
        console.error(note);
        continue;
      }

      const { data: propMarkets } = await client
        .from('markets')
        .select('id, stat_key, subject_player_id')
        .eq('event_id', event.id)
        .eq('type', 'player_prop');
      const marketById = new Map((propMarkets ?? []).map((m) => [m.id, m]));

      const propBets: OpenBet[] = [];
      for (const bet of (bets ?? []) as OpenBet[]) {
        const isProp = bet.market === 'player_prop' || !!bet.stat_key;
        if (!isProp) continue;
        // Already graded parlay legs belong to the parlay settler.
        if (bet.is_parlay && bet.status === 'graded') continue;
        propBets.push(bet);
      }
      if (propBets.length === 0) continue;

      const bookieIds = [...new Set(propBets.map((bet) => bet.bookie_id))];
      const { data: bookies } = await client
        .from('bookies')
        .select('id, manual_bet_grading, auth_user_id')
        .in('id', bookieIds);
      const manual = new Set((bookies ?? []).filter((b) => b.manual_bet_grading).map((b) => b.id));
      const actorByBookie = new Map((bookies ?? []).map((b) => [b.id, b.auth_user_id as string | null]));

      const finalAt = new Date(event.updated_at).getTime();
      if (!force && now - finalAt < SETTLING_DELAY_MS) {
        stats.games_waiting_settle++;
        continue;
      }

      const res = await fetch(
        `${BDL_BASE}/stats?game_ids[]=${event.bdl_game_id}&per_page=100`,
        { headers: { Authorization: bdlKey } },
      );
      const rows: BdlStatRow[] = res.ok ? ((await res.json()).data ?? []) : [];
      const teamsSeen = new Set(rows.map((r) => r.team?.id).filter(Boolean));
      const complete = res.ok && rows.length >= NFL_BOX_SCORE_MIN_ROWS && teamsSeen.size >= 2;

      if (!complete) {
        const attempts = (runRow?.attempts ?? 0) + 1;
        const firstAttempt = runRow?.first_attempt_at ?? new Date(now).toISOString();
        const gaveUp = now - new Date(firstAttempt).getTime() > GIVE_UP_AFTER_MS;
        if (gaveUp) stats.games_gave_up++; else stats.games_incomplete++;
        const note = `${event.away_team} @ ${event.home_team}: ${rows.length} statlines, ${teamsSeen.size} teams` +
          (gaveUp ? ' — GIVING UP, needs manual grading; bets left pending' : ' — stats not final, will retry');
        stats.notes.push(note);
        console.log(note);
        if (!dryRun) {
          await client.from('prop_grading_runs').upsert({
            event_id: event.id,
            bdl_game_id: event.bdl_game_id,
            status: gaveUp ? 'needs_review' : 'partial',
            attempts,
            first_attempt_at: firstAttempt,
            last_error: `incomplete box score: ${rows.length} rows, ${teamsSeen.size} teams`,
            updated_at: new Date().toISOString(),
          }, { onConflict: 'event_id' });
        }
        continue;
      }

      const byPlayer = new Map<number, Statline>(
        rows.map((r) => [r.player.id, r as unknown as Statline]),
      );

      let settled = 0;
      let voided = 0;
      let blocked = false;

      for (const bet of propBets) {
        if (manual.has(bet.bookie_id)) {
          const note = `bet ${bet.id}: organizer grades manually; left pending`;
          stats.notes.push(note);
          console.log(note);
          blocked = true;
          stats.bets_left_pending++;
          continue;
        }

        // A previous attempt graded the single and the settlement RPC failed.
        // Do not grade it again; just finish the settlement.
        if (!bet.is_parlay && bet.status === 'graded' && bet.grade_result) {
          if (dryRun) { settled++; continue; }
          const posted = await settleSingle(client, bet, actorByBookie.get(bet.bookie_id) ?? null, stats.notes);
          if (posted) settled++;
          continue;
        }

        const market = bet.market_id ? marketById.get(bet.market_id) ?? null : null;
        const target = resolvePropTarget(bet, market);
        if ('error' in target) {
          const note = `bet ${bet.id}: ${target.error}`;
          stats.notes.push(note);
          console.log(note);
          blocked = true;
          stats.bets_left_pending++;
          continue;
        }

        const statline = byPlayer.get(target.subjectPlayerId) ?? null;
        const outcome = gradeProp(target.statKey, target.side, statline, { statsFinal: true });

        if (outcome.result === 'pending') {
          const note = `bet ${bet.id}: ${outcome.detail}`;
          stats.notes.push(note);
          console.log(note);
          blocked = true;
          stats.bets_left_pending++;
          continue;
        }

        if (outcome.result === 'void') {
          console.log(`VOID prop bet ${bet.id}: ${outcome.detail}`);
          stats.notes.push(`VOID bet ${bet.id}: ${outcome.detail}`);
        }

        if (dryRun) {
          settled++;
          if (outcome.result === 'void') voided++;
          continue;
        }

        if (bet.is_parlay) {
          const status = outcome.result === 'void' ? 'void' : 'graded';
          const { error: gradeError } = await client
            .from('bets')
            .update({
              status,
              grade_result: outcome.result,
              updated_at: new Date().toISOString(),
            })
            .eq('id', bet.id)
            .in('status', ['accepted', 'pending']);
          if (gradeError) {
            stats.notes.push(`bet ${bet.id}: ${gradeError.message}`);
            blocked = true;
            continue;
          }
          settled++;
          if (outcome.result === 'void') voided++;
          continue;
        }

        const { error: gradeError } = await client
          .from('bets')
          .update({
            status: 'graded',
            grade_result: outcome.result,
            updated_at: new Date().toISOString(),
          })
          .eq('id', bet.id)
          .in('status', ['accepted', 'pending']);
        if (gradeError) {
          stats.notes.push(`bet ${bet.id}: ${gradeError.message}`);
          blocked = true;
          continue;
        }

        const posted = await settleSingle(client, bet, actorByBookie.get(bet.bookie_id) ?? null, stats.notes);
        if (!posted) {
          blocked = true;
          continue;
        }
        settled++;
        if (outcome.result === 'void') voided++;
      }

      stats.bets_settled += settled;
      stats.bets_void += voided;

      if (blocked) {
        if (!dryRun) {
          await client.from('prop_grading_runs').upsert({
            event_id: event.id,
            bdl_game_id: event.bdl_game_id,
            status: 'partial',
            attempts: (runRow?.attempts ?? 0) + 1,
            first_attempt_at: runRow?.first_attempt_at ?? new Date(now).toISOString(),
            last_error: 'one or more props still pending',
            updated_at: new Date().toISOString(),
          }, { onConflict: 'event_id' });
        }
        continue;
      }

      stats.games_graded++;
      if (!dryRun) {
        await client.from('prop_grading_runs').upsert({
          event_id: event.id,
          bdl_game_id: event.bdl_game_id,
          status: 'graded',
          attempts: (runRow?.attempts ?? 0) + 1,
          first_attempt_at: runRow?.first_attempt_at ?? new Date(now).toISOString(),
          statline_snapshot: rows,
          graded_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        }, { onConflict: 'event_id' });
      }
    }

    if (!dryRun) {
      stats.parlays_settled = await settleReadyParlays(client);
    }

    return json({ success: true, ...stats });
  } catch (error) {
    console.error('grade_player_props error:', error);
    return json({ error: error instanceof Error ? error.message : 'Internal error' }, 500);
  }
});

async function settleSingle(
  client: ReturnType<typeof createServiceClient>,
  bet: OpenBet,
  actorUserId: string | null,
  notes: string[],
): Promise<boolean> {
  const { data: rpcResult, error: rpcError } = await client.rpc('settle_bet_tx', {
    p_bet_id: bet.id,
    p_actor_user_id: actorUserId,
    p_idempotency_key: `settle_prop_${bet.id}_v1`,
    p_mode: 'auto',
  });
  if (rpcError) {
    notes.push(`bet ${bet.id}: settle_bet_tx ${rpcError.message}`);
    console.error(`settle_bet_tx failed for ${bet.id}:`, rpcError);
    return false;
  }
  if (rpcResult && rpcResult.success === false) {
    if (rpcResult.error === 'Bet has already been settled') return true;
    notes.push(`bet ${bet.id}: settle_bet_tx ${rpcResult.error}`);
    console.error(`settle_bet_tx refused ${bet.id}:`, rpcResult.error);
    return false;
  }
  return true;
}
