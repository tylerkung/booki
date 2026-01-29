import { corsHeaders } from '../_shared/cors.ts';
import { createServiceClient, getUserIdFromAuthHeader } from '../_shared/supabase.ts';
import { checkIdempotency, storeIdempotency } from '../_shared/idempotency.ts';
import { emitAuditEvent } from '../_shared/audit.ts';

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
  accepted_at: string | null;
  created_at: string;
  updated_at: string;
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
    const body: GradeBetRequest = await req.json();

    // Validate required fields
    if (!body.bet_id) {
      return new Response(
        JSON.stringify({ success: false, error: 'Missing required field: bet_id' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    if (!body.outcome) {
      return new Response(
        JSON.stringify({ success: false, error: 'Missing required field: outcome' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    if (!VALID_OUTCOMES.includes(body.outcome)) {
      return new Response(
        JSON.stringify({ success: false, error: `Invalid outcome. Must be one of: ${VALID_OUTCOMES.join(', ')}` }),
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
    const cachedResponse = await checkIdempotency(client, body.idempotency_key, 'grade_bet');
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

    // Validate: bet status must be 'accepted' (not already graded or settled)
    if (bet.status !== 'accepted') {
      const statusErrors: Record<string, string> = {
        'pending': 'Bet must be accepted before grading',
        'declined': 'Bet has been declined and cannot be graded',
        'graded': 'Bet has already been graded',
        'settled': 'Bet has already been settled',
      };
      const errorMessage = statusErrors[bet.status] || `Bet cannot be graded (current status: ${bet.status})`;

      return new Response(
        JSON.stringify({ success: false, error: errorMessage }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Update bet with outcome (stored in grade_result column)
    const now = new Date().toISOString();
    const { data: updatedBet, error: updateError } = await client
      .from('bets')
      .update({
        grade_result: body.outcome,
        status: 'graded',
        updated_at: now,
      })
      .eq('id', body.bet_id)
      .select()
      .single();

    if (updateError || !updatedBet) {
      console.error('Error updating bet:', updateError);
      return new Response(
        JSON.stringify({ success: false, error: 'Failed to grade bet' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Emit audit event for bet grading
    await emitAuditEvent(client, {
      bookieId: bet.bookie_id,
      actorUserId: userId,
      entityType: 'bet',
      entityId: bet.id,
      actionType: 'grade',
      previousState: { status: 'accepted', grade_result: null },
      newState: { status: 'graded', grade_result: body.outcome },
    });

    // Prepare success response
    const response = JSON.stringify({ success: true, bet: updatedBet });

    // Store idempotency key with response
    await storeIdempotency(client, body.idempotency_key, 'grade_bet', userId, response);

    return new Response(
      response,
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (error) {
    console.error('Error in grade_bet:', error);
    return new Response(
      JSON.stringify({ success: false, error: error instanceof Error ? error.message : 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
