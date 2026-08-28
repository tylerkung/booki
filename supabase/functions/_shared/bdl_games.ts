import { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';

/**
 * Resolve one of our events to a balldontlie game.
 *
 * Needed twice — once at prop ingest to decide whether a game's props can be
 * offered at all, and again at settlement to fetch its box score — so the
 * result is cached on the event row rather than matched by name each time.
 * Matching repeatedly is both slower and two places to get it wrong.
 *
 * Matched on DATE plus BOTH team ids. Not on team names: those are already
 * mapped through bdl_teams, and re-deriving a name match here would put a
 * second, divergent copy of that mapping in the codebase.
 *
 * Kickoff can cross midnight UTC — a Sunday-night game starts Monday in UTC and
 * the two providers do not necessarily agree which calendar day that is — so a
 * one-day window either side is searched rather than an exact date. Both teams
 * must still match, which is what keeps the window from being ambiguous: two
 * teams play each other at most once in any three-day span.
 */

/** Default kept so NFL callers are unchanged; MLB passes its own. */
import { bdlFetch } from './bdl_fetch.ts';

const BDL_BASE = 'https://api.balldontlie.io/nfl/v1';

export interface BdlGame {
  id: number;
  date: string;
  home_team: { id: number };
  /** NFL and NBA call the road side visitor_team; MLB calls it away_team.
   *  Reading only the first silently matches nothing for MLB, because the
   *  field is simply undefined and the filter quietly excludes every game. */
  visitor_team?: { id: number };
  away_team?: { id: number };
  status: string;
}

/** The road team, whichever name this sport's payload uses. */
const roadTeamId = (g: BdlGame): number | undefined =>
  g.visitor_team?.id ?? g.away_team?.id;

export type GameResolution =
  | { ok: true; bdlGameId: number; cached: boolean }
  | { ok: false; reason: string };

function dayStrings(iso: string): string[] {
  const d = new Date(iso);
  return [-1, 0, 1].map((offset) => {
    const x = new Date(d.getTime() + offset * 86_400_000);
    return x.toISOString().slice(0, 10);
  });
}

/**
 * One games fetch per date-set per run.
 *
 * Every event on a slate looks at the same two or three dates, so resolving
 * nine games made nine identical requests and hit balldontlie's rate limit on
 * the fourth — which surfaced as "no balldontlie game for these teams", a
 * mapping problem that was really a pacing one. The cache lives for the
 * lifetime of the isolate, which is one run.
 */
const gamesCache = new Map<string, BdlGame[]>();

async function gamesForDays(bdlBase: string, apiKey: string, days: string[]): Promise<BdlGame[]> {
  const key = `${bdlBase}|${days.join(',')}`;
  const hit = gamesCache.get(key);
  if (hit) return hit;

  const qs = days.map((d) => `dates[]=${d}`).join('&');
  const res = await bdlFetch(`${bdlBase}/games?${qs}&per_page=100`, apiKey);
  if (!res.ok) {
    // Named separately from a genuine miss: a 429 is transient and a missing
    // game is not, and a skip count that conflates them looks like a mapping
    // problem when it is a pacing one.
    throw new Error(res.status === 429 ? 'balldontlie rate limited' : `balldontlie games ${res.status}`);
  }
  const games: BdlGame[] = (await res.json()).data ?? [];
  gamesCache.set(key, games);
  return games;
}

export async function resolveBdlGame(
  client: SupabaseClient,
  apiKey: string,
  event: {
    id: string;
    start_time: string;
    home_team: string;
    away_team: string;
    bdl_game_id?: number | null;
  },
  sport = 'NFL',
  bdlBase = BDL_BASE,
): Promise<GameResolution> {
  if (event.bdl_game_id) {
    return { ok: true, bdlGameId: event.bdl_game_id, cached: true };
  }

  const { data: teams, error: teamsError } = await client
    .from('bdl_teams')
    .select('bdl_team_id, odds_api_name')
    // Scoped by sport: bdl_team_id is only unique WITHIN a sport — 29 of the 30
    // MLB ids are also NFL ids — so an unscoped read can hand back a team from
    // the wrong league.
    .eq('sport', sport)
    .in('odds_api_name', [event.home_team, event.away_team]);

  if (teamsError) return { ok: false, reason: `bdl_teams lookup failed: ${teamsError.message}` };
  if (!teams || teams.length !== 2) {
    // One side unmapped means every prop for this game is unofferable. Saying
    // which side is unmapped is the difference between a five-minute fix and an
    // afternoon.
    const found = (teams ?? []).map((t) => t.odds_api_name);
    const missing = [event.home_team, event.away_team].filter((n) => !found.includes(n));
    return { ok: false, reason: `unmapped team(s): ${missing.join(', ')}` };
  }
  const wanted = new Set(teams.map((t) => t.bdl_team_id));

  const days = dayStrings(event.start_time);
  let games: BdlGame[];
  try {
    games = await gamesForDays(bdlBase, apiKey, days);
  } catch (e) {
    return { ok: false, reason: String((e as Error).message) };
  }

  const matches = games.filter((g) => {
    const road = roadTeamId(g);
    return wanted.has(g.home_team?.id) && road !== undefined && wanted.has(road);
  });
  if (matches.length === 0) return { ok: false, reason: 'no balldontlie game for these teams on these dates' };

  // More than one candidate is NORMAL in baseball and impossible in the NFL.
  // Two teams play a three-game series on consecutive days, and the ±1 day
  // search — which exists because a 7pm ET game is the next day in UTC — sees
  // the whole series. Date alone cannot separate them, so separate them by
  // first pitch: the right game is the one nearest the event's start time.
  let chosen = matches[0];
  if (matches.length > 1) {
    const target = new Date(event.start_time).getTime();
    const withGap = matches
      .map((g) => ({ g, gap: Math.abs(new Date(g.date).getTime() - target) }))
      .sort((a, b) => a.gap - b.gap);
    // A true doubleheader is two games the same day, hours apart, and the price
    // feed lists them as separate events with distinct start times — so a near
    // tie means the times are not telling them apart and guessing would attach
    // a box score to the wrong game.
    if (withGap[1].gap - withGap[0].gap < 60 * 60 * 1000) {
      return { ok: false, reason: `${matches.length} candidate games within an hour of each other; refusing to guess` };
    }
    if (withGap[0].gap > 12 * 60 * 60 * 1000) {
      return { ok: false, reason: `nearest candidate is ${Math.round(withGap[0].gap / 3.6e6)}h from the listed start; refusing to guess` };
    }
    chosen = withGap[0].g;
  }

  const bdlGameId = chosen.id;
  const { error: updateError } = await client
    .from('events')
    .update({ bdl_game_id: bdlGameId })
    .eq('id', event.id);
  if (updateError) {
    // The match itself is still good; only the cache write failed.
    console.error(`cache bdl_game_id for ${event.id}: ${updateError.message}`);
  }

  return { ok: true, bdlGameId, cached: false };
}
