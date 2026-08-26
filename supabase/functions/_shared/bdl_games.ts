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

const BDL_BASE = 'https://api.balldontlie.io/nfl/v1';

export interface BdlGame {
  id: number;
  date: string;
  home_team: { id: number };
  visitor_team: { id: number };
  status: string;
}

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
): Promise<GameResolution> {
  if (event.bdl_game_id) {
    return { ok: true, bdlGameId: event.bdl_game_id, cached: true };
  }

  const { data: teams, error: teamsError } = await client
    .from('bdl_teams')
    .select('bdl_team_id, odds_api_name')
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

  const dates = dayStrings(event.start_time).map((d) => `dates[]=${d}`).join('&');
  const res = await fetch(`${BDL_BASE}/games?${dates}&per_page=100`, {
    headers: { Authorization: apiKey },
  });
  if (!res.ok) {
    return { ok: false, reason: `balldontlie games ${res.status}` };
  }
  const games: BdlGame[] = (await res.json()).data ?? [];

  const matches = games.filter((g) =>
    wanted.has(g.home_team?.id) && wanted.has(g.visitor_team?.id)
  );
  if (matches.length === 0) return { ok: false, reason: 'no balldontlie game for these teams on these dates' };
  if (matches.length > 1) {
    // Should be impossible in the NFL, but guessing between two candidates is
    // how a box score gets attached to the wrong game.
    return { ok: false, reason: `${matches.length} candidate games; refusing to guess` };
  }

  const bdlGameId = matches[0].id;
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
