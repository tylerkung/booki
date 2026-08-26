import { corsHeaders } from '../_shared/cors.ts';
import { createServiceClient } from '../_shared/supabase.ts';
import { gradeProp, type Statline } from '../_shared/prop_stats.ts';
import { settlementAmount, SETTLEMENT_DESCRIPTION, type GradeResult } from '../_shared/settlement_math.ts';

/**
 * Settle player props from a balldontlie box score.
 *
 * Three rules shape this, and each exists because the obvious alternative
 * settles bets wrongly:
 *
 *   1. WAIT before grading. A statline is not final when the whistle blows;
 *      grading immediately settles against a box score still being written.
 *
 *   2. ALL OR NOTHING per game. A partial box score produces confident wrong
 *      answers rather than obviously broken ones — an Over on a receiver whose
 *      line has not landed yet reads exactly like a loss.
 *
 *   3. AN ABSENT STATLINE IS A VOID, A ZERO ROW IS NOT. balldontlie emits a row
 *      only for players with recorded involvement, so absence means the player
 *      did not play. A row of zeroes means he played and did nothing, and an
 *      Over on him LOSES. Collapsing the two would refund stakes on bets the
 *      book won.
 */

const BDL_BASE = 'https://api.balldontlie.io/nfl/v1';

/** How long after a game is marked final before the first grading attempt. */
const SETTLING_DELAY_MS = 30 * 60 * 1000;

/** After this long, stop retrying and hand the game to a human. */
const GIVE_UP_AFTER_MS = 24 * 60 * 60 * 1000;

/** A box score with fewer statlines than this is treated as still arriving. */
const MIN_STATLINES = 20;

interface BdlStatRow {
  player: { id: number };
  team?: { id: number };
  [k: string]: unknown;
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
    // Bypasses the settling delay only. Never bypasses completeness.
    const force = body.force === true;

    const client = createServiceClient();
    const now = Date.now();

    // Games finished recently enough to still be worth grading.
    const { data: events, error: eventsError } = await client
      .from('events')
      .select('id, home_team, away_team, start_time, status, bdl_game_id, updated_at')
      .eq('league', 'NFL')
      .eq('status', 'final')
      .not('bdl_game_id', 'is', null)
      .gt('updated_at', new Date(now - GIVE_UP_AFTER_MS).toISOString());

    if (eventsError) return json({ error: `events: ${eventsError.message}` }, 500);

    const stats = {
      games_considered: events?.length ?? 0,
      games_waiting_settle: 0,
      games_incomplete: 0,
      games_graded: 0,
      games_gave_up: 0,
      bets_settled: 0,
      bets_void: 0,
      dry_run: dryRun,
      notes: [] as string[],
    };

    for (const event of events ?? []) {
      const { data: runRow } = await client
        .from('prop_grading_runs')
        .select('*')
        .eq('event_id', event.id)
        .maybeSingle();

      if (runRow?.status === 'graded') continue;

      // Only bets on THIS event's prop markets, still open.
      const { data: bets } = await client
        .from('bets')
        .select('id, player_id, bookie_id, market, side, odds, stake, status, market_id')
        .eq('event_id', event.id)
        .in('status', ['accepted', 'pending']);

      // One read for the event's prop markets, then join in memory. A query
      // per bet would be N round trips on a game that could carry hundreds.
      const { data: propMarkets } = await client
        .from('markets')
        .select('id, stat_key, subject_player_id')
        .eq('event_id', event.id)
        .eq('type', 'player_prop');
      const marketById = new Map((propMarkets ?? []).map((m) => [m.id, m]));

      const propBets = [];
      for (const b of bets ?? []) {
        // A bet placed before migration 042 has no market_id. It cannot be
        // traced to a stat, so it is left for manual grading rather than
        // guessed at from its side label — "Jalen Hurts Over 1.5" is a valid
        // label for two different stats.
        if (!b.market_id) continue;
        const mkt = marketById.get(b.market_id);
        if (mkt?.stat_key && mkt.subject_player_id) {
          propBets.push({ ...b, stat_key: mkt.stat_key, subject_player_id: mkt.subject_player_id });
        }
      }
      if (propBets.length === 0) continue;

      const finalAt = new Date(event.updated_at).getTime();
      if (!force && now - finalAt < SETTLING_DELAY_MS) {
        stats.games_waiting_settle++;
        continue;
      }

      // Fetch the box score.
      const res = await fetch(
        `${BDL_BASE}/stats?game_ids[]=${event.bdl_game_id}&per_page=100`,
        { headers: { Authorization: bdlKey } },
      );
      const rows: BdlStatRow[] = res.ok ? ((await res.json()).data ?? []) : [];

      // Completeness gate. Both teams must be represented and the row count has
      // to look like a real NFL box score; a half-written one grades nothing.
      const teamsSeen = new Set(rows.map((r) => r.team?.id).filter(Boolean));
      const complete = res.ok && rows.length >= MIN_STATLINES && teamsSeen.size >= 2;

      if (!complete) {
        const attempts = (runRow?.attempts ?? 0) + 1;
        const firstAttempt = runRow?.first_attempt_at ?? new Date(now).toISOString();
        const gaveUp = now - new Date(firstAttempt).getTime() > GIVE_UP_AFTER_MS;
        if (gaveUp) stats.games_gave_up++; else stats.games_incomplete++;
        stats.notes.push(
          `${event.away_team} @ ${event.home_team}: ${rows.length} statlines, ${teamsSeen.size} teams` +
          (gaveUp ? ' — GIVING UP, needs manual grading' : ' — will retry'),
        );
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
      for (const bet of propBets) {
        // null here means NO ROW, which is the only signal of a DNP. A zero row
        // is passed through and grades normally.
        const statline = byPlayer.get(bet.subject_player_id) ?? null;
        const outcome = gradeProp(bet.stat_key, bet.side, statline);

        if (outcome.result === 'pending') {
          stats.notes.push(`bet ${bet.id}: ${outcome.detail}`);
          continue;
        }
        if (dryRun) {
          settled++;
          if (outcome.result === 'void') voided++;
          continue;
        }

        const amount = settlementAmount(outcome.result as GradeResult, Number(bet.stake), Number(bet.odds));

        const { error: betError } = await client
          .from('bets')
          .update({
            status: 'settled',
            grade_result: outcome.result,
            updated_at: new Date().toISOString(),
          })
          .eq('id', bet.id)
          .in('status', ['accepted', 'pending']);
        if (betError) { stats.notes.push(`bet ${bet.id}: ${betError.message}`); continue; }

        // Guard against a double ledger entry if a run is retried after a
        // partial failure — the same guard auto_refresh_games uses.
        const { data: existing } = await client
          .from('ledger_entries')
          .select('id').eq('bet_id', bet.id).eq('type', 'settlement').limit(1);

        if (!existing?.length) {
          const { error: ledgerError } = await client.from('ledger_entries').insert({
            bookie_id: bet.bookie_id,
            player_id: bet.player_id,
            bet_id: bet.id,
            amount,
            type: 'settlement',
            description: `${SETTLEMENT_DESCRIPTION[outcome.result as GradeResult]} — ${outcome.detail}`,
          });
          if (ledgerError) { stats.notes.push(`ledger ${bet.id}: ${ledgerError.message}`); continue; }
        }
        settled++;
        if (outcome.result === 'void') voided++;
      }

      stats.bets_settled += settled;
      stats.bets_void += voided;
      stats.games_graded++;

      if (!dryRun) {
        await client.from('prop_grading_runs').upsert({
          event_id: event.id,
          bdl_game_id: event.bdl_game_id,
          status: 'graded',
          attempts: (runRow?.attempts ?? 0) + 1,
          first_attempt_at: runRow?.first_attempt_at ?? new Date(now).toISOString(),
          // Snapshot what we graded against, so a later stat correction is
          // DETECTABLE by comparison rather than silent. US-006 reads this.
          statline_snapshot: rows,
          graded_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        }, { onConflict: 'event_id' });
      }
    }

    return json({ success: true, ...stats });
  } catch (error) {
    console.error('grade_player_props error:', error);
    return json({ error: error instanceof Error ? error.message : 'Internal error' }, 500);
  }
});
