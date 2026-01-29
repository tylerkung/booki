import { corsHeaders } from '../_shared/cors.ts';
import { createServiceClient, getUserIdFromAuthHeader } from '../_shared/supabase.ts';
import { checkIdempotency, storeIdempotency } from '../_shared/idempotency.ts';
import { emitAuditEvent } from '../_shared/audit.ts';

interface SubmitBetRequest {
  event_id: string;
  market_id: string;
  side: 'a' | 'b';
  odds: number;
  stake: string;
  player_id: string;
  bookie_id: string;
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
  created_at: string;
  updated_at: string;
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
    const body: SubmitBetRequest = await req.json();

    // Validate required fields
    const requiredFields = ['event_id', 'market_id', 'side', 'odds', 'stake', 'player_id', 'bookie_id', 'idempotency_key'];
    for (const field of requiredFields) {
      if (body[field as keyof SubmitBetRequest] === undefined || body[field as keyof SubmitBetRequest] === null) {
        return new Response(
          JSON.stringify({ success: false, error: `Missing required field: ${field}` }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }
    }

    // Validate side is 'a' or 'b'
    if (body.side !== 'a' && body.side !== 'b') {
      return new Response(
        JSON.stringify({ success: false, error: "Side must be 'a' or 'b'" }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Validate odds is an integer
    if (!Number.isInteger(body.odds)) {
      return new Response(
        JSON.stringify({ success: false, error: 'Odds must be an integer' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Validate stake is a valid decimal string
    const stakeNum = parseFloat(body.stake);
    if (isNaN(stakeNum) || stakeNum <= 0) {
      return new Response(
        JSON.stringify({ success: false, error: 'Stake must be a positive number' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const client = createServiceClient();

    // Check idempotency - if key exists, return cached response
    const cachedResponse = await checkIdempotency(client, body.idempotency_key, 'submit_bet');
    if (cachedResponse) {
      return new Response(
        cachedResponse,
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Validate: player exists and belongs to the specified bookie
    const { data: player, error: playerError } = await client
      .from('players')
      .select('id, bookie_id, auth_user_id')
      .eq('id', body.player_id)
      .single();

    if (playerError || !player) {
      return new Response(
        JSON.stringify({ success: false, error: 'Player not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    if (player.bookie_id !== body.bookie_id) {
      return new Response(
        JSON.stringify({ success: false, error: 'Player does not belong to specified bookie' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Validate: user must be the player submitting their own bet
    if (player.auth_user_id !== userId) {
      return new Response(
        JSON.stringify({ success: false, error: 'Cannot submit bet for another player' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Validate: event exists and is not locked
    const { data: event, error: eventError } = await client
      .from('events')
      .select('id, status, start_time, bookie_id')
      .eq('id', body.event_id)
      .single();

    if (eventError || !event) {
      return new Response(
        JSON.stringify({ success: false, error: 'Event not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Validate event belongs to the same bookie
    if (event.bookie_id !== body.bookie_id) {
      return new Response(
        JSON.stringify({ success: false, error: 'Event does not belong to specified bookie' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Check if event is locked (status is locked or start_time has passed)
    const now = new Date();
    const startTime = new Date(event.start_time);

    if (event.status === 'locked' || startTime <= now) {
      return new Response(
        JSON.stringify({ success: false, error: 'Event is locked for betting' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Generate ticket_id for this bet submission
    const ticketId = crypto.randomUUID();

    // Insert bet record with status 'pending'
    const { data: bet, error: betError } = await client
      .from('bets')
      .insert({
        bookie_id: body.bookie_id,
        player_id: body.player_id,
        event_id: body.event_id,
        ticket_id: ticketId,
        market: body.market_id,
        side: body.side,
        odds: body.odds,
        stake: stakeNum,
        status: 'pending',
        is_parlay: false,
        parlay_legs: 1,
      })
      .select()
      .single();

    if (betError || !bet) {
      console.error('Error inserting bet:', betError);
      return new Response(
        JSON.stringify({ success: false, error: 'Failed to create bet' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Emit audit event for bet creation
    await emitAuditEvent(client, {
      bookieId: body.bookie_id,
      actorUserId: userId,
      entityType: 'bet',
      entityId: bet.id,
      actionType: 'create',
      previousState: null,
      newState: bet as unknown as Record<string, unknown>,
    });

    // Prepare success response
    const response = JSON.stringify({ success: true, bet });

    // Store idempotency key with response
    await storeIdempotency(client, body.idempotency_key, 'submit_bet', userId, response);

    return new Response(
      response,
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (error) {
    console.error('Error in submit_bet:', error);
    return new Response(
      JSON.stringify({ success: false, error: error instanceof Error ? error.message : 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
