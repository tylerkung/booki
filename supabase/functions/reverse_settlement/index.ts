import { corsHeaders } from '../_shared/cors.ts';
import { createServiceClient, getUserIdFromAuthHeader } from '../_shared/supabase.ts';
import { checkIdempotency, storeIdempotency } from '../_shared/idempotency.ts';

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

    // Call the transactional RPC — it validates bet status, finds original settlement entry,
    // creates reversal entry, updates bet to 'graded', and emits audit events atomically
    const { data: rpcResult, error: rpcError } = await client.rpc('reverse_settlement_tx', {
      p_bet_id: body.bet_id,
      p_actor_user_id: userId,
      p_reason: body.reason.trim(),
      p_idempotency_key: body.idempotency_key,
    });

    if (rpcError) {
      console.error('Error calling reverse_settlement_tx:', rpcError);
      return new Response(
        JSON.stringify({ success: false, error: rpcError.message || 'Failed to reverse settlement' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // RPC returns JSONB with success flag
    if (!rpcResult.success) {
      return new Response(
        JSON.stringify({ success: false, error: rpcResult.error }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Prepare success response (same shape as before)
    const response = JSON.stringify({
      success: true,
      bet: rpcResult.bet,
      reversal_entry: rpcResult.reversal_entry,
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
