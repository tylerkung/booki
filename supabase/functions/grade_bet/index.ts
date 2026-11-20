import { corsHeaders } from '../_shared/cors.ts';
import { createServiceClient, getUserIdFromAuthHeader } from '../_shared/supabase.ts';
import { checkIdempotency, storeIdempotency } from '../_shared/idempotency.ts';
import { emitAuditEvent } from '../_shared/audit.ts';
import { settleBetTx } from '../_shared/settle_tx.ts';
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
  // Already paid. A second click uses a new request key, so the cache above
  // does not catch it. settle_bet_tx would also refuse a second ledger row;
  // returning here avoids rewriting the grade.
  if (bet.status === 'settled' || bet.status === 'void') {
    const response = JSON.stringify({
      success: true,
      idempotent: true,
      settled: bet.status === 'settled',
      bet,
    });
    await storeIdempotency(client, body.idempotency_key, 'grade_bet', userId, response);
    return new Response(response, {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  if (bet.status === 'graded' && bet.grade_result && bet.grade_result !== body.outcome) {
    return json({ success: false, error: 'Bet has already been graded' }, 400);
  }

  if (bet.status !== 'accepted' && bet.status !== 'graded') {
    return statusError(bet.status);
  }

  const now = new Date().toISOString();
  let graded = bet;

  if (bet.status === 'accepted' || bet.grade_result !== body.outcome) {
    // status stays one settle_bet_tx accepts. A void is grade_result 'void',
    // not status 'void': the RPC rejects status 'void' and posts a 0 payout
    // for grade_result 'void', then marks the row settled.
    const { data: updatedBet, error: updateError } = await client
      .from('bets')
      .update({
        grade_result: body.outcome,
        status: 'graded',
        updated_at: now,
      })
      .eq('id', body.bet_id)
      .in('status', ['accepted', 'graded'])
      .select()
      .single();

    if (updateError || !updatedBet) {
      console.error('Error updating bet:', updateError);
      return json({ success: false, error: 'Failed to grade bet' }, 500);
    }

    graded = updatedBet as BetRecord;

    await emitAuditEvent(client, {
      bookieId: bet.bookie_id,
      actorUserId: userId,
      entityType: 'bet',
      entityId: bet.id,
      actionType: 'grade',
      previousState: { status: bet.status, grade_result: bet.grade_result },
      newState: { status: 'graded', grade_result: body.outcome },
    });
  }

  // The ledger write is settle_bet_tx, one transaction, the same path as
  // auto-grading. The key is stable, so a retry that arrives after the grade
  // write and before this call posts the row once.
  const posted = await settleBetTx(client, {
    betId: bet.id,
    actorUserId: userId,
    idempotencyKey: manualSingleSettlementKey(bet.id),
    mode: 'manual',
  });

  if (posted.error || !posted.result) {
    console.error('Error settling bet:', posted.error);
    return json({ success: false, error: posted.error || 'Failed to settle bet' }, 500);
  }

  const response = JSON.stringify({
    success: true,
    idempotent: posted.result.idempotent === true,
    settled: true,
    bet: posted.result.bet ?? graded,
    ledger_entry: posted.result.ledger_entry ?? null,
    settlement_version: posted.result.settlement_version ?? null,
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
