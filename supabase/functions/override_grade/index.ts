import { corsHeaders } from '../_shared/cors.ts';
import { createServiceClient, getUserIdFromAuthHeader } from '../_shared/supabase.ts';
import { checkIdempotency, storeIdempotency } from '../_shared/idempotency.ts';
import { emitAuditEvent } from '../_shared/audit.ts';

interface OverrideGradeRequest {
  bet_id: string;
  new_outcome: 'win' | 'loss' | 'push' | 'void';
  reason: string;
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
  accepted_at: string | null;
  created_at: string;
  updated_at: string;
}

interface LedgerEntry {
  id: string;
  bookie_id: string;
  player_id: string;
  bet_id: string | null;
  amount: number;
  type: string;
  description: string;
  created_at: string;
}

const VALID_OUTCOMES = ['win', 'loss', 'push', 'void'];

Deno.serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // Extract and validate JWT
    const authHeader = req.headers.get('Authorization');
    const userId = await getUserIdFromAuthHeader(authHeader);

    if (!userId) {
      return new Response(
        JSON.stringify({ success: false, error: 'Unauthorized' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Parse request body
    const body: OverrideGradeRequest = await req.json();

    // Validate required fields
    if (!body.bet_id) {
      return new Response(
        JSON.stringify({ success: false, error: 'Missing required field: bet_id' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    if (!body.new_outcome) {
      return new Response(
        JSON.stringify({ success: false, error: 'Missing required field: new_outcome' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    if (!VALID_OUTCOMES.includes(body.new_outcome)) {
      return new Response(
        JSON.stringify({ success: false, error: `Invalid new_outcome. Must be one of: ${VALID_OUTCOMES.join(', ')}` }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    if (!body.reason || body.reason.trim() === '') {
      return new Response(
        JSON.stringify({ success: false, error: 'Missing required field: reason (must not be empty)' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    if (!body.idempotency_key) {
      return new Response(
        JSON.stringify({ success: false, error: 'Missing required field: idempotency_key' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const client = createServiceClient();

    // Check idempotency - if key exists, return cached response
    const cachedResponse = await checkIdempotency(client, body.idempotency_key, 'override_grade');
    if (cachedResponse) {
      return new Response(
        cachedResponse,
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Fetch the bet
    const { data: bet, error: betError } = await client
      .from('bets')
      .select('id, bookie_id, player_id, event_id, ticket_id, market, side, odds, stake, status, grade_result, accepted_at, created_at, updated_at')
      .eq('id', body.bet_id)
      .single();

    if (betError || !bet) {
      return new Response(
        JSON.stringify({ success: false, error: 'Bet not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Validate: user must be the bookie who owns this bet
    const { data: bookie, error: bookieError } = await client
      .from('bookies')
      .select('id')
      .eq('auth_user_id', userId)
      .single();

    if (bookieError || !bookie) {
      return new Response(
        JSON.stringify({ success: false, error: 'Bookie not found for current user' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Check that the bet belongs to this bookie
    if (bet.bookie_id !== bookie.id) {
      return new Response(
        JSON.stringify({ success: false, error: 'Bet does not belong to your bookie account' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Validate: bet must have been graded (grade_result is not null)
    if (bet.grade_result === null) {
      return new Response(
        JSON.stringify({ success: false, error: 'Bet has not been graded yet. Only graded bets can have their grade overridden.' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const now = new Date().toISOString();
    const reason = body.reason.trim();
    let settlementReversed = false;

    // Store previous state for audit
    const previousGradeResult = bet.grade_result;
    const previousStatus = bet.status;

    // If bet status is 'settled', first reverse the settlement internally
    if (bet.status === 'settled') {
      // Find the original settlement ledger_entry for this bet
      const { data: originalLedgerEntry, error: ledgerError } = await client
        .from('ledger_entries')
        .select('*')
        .eq('bet_id', body.bet_id)
        .eq('type', 'settlement')
        .order('created_at', { ascending: false })
        .limit(1)
        .single();

      if (ledgerError || !originalLedgerEntry) {
        return new Response(
          JSON.stringify({ success: false, error: 'Settlement ledger entry not found for this bet' }),
          { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }

      // Create reversing ledger_entry with opposite amount
      const reversalAmount = -Number(originalLedgerEntry.amount);
      const { data: reversalEntry, error: reversalError } = await client
        .from('ledger_entries')
        .insert({
          bookie_id: bet.bookie_id,
          player_id: bet.player_id,
          bet_id: bet.id,
          amount: reversalAmount,
          type: 'reversal',
          description: `Settlement reversal for grade override: ${reason}`,
        })
        .select()
        .single();

      if (reversalError || !reversalEntry) {
        console.error('Error creating reversal entry:', reversalError);
        return new Response(
          JSON.stringify({ success: false, error: 'Failed to reverse settlement' }),
          { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }

      // Emit audit event for settlement reversal
      await emitAuditEvent(client, {
        bookieId: bet.bookie_id,
        actorUserId: userId,
        entityType: 'bet',
        entityId: bet.id,
        actionType: 'reverse',
        previousState: { status: 'settled', grade_result: previousGradeResult },
        newState: { status: 'graded', grade_result: previousGradeResult },
        reason: `Settlement reversal for grade override: ${reason}`,
      });

      // Emit audit event for reversal ledger entry creation
      await emitAuditEvent(client, {
        bookieId: bet.bookie_id,
        actorUserId: userId,
        entityType: 'ledger_entry',
        entityId: reversalEntry.id,
        actionType: 'create',
        previousState: null,
        newState: reversalEntry as unknown as Record<string, unknown>,
        reason: `Settlement reversal for grade override: ${reason}`,
      });

      settlementReversed = true;
    }

    // Update bet grade_result to new_outcome, keep status as 'graded'
    const { data: updatedBet, error: updateError } = await client
      .from('bets')
      .update({
        grade_result: body.new_outcome,
        status: 'graded',
        updated_at: now,
      })
      .eq('id', body.bet_id)
      .select()
      .single();

    if (updateError || !updatedBet) {
      console.error('Error updating bet:', updateError);
      return new Response(
        JSON.stringify({ success: false, error: 'Failed to override bet grade' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Emit audit event for grade override
    await emitAuditEvent(client, {
      bookieId: bet.bookie_id,
      actorUserId: userId,
      entityType: 'bet',
      entityId: bet.id,
      actionType: 'override',
      previousState: { status: previousStatus, grade_result: previousGradeResult },
      newState: { status: 'graded', grade_result: body.new_outcome },
      reason: reason,
    });

    // Prepare success response
    const response = JSON.stringify({
      success: true,
      bet: updatedBet,
      settlement_reversed: settlementReversed,
    });

    // Store idempotency key with response
    await storeIdempotency(client, body.idempotency_key, 'override_grade', userId, response);

    return new Response(
      response,
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (error) {
    console.error('Error in override_grade:', error);
    return new Response(
      JSON.stringify({ success: false, error: error instanceof Error ? error.message : 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
