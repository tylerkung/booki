import { corsHeaders } from '../_shared/cors.ts';
import { createServiceClient, getUserIdFromAuthHeader } from '../_shared/supabase.ts';
import { checkIdempotency, storeIdempotency } from '../_shared/idempotency.ts';
import { emitAuditEvent } from '../_shared/audit.ts';
import { isOutrightMarket, manualSingleSettlementKey } from '../_shared/outright.ts';

interface GradeBetRequest {
  bet_id: string;
  outcome: 'win' | 'loss' | 'push' | 'void';
  idempotency_key: string;
}

interface BetRecord {
  id: string;
  bookie_id: string;
  player_id: string;
  event_id: string;
  ticket_id: string;
  market: string;
  side: string;
  odds: number;
  stake: number;
  status: string;
  grade_result: string | null;
  is_parlay: boolean | null;
  accepted_at: string | null;
  created_at: string;
  updated_at: string;
}

const VALID_OUTCOMES = ['win', 'loss', 'push', 'void'];

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get('Authorization');
    const userId = await getUserIdFromAuthHeader(authHeader);

    if (!userId) {
      return json({ success: false, error: 'Unauthorized' }, 401);
    }

    const body: GradeBetRequest = await req.json();

    if (!body.bet_id) {
      return json({ success: false, error: 'Missing required field: bet_id' }, 400);
    }

    if (!body.outcome) {
      return json({ success: false, error: 'Missing required field: outcome' }, 400);
    }

    if (!VALID_OUTCOMES.includes(body.outcome)) {
      return json({
        success: false,
        error: `Invalid outcome. Must be one of: ${VALID_OUTCOMES.join(', ')}`,
      }, 400);
    }

    if (!body.idempotency_key) {
      return json({ success: false, error: 'Missing required field: idempotency_key' }, 400);
    }

    const client = createServiceClient();

    // Cached only after the settlement succeeds. A crash between the grade
    // write and the ledger insert must not replay a "graded, unpaid" body.
    const cachedResponse = await checkIdempotency(client, body.idempotency_key, 'grade_bet');
    if (cachedResponse) {
      return new Response(cachedResponse, {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const { data: bet, error: betError } = await client
      .from('bets')
      .select('id, bookie_id, player_id, event_id, ticket_id, market, side, odds, stake, status, grade_result, is_parlay, accepted_at, created_at, updated_at')
      .eq('id', body.bet_id)
      .single();

    if (betError || !bet) {
      return json({ success: false, error: 'Bet not found' }, 404);
    }

    const record = bet as BetRecord;

    const { data: bookie, error: bookieError } = await client
      .from('bookies')
      .select('id')
      .eq('auth_user_id', userId)
      .single();

    if (bookieError || !bookie) {
      return json({ success: false, error: 'Bookie not found for current user' }, 403);
    }

    if (record.bookie_id !== bookie.id) {
      return json({ success: false, error: 'Bet does not belong to your bookie account' }, 403);
    }

    // One winner for every book, recorded by a Booki admin. An organizer
    // grading this row would pay the stuck futures pick through the wrong door.
    if (isOutrightMarket(record.market)) {
      return json({
        success: false,
        error: 'Futures are settled by Booki when the result is recorded',
      }, 400);
    }

    // A parlay leg is not a single. settle_bet_tx refuses it. Grade the leg
    // and leave the ticket to settle_parlay_tx.
    if (record.is_parlay) {
      return await gradeParlayLeg(client, userId, body, record);
    }

    return await gradeAndSettleSingle(client, userId, body, record);
  } catch (error) {
    console.error('Error in grade_bet:', error);
    return json({
      success: false,
      error: error instanceof Error ? error.message : 'Internal server error',
    }, 500);
  }
});

async function gradeParlayLeg(
  client: ReturnType<typeof createServiceClient>,
  userId: string,
  body: GradeBetRequest,
  bet: BetRecord,
): Promise<Response> {
  if (bet.status !== 'accepted') {
    return statusError(bet.status);
  }

  const now = new Date().toISOString();
  const isVoid = body.outcome === 'void';
  const { data: updatedBet, error: updateError } = await client
    .from('bets')
    .update({
      grade_result: isVoid ? null : body.outcome,
      status: isVoid ? 'void' : 'graded',
      updated_at: now,
    })
    .eq('id', body.bet_id)
    .eq('status', 'accepted')
    .select()
    .single();

  if (updateError || !updatedBet) {
    console.error('Error updating parlay leg:', updateError);
    return json({ success: false, error: 'Failed to grade bet' }, 500);
  }

  await emitAuditEvent(client, {
    bookieId: bet.bookie_id,
    actorUserId: userId,
    entityType: 'bet',
    entityId: bet.id,
    actionType: 'grade',
    previousState: { status: 'accepted', grade_result: null },
    newState: { status: isVoid ? 'void' : 'graded', grade_result: isVoid ? null : body.outcome },
  });

  const response = JSON.stringify({ success: true, bet: updatedBet, settled: false });
  await storeIdempotency(client, body.idempotency_key, 'grade_bet', userId, response);
  return new Response(response, {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

async function gradeAndSettleSingle(
  client: ReturnType<typeof createServiceClient>,
  userId: string,
  body: GradeBetRequest,
  bet: BetRecord,
): Promise<Response> {
  // A second grade of a settled pick is not a success. Same outcome is an
  // idempotent replay; a different outcome must not look like it stuck.
  if (bet.status === 'settled' && bet.grade_result && bet.grade_result !== body.outcome) {
    return json({ success: false, error: 'Bet has already been settled' }, 409);
  }
  if (bet.status === 'void' && body.outcome !== 'void') {
    return json({ success: false, error: 'Bet has already been voided' }, 409);
  }

  if (bet.status === 'graded' && bet.grade_result && bet.grade_result !== body.outcome) {
    return json({ success: false, error: 'Bet has already been graded' }, 400);
  }

  if (!['accepted', 'graded', 'settled', 'void'].includes(bet.status)) {
    return statusError(bet.status);
  }

  // Grade and, for a win/loss/push, the ledger row are one transaction.
  // A void stays status void and writes no ledger row.
  const { data, error } = await client.rpc('grade_and_settle_bet_tx', {
    p_bet_id: bet.id,
    p_outcome: body.outcome,
    p_actor_user_id: userId,
    p_idempotency_key: manualSingleSettlementKey(bet.id),
  });

  if (error) {
    console.error('grade_and_settle_bet_tx error:', error);
    return json({ success: false, error: error.message }, 500);
  }

  const result = data as {
    success?: boolean;
    error?: string;
    status?: string;
    idempotent?: boolean;
    settled?: boolean;
    voided?: boolean;
    bet?: Record<string, unknown>;
    ledger_entry?: Record<string, unknown> | null;
  } | null;

  if (!result?.success) {
    const conflict = result?.error === 'outcome_conflict';
    const settledConflict = conflict && (result?.status === 'settled' || result?.status === 'void');
    return json({
      success: false,
      error: settledConflict
        ? 'Bet has already been settled'
        : (result?.error === 'outcome_conflict' ? 'Bet has already been graded' : (result?.error || 'Failed to grade bet')),
    }, settledConflict ? 409 : 400);
  }

  const response = JSON.stringify({
    success: true,
    idempotent: result.idempotent === true,
    settled: result.settled === true,
    voided: result.voided === true,
    bet: result.bet ?? bet,
    ledger_entry: result.ledger_entry ?? null,
  });

  await storeIdempotency(client, body.idempotency_key, 'grade_bet', userId, response);
  return new Response(response, {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function statusError(status: string): Response {
  const statusErrors: Record<string, string> = {
    pending: 'Bet must be accepted before grading',
    declined: 'Bet has been declined and cannot be graded',
    graded: 'Bet has already been graded',
    settled: 'Bet has already been settled',
  };
  const errorMessage = statusErrors[status] || `Bet cannot be graded (current status: ${status})`;
  return json({ success: false, error: errorMessage }, 400);
}
