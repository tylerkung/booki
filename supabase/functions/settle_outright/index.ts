import { corsHeaders } from '../_shared/cors.ts';
import { createServiceClient, getUserIdFromAuthHeader } from '../_shared/supabase.ts';
import { selectAllIn, selectAllPaged } from '../_shared/pagination.ts';
import { futuresAwaitingResult } from '../_shared/outright.ts';

/**
 * Record one futures winner for every book.
 *
 * Authorization: Bearer <admin user access token>
 * ADMIN_EMAILS is the same secret admin_query uses. There is no admin role
 * in the database. A caller who is not on that list gets 404.
 *
 * POST { "action": "list" }
 *   Futures that still have an open pick and no outright_results row.
 *
 * POST { "action": "settle", "event_id": "<uuid>", "winning_selection": "Team" }
 * POST { "action": "settle", "event_id": "<uuid>", "void": true }
 *
 * Settlement is settle_outright_tx. A repeat with the same winner pays nothing
 * again. This function does not settle on list, and it does not choose a winner.
 */

interface SettleBody {
  action?: string;
  event_id?: string;
  winning_selection?: string;
  void?: boolean;
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
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
      return json({ error: 'Not found' }, 404);
    }

    const body: SettleBody = req.method === 'POST' ? await req.json().catch(() => ({})) : {};
    const action = body.action ?? 'list';

    if (action === 'list') {
      return json({ events: await listAwaiting(client) });
    }

    if (action !== 'settle') {
      return json({ error: 'Unknown action' }, 400);
    }

    const eventId = (body.event_id ?? '').trim();
    if (!UUID_RE.test(eventId)) {
      return json({ error: 'event_id must be a UUID' }, 400);
    }

    const voidEvent = body.void === true;
    const winner = (body.winning_selection ?? '').trim();
    if (!voidEvent && !winner) {
      return json({ error: 'A winning selection is required' }, 400);
    }
    if (voidEvent && winner) {
      return json({ error: 'A voided future has no winner' }, 400);
    }

    const { data, error } = await client.rpc('settle_outright_tx', {
      p_event_id: eventId,
      p_winning_selection: voidEvent ? null : winner,
      p_void: voidEvent,
      p_actor_user_id: userId,
    });

    if (error) {
      console.error('settle_outright_tx error:', error);
      return json({ error: error.message }, 500);
    }

    const result = data as { success?: boolean; error?: string } | null;
    if (!result?.success) {
      const status = result?.error === 'result_already_recorded' ? 409 : 400;
      return json(result ?? { error: 'settle_outright_tx failed' }, status);
    }

    return json(result);
  } catch (error) {
    console.error('settle_outright error:', error);
    return json({ error: error instanceof Error ? error.message : 'Internal error' }, 500);
  }
});

async function listAwaiting(client: ReturnType<typeof createServiceClient>) {
  const openStatuses = ['pending', 'accepted', 'graded', 'readyToGrade'];
  const { data: bets, error: betsError } = await selectAllPaged<{
    event_id: string | null;
    side: string | null;
    stake: number | null;
    market: string | null;
  }>(() =>
    client
      .from('bets')
      .select('event_id, side, stake, market')
      .in('status', openStatuses)
      .in('market', ['outright', 'futures'])
  );
  if (betsError) throw new Error(betsError.message);
  if (bets.length === 0) return [];

  const eventIds = [...new Set(bets.map((bet) => (bet.event_id ?? '').toLowerCase()).filter(Boolean))];
  const [eventsResult, marketsResult, resultsResult] = await Promise.all([
    selectAllIn(client, 'events', 'id, away_team, home_team, name, start_time, status, sport, league', 'id', eventIds),
    selectAllIn(client, 'markets', 'event_id, type, side_a', 'event_id', eventIds),
    selectAllIn(client, 'outright_results', 'event_id', 'event_id', eventIds),
  ]);
  if (eventsResult.error) throw new Error(eventsResult.error.message);
  if (marketsResult.error) throw new Error(marketsResult.error.message);
  if (resultsResult.error) throw new Error(resultsResult.error.message);

  return futuresAwaitingResult({
    bets,
    events: eventsResult.data as Parameters<typeof futuresAwaitingResult>[0]['events'],
    markets: marketsResult.data as Parameters<typeof futuresAwaitingResult>[0]['markets'],
    results: resultsResult.data as Array<{ event_id: string }>,
  });
}
