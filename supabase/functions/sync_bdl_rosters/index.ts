import { corsHeaders } from '../_shared/cors.ts';
import { createServiceClient } from '../_shared/supabase.ts';
import { normalizeName } from '../_shared/player_identity.ts';

/**
 * Refresh the balldontlie roster cache.
 *
 * Props resolve a name to a player against this table, so a stale cache does
 * not fail loudly — it just stops resolving newly signed players, and their
 * props quietly never appear. Weekly is enough for that not to matter; the
 * point is that it runs at all.
 *
 * Pulled per team rather than from the unfiltered /players endpoint, which
 * returns HISTORICAL players — it was still climbing past 5,000 rows when a
 * full pull was abandoned during the spike. Per team is bounded and is also
 * exactly the shape resolution needs: candidates for a game are the two
 * rosters, never the league.
 */

const BDL_BASE = 'https://api.balldontlie.io/nfl/v1';

/** ALL-STAR is 60 requests/minute. One team per second stays well inside it
 *  while keeping a 32-team refresh under a minute. */
const REQUEST_SPACING_MS = 1100;

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

interface BdlPlayerRow {
  id: number;
  first_name: string;
  last_name: string;
  position?: string | null;
  position_abbreviation?: string | null;
  team?: { id: number } | null;
}

async function fetchTeamRoster(
  apiKey: string,
  teamId: number,
): Promise<{ players: BdlPlayerRow[]; error?: string }> {
  const url = `${BDL_BASE}/players?team_ids[]=${teamId}&per_page=100`;
  for (let attempt = 0; attempt < 4; attempt++) {
    const res = await fetch(url, { headers: { Authorization: apiKey } });
    if (res.status === 429) {
      // Backing off past the window beats hammering it: a 429 storm looks
      // exactly like an outage in the logs.
      await sleep(3000 * (attempt + 1));
      continue;
    }
    if (!res.ok) {
      return { players: [], error: `${res.status} ${(await res.text()).slice(0, 120)}` };
    }
    const body = await res.json();
    return { players: body.data ?? [] };
  }
  return { players: [], error: 'rate limited after 4 attempts' };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });

  try {
    const apiKey = Deno.env.get('BALLDONTLIE_API_KEY');
    if (!apiKey) return json({ error: 'BALLDONTLIE_API_KEY is not configured' }, 500);

    const client = createServiceClient();

    const { data: teams, error: teamsError } = await client
      .from('bdl_teams')
      .select('bdl_team_id, abbreviation')
      .eq('sport', 'NFL')
      .order('abbreviation');

    if (teamsError || !teams?.length) {
      return json({ error: `bdl_teams unavailable: ${teamsError?.message ?? 'empty'}` }, 500);
    }

    const stats = { teams: teams.length, upserted: 0, failed: [] as string[] };
    const rows: Record<string, unknown>[] = [];

    for (const [i, team] of teams.entries()) {
      const { players, error } = await fetchTeamRoster(apiKey, team.bdl_team_id);
      if (error) {
        stats.failed.push(`${team.abbreviation}: ${error}`);
      } else {
        for (const p of players) {
          rows.push({
            bdl_player_id: p.id,
            first_name: p.first_name,
            last_name: p.last_name,
            // Computed HERE, by the one shared implementation, so both sides of
            // a future comparison normalise identically. Two copies of these
            // rules drift, and when they drift both still look correct.
            normalized_name: normalizeName(`${p.first_name} ${p.last_name}`),
            position: p.position_abbreviation ?? p.position ?? null,
            bdl_team_id: p.team?.id ?? team.bdl_team_id,
            sport: 'NFL',
            last_synced_at: new Date().toISOString(),
          });
        }
      }
      if (i < teams.length - 1) await sleep(REQUEST_SPACING_MS);
    }

    // Chunked: a single upsert of a few thousand rows is one oversized request
    // that can time out and leave the cache half-written.
    for (let i = 0; i < rows.length; i += 500) {
      const chunk = rows.slice(i, i + 500);
      const { error } = await client
        .from('bdl_players')
        .upsert(chunk, { onConflict: 'bdl_player_id' });
      if (error) {
        stats.failed.push(`upsert chunk ${i}: ${error.message}`);
      } else {
        stats.upserted += chunk.length;
      }
    }

    // A partial refresh is worth reporting as a failure even though rows landed:
    // silently succeeding with 3 of 32 teams is how a cache rots unnoticed.
    const ok = stats.failed.length === 0;
    return json({ success: ok, ...stats }, ok ? 200 : 207);
  } catch (error) {
    console.error('sync_bdl_rosters error:', error);
    return json({ error: error instanceof Error ? error.message : 'Internal error' }, 500);
  }
});
