import { corsHeaders } from '../_shared/cors.ts';
import { createServiceClient, getUserIdFromAuthHeader } from '../_shared/supabase.ts';
import { checkIdempotency, storeIdempotency } from '../_shared/idempotency.ts';
import { emitAuditEvent } from '../_shared/audit.ts';

interface ReverseSettlementRequest {
  bet_id: string;
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
    const body: ReverseSettlementRequest = await req.json();

    // Validate required fields
    if (!body.bet_id) {
      return new Response(
        JSON.stringify({ success: false, error: 'Missing required field: bet_id' }),
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
    const cachedResponse = await checkIdempotency(client, body.idempotency_key, 'reverse_settlement');
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

    // Validate: bet must be settled
    if (bet.status !== 'settled') {
      return new Response(
        JSON.stringify({ success: false, error: `Bet cannot be reversed (current status: ${bet.status}). Only settled bets can be reversed.` }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

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

    const now = new Date().toISOString();
    const reason = body.reason.trim();

    // Store previous state for audit
    const previousBetState = {
      status: bet.status,
      grade_result: bet.grade_result,
    };

    // Update bet status back to 'graded'
    const { data: updatedBet, error: updateError } = await client
      .from('bets')
      .update({
        status: 'graded',
        updated_at: now,
      })
      .eq('id', body.bet_id)
      .select()
      .single();

    if (updateError || !updatedBet) {
      console.error('Error updating bet:', updateError);
      return new Response(
        JSON.stringify({ success: false, error: 'Failed to reverse bet settlement' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
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
        description: `Settlement reversal: ${reason}`,
      })
      .select()
      .single();

    if (reversalError || !reversalEntry) {
      console.error('Error creating reversal entry:', reversalError);
      // Note: Bet was already updated. In a production system, we'd use a DB transaction.
      return new Response(
        JSON.stringify({ success: false, error: 'Bet status reversed but failed to create reversal ledger entry. Please contact support.' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Emit audit event for bet reversal
    await emitAuditEvent(client, {
      bookieId: bet.bookie_id,
      actorUserId: userId,
      entityType: 'bet',
      entityId: bet.id,
      actionType: 'reverse',
      previousState: previousBetState,
      newState: { status: 'graded', grade_result: bet.grade_result },
      reason: reason,
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
      reason: reason,
    });

    // Prepare success response
    const response = JSON.stringify({
      success: true,
      bet: updatedBet,
      reversal_entry: reversalEntry,
    });

    // Store idempotency key with response
    await storeIdempotency(client, body.idempotency_key, 'reverse_settlement', userId, response);

    return new Response(
      response,
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (error) {
    console.error('Error in reverse_settlement:', error);
    return new Response(
      JSON.stringify({ success: false, error: error instanceof Error ? error.message : 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
