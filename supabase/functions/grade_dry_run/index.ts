import { corsHeaders } from '../_shared/cors.ts';
import { createServiceClient, getUserIdFromAuthHeader } from '../_shared/supabase.ts';
import { runGradeDryRun, type ReadClient, type StatlineLoad } from '../_shared/grade_dry_run.ts';
import { NFL_BOX_SCORE_MIN_ROWS, type Statline } from '../_shared/prop_stats.ts';

/**
 * Read-only grading report.
 *
 * POST { "bet_id": "<uuid>" } or { "ticket_id": "<uuid>" }
 * Authorization: Bearer <admin user access token>
 *
 * Returns the result, ledger payout, stat, and (for a parlay) repriced
 * decimal odds the fixed grader would produce. Does not update a bet,
 * write a ledger row, or store an idempotency key.
 *
 * Non-admins get 403. ADMIN_EMAILS is the same secret admin_query uses.
 */

const NFL_BASE = 'https://api.balldontlie.io/nfl/v1';

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

async function loadNflStatline(
  event: Record<string, unknown>,
  subjectPlayerId: number,
): Promise<StatlineLoad> {
  const league = String(event.league ?? '');
  if (league !== 'NFL') {
    return {
      statline: null,
      statsFinal: false,
      note: `${league || 'this sport'} has no stat feed wired; left pending`,
    };
  }
  if (!event.bdl_game_id) {
    return {
      statline: null,
      statsFinal: false,
      note: 'NFL event has no balldontlie game id; left pending',
    };
  }
  const apiKey = Deno.env.get('BALLDONTLIE_API_KEY');
  if (!apiKey) {
    return { statline: null, statsFinal: false, note: 'BALLDONTLIE_API_KEY is not set; left pending' };
  }

  const res = await fetch(
    `${NFL_BASE}/stats?game_ids[]=${event.bdl_game_id}&per_page=100`,
    { headers: { Authorization: apiKey } },
  );
  if (!res.ok) {
    return { statline: null, statsFinal: false, note: `box score request failed (${res.status}); left pending` };
  }
  const rows = ((await res.json()).data ?? []) as Array<{ player?: { id?: number }; team?: { id?: number } }>;
  const teams = new Set(rows.map((row) => row.team?.id).filter((id) => id != null));
  if (rows.length < NFL_BOX_SCORE_MIN_ROWS || teams.size < 2) {
    return {
      statline: null,
      statsFinal: false,
      note: `box score not final (${rows.length} statlines, ${teams.size} teams); left pending`,
    };
  }
  const row = rows.find((entry) => entry.player?.id === subjectPlayerId) ?? null;
  return { statline: row as Statline | null, statsFinal: true };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    const authHeader = req.headers.get('Authorization');
    const userId = await getUserIdFromAuthHeader(authHeader);
    if (!userId) return json({ error: 'Unauthorized' }, 401);

    const client = createServiceClient();
    const { data: caller } = await client.auth.admin.getUserById(userId);
    const callerEmail = (caller?.user?.email ?? '').trim().toLowerCase();
    const allow = (Deno.env.get('ADMIN_EMAILS') ?? '')
      .split(',')
      .map((email) => email.trim().toLowerCase())
      .filter(Boolean);

    if (allow.length === 0 || !callerEmail || !allow.includes(callerEmail)) {
      return json({ error: 'Forbidden' }, 403);
    }

    const body = req.method === 'POST' ? await req.json().catch(() => ({})) : {};
    const report = await runGradeDryRun(
      client as unknown as ReadClient,
      { bet_id: body.bet_id, ticket_id: body.ticket_id ?? body.parlay_id },
      loadNflStatline,
    );
    return json(report, 'error' in report ? 404 : 200);
  } catch (error) {
    console.error('grade_dry_run error:', error);
    return json({ error: error instanceof Error ? error.message : 'Internal error' }, 500);
  }
});
