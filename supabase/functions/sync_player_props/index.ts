import { corsHeaders } from '../_shared/cors.ts';
import { createServiceClient } from '../_shared/supabase.ts';
import { resolveBdlGame } from '../_shared/bdl_games.ts';
import { resolveSubject } from '../_shared/bdl_resolve.ts';
import { PROP_STATS } from '../_shared/prop_stats.ts';
import { POSITION_HINTS } from '../_shared/player_identity.ts';
import { sportConfig } from '../_shared/sport_config.ts';
import { recordQuota, resetQuota, getQuotaSnapshot } from '../_shared/odds_quota.ts';

/**
 * Ingest player props: prices from The Odds API, subjects resolved against
 * balldontlie before anything is written.
 *
 * Separate from sync_games deliberately. That function already runs ~80s
 * against a 150s ceiling, and a slate's first ingest needs one resolution call
 * per unseen player — a few hundred requests. Bolting that on would push a
 * working sync over the edge for a feature that can run on its own schedule.
 *
 * THE RULE: a prop we cannot grade is never offered. A market is written only
 * when the game maps to a balldontlie game AND the subject resolves to exactly
 * one player on one of its two rosters. Everything else is skipped and counted,
 * because the skip count is the monitor for identity drift.
 */

const ODDS_BASE = 'https://api.the-odds-api.com/v4/sports';

/** How close to kickoff a game earns prop ingest. Tighter than the odds
 *  window: props are the largest market type by row count and the least
 *  useful to publish days early. */
const PROP_WINDOW_MS = 2 * 24 * 60 * 60 * 1000;

interface OddsOutcome {
  name: string;
  description?: string;
  price: number;
  point?: number;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  const json = (b: unknown, s = 200) =>
    new Response(JSON.stringify(b), { status: s, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

  try {
    resetQuota();
    const oddsKey = Deno.env.get('ODDS_API_KEY');
    const bdlKey = Deno.env.get('BALLDONTLIE_API_KEY');
    if (!oddsKey || !bdlKey) return json({ error: 'ODDS_API_KEY or BALLDONTLIE_API_KEY missing' }, 500);

    const body = req.method === 'POST' ? await req.json().catch(() => ({})) : {};
    const dryRun = body.dry_run === true;
    // Sport is a request parameter defaulting to NFL, so the existing cron and
    // every prior invocation behave exactly as before.
    const cfg = sportConfig(body.sport);

    const client = createServiceClient();

    // Optional override, for previewing a slate that is further out than the
    // ingest window — "what would we publish for week 1" is a question worth
    // being able to ask, especially with dry_run.
    const windowMs = typeof body.window_days === 'number'
      ? Math.min(Math.max(body.window_days, 1), 30) * 24 * 60 * 60 * 1000
      : PROP_WINDOW_MS;
    const cutoff = new Date(Date.now() + windowMs).toISOString();

    const { data: events, error: eventsError } = await client
      .from('events')
      .select('id, external_id, home_team, away_team, start_time, status, bdl_game_id')
      .eq('league', cfg.sport)
      .neq('away_team', 'Outright')
      .eq('status', 'scheduled')
      .gt('start_time', new Date().toISOString())
      .lt('start_time', cutoff)
      .order('start_time');

    if (eventsError) return json({ error: `events: ${eventsError.message}` }, 500);

    const stats = {
      games_considered: events?.length ?? 0,
      games_ingested: 0,
      games_skipped_no_bdl_game: 0,
      markets_written: 0,
      markets_updated: 0,
      subjects_resolved: 0,
      // The monitor. A rising skip count is how identity drift announces itself.
      subjects_unresolved: 0,
      unresolved_examples: [] as string[],
      dry_run: dryRun,
      window_days: Math.round(windowMs / 86400000),
    };

    for (const event of events ?? []) {
      // No balldontlie game means no box score, which means nothing here could
      // ever be settled. Skip before spending an Odds API credit on it.
      const game = await resolveBdlGame(client, bdlKey, event, cfg.sport, cfg.bdlBase);
      if (!game.ok) {
        stats.games_skipped_no_bdl_game++;
        console.log(`skip ${event.away_team} @ ${event.home_team}: ${game.reason}`);
        continue;
      }

      const { data: teamRows } = await client
        .from('bdl_teams')
        .select('bdl_team_id')
        // Scoped by sport: bdl_team_id is unique only within a sport.
        .eq('sport', cfg.sport)
        .in('odds_api_name', [event.home_team, event.away_team]);
      const teamIds = (teamRows ?? []).map((t) => t.bdl_team_id);
      if (teamIds.length !== 2) {
        stats.games_skipped_no_bdl_game++;
        continue;
      }

      const url = `${ODDS_BASE}/${cfg.oddsKey}/events/${event.external_id}/odds/` +
        `?apiKey=${oddsKey}&regions=us&oddsFormat=american&markets=${cfg.propMarkets.join(',')}`;
      const res = await fetch(url);
      const text = await res.text();
      recordQuota(res, `props:${event.external_id}`, text.length);
      if (!res.ok) {
        if (res.status !== 422) console.error(`props ${event.external_id}: ${res.status}`);
        continue;
      }

      const bundle = JSON.parse(text);
      const book = (bundle.bookmakers ?? [])
        .find((b: { key: string }) => b.key === 'draftkings') ?? (bundle.bookmakers ?? [])[0];
      if (!book) continue;

      const rows: Record<string, unknown>[] = [];
      // Resolutions are cached in-process too: a player carries several markets
      // in one bundle and re-resolving each would multiply the API calls.
      const resolved = new Map<string, number | null>();

      for (const market of book.markets ?? []) {
        const statKey = cfg.marketToStat[market.key];
        if (!statKey) continue;
        // A settleable sport must map to a grading function, or the market is
        // ungradeable and has no business being written. An unsettleable sport
        // has no such functions by definition — those markets are written with
        // bettable = false rather than withheld, so the board can show them
        // while nobody can wager into something we cannot grade.
        if (cfg.settleable && !PROP_STATS[statKey]) continue;

        // Group Over/Under by (player, line): that pair is one two-sided row,
        // exactly how team totals are stored.
        const pairs = new Map<string, { subject: string; point: number; over?: OddsOutcome; under?: OddsOutcome }>();
        for (const o of (market.outcomes ?? []) as OddsOutcome[]) {
          const subject = o.description;
          if (!subject) continue;
          const point = o.point ?? 0.5;   // anytime TD has no point; Yes is "over 0.5"
          const key = `${subject}|${point}`;
          const entry = pairs.get(key) ?? { subject, point };
          const side = o.name.toLowerCase();
          if (side === 'over' || side === 'yes') entry.over = o;
          else if (side === 'under' || side === 'no') entry.under = o;
          pairs.set(key, entry);
        }

        for (const entry of pairs.values()) {
          if (!entry.over || !entry.under) continue;   // one-sided: nothing to price against

          if (!resolved.has(entry.subject)) {
            const r = await resolveSubject(
              client, bdlKey, entry.subject, teamIds, POSITION_HINTS[statKey],
              cfg.sport, cfg.bdlBase,
            );
            resolved.set(entry.subject, r.ok ? r.player.bdl_player_id : null);
            if (r.ok) stats.subjects_resolved++;
            else {
              stats.subjects_unresolved++;
              if (stats.unresolved_examples.length < 10) {
                stats.unresolved_examples.push(`${entry.subject}: ${r.reason}`);
              }
            }
          }
          const playerId = resolved.get(entry.subject);
          // THE RULE. Migration 039's CHECK would reject this anyway; refusing
          // here means the reason is logged rather than surfacing as a
          // constraint violation with no context.
          if (playerId == null) continue;

          const label = entry.point === 0.5 && market.key === 'player_anytime_td'
            ? `${entry.subject} Anytime TD`
            : `${entry.subject} Over ${entry.point}`;
          rows.push({
            event_id: event.id,
            bookie_id: null,
            type: 'player_prop',
            side_a: market.key === 'player_anytime_td' ? `${label} Yes` : label,
            side_b: market.key === 'player_anytime_td'
              ? `${label} No`
              : `${entry.subject} Under ${entry.point}`,
            odds_a: entry.over.price,
            odds_b: entry.under.price,
            subject_player_id: playerId,
            subject_name: entry.subject,
            subject_sport: cfg.sport,
            stat_key: statKey,
            bettable: cfg.settleable,
          });
        }
      }

      if (rows.length && !dryRun) {
        // Insert-or-update against what is already stored, rather than a plain
        // insert. This function re-runs as prices move, and inserting blindly
        // would duplicate every prop on every run. Matched in application code
        // on (stat_key, subject, side) the same way sync_games matches its
        // markets — deleting and re-inserting would churn market ids that
        // placed bets already reference.
        const { data: existing } = await client
          .from('markets')
          .select('id, stat_key, subject_player_id, side_a')
          .eq('event_id', event.id)
          .eq('type', 'player_prop');

        const keyOf = (r: { stat_key?: unknown; subject_player_id?: unknown; side_a?: unknown }) =>
          `${r.stat_key}|${r.subject_player_id}|${r.side_a}`;
        const existingByKey = new Map((existing ?? []).map((m) => [keyOf(m), m.id]));

        const toInsert: Record<string, unknown>[] = [];
        const toUpdate: Record<string, unknown>[] = [];
        for (const row of rows) {
          const id = existingByKey.get(keyOf(row));
          if (id) toUpdate.push({ ...row, id });
          else toInsert.push(row);
        }

        for (let i = 0; i < toInsert.length; i += 200) {
          const chunk = toInsert.slice(i, i + 200);
          const { error } = await client.from('markets').insert(chunk);
          if (error) console.error(`insert props ${event.id}: ${error.message}`);
          else stats.markets_written += chunk.length;
        }
        for (let i = 0; i < toUpdate.length; i += 200) {
          const chunk = toUpdate.slice(i, i + 200);
          const { error } = await client.from('markets').upsert(chunk, { onConflict: 'id' });
          if (error) console.error(`update props ${event.id}: ${error.message}`);
          else stats.markets_updated += chunk.length;
        }
      } else {
        stats.markets_written += rows.length;
      }
      stats.games_ingested++;
    }

    return json({ success: true, ...stats, quota: getQuotaSnapshot() });
  } catch (error) {
    console.error('sync_player_props error:', error);
    return json({ error: error instanceof Error ? error.message : 'Internal error' }, 500);
  }
});
