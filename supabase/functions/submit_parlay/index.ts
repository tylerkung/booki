import { corsHeaders } from '../_shared/cors.ts';
import { createServiceClient, getUserIdFromAuthHeader } from '../_shared/supabase.ts';
import { checkIdempotency, storeIdempotency } from '../_shared/idempotency.ts';
import { emitAuditEvent } from '../_shared/audit.ts';

interface ParlayLeg {
  event_id: string;
  market_id: string;
  side: string;
  side_indicator: 'a' | 'b';
  odds: number;
}

interface SubmitParlayRequest {
  legs: ParlayLeg[];
  stake: string;
  player_id: string;
  bookie_id: string;
  combined_odds: number;
  idempotency_key: string;
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
    const body: SubmitParlayRequest = await req.json();

    // Validate required fields
    if (!body.legs || !Array.isArray(body.legs) || body.legs.length < 2) {
      return new Response(
        JSON.stringify({ success: false, error: 'Parlay requires at least 2 legs' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const requiredTopLevel = ['stake', 'player_id', 'bookie_id', 'combined_odds', 'idempotency_key'];
    for (const field of requiredTopLevel) {
      if (body[field as keyof SubmitParlayRequest] === undefined || body[field as keyof SubmitParlayRequest] === null) {
        return new Response(
          JSON.stringify({ success: false, error: `Missing required field: ${field}` }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }
    }

    // Validate each leg
    for (let i = 0; i < body.legs.length; i++) {
      const leg = body.legs[i];
      const legFields = ['event_id', 'market_id', 'side', 'side_indicator', 'odds'];
      for (const field of legFields) {
        if (leg[field as keyof ParlayLeg] === undefined || leg[field as keyof ParlayLeg] === null) {
          return new Response(
            JSON.stringify({ success: false, error: `Missing required field in leg ${i}: ${field}` }),
            { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
          );
        }
      }
      if (leg.side_indicator !== 'a' && leg.side_indicator !== 'b') {
        return new Response(
          JSON.stringify({ success: false, error: `Side indicator must be 'a' or 'b' in leg ${i}` }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }
      if (!Number.isInteger(leg.odds)) {
        return new Response(
          JSON.stringify({ success: false, error: `Odds must be an integer in leg ${i}` }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }
    }

    // Validate stake
    const stakeNum = parseFloat(body.stake);
    if (isNaN(stakeNum) || stakeNum <= 0) {
      return new Response(
        JSON.stringify({ success: false, error: 'Stake must be a positive number' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const client = createServiceClient();

    // Check idempotency
    const cachedResponse = await checkIdempotency(client, body.idempotency_key, 'submit_parlay');
    if (cachedResponse) {
      return new Response(
        cachedResponse,
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Normalize UUIDs to lowercase (iOS sends uppercase, DB stores lowercase)
    const normalizedPlayerId = body.player_id?.toLowerCase();
    const requestBookieId = body.bookie_id?.toLowerCase();

    // Validate: player exists and belongs to the specified bookie
    const { data: player, error: playerError } = await client
      .from('players')
      .select('id, bookie_id, auth_user_id')
      .eq('id', normalizedPlayerId)
      .single();

    if (playerError || !player) {
      return new Response(
        JSON.stringify({ success: false, error: 'Player not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const playerBookieId = player.bookie_id?.toLowerCase();
    if (playerBookieId !== requestBookieId) {
      return new Response(
        JSON.stringify({
          success: false,
          error: 'Player does not belong to specified bookie',
          debug: {
            player_bookie_id: player.bookie_id,
            request_bookie_id: body.bookie_id
          }
        }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Validate: user must be the player submitting their own bet
    if (player.auth_user_id?.toLowerCase() !== userId?.toLowerCase()) {
      return new Response(
        JSON.stringify({ success: false, error: 'Cannot submit bet for another player' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Validate all events: exist, not locked, belong to bookie or shared
    const normalizedEventIds = body.legs.map(leg => leg.event_id.toLowerCase());
    const uniqueEventIds = Array.from(new Set(normalizedEventIds));

    const { data: events, error: eventsError } = await client
      .from('events')
      .select('id, status, start_time, bookie_id')
      .in('id', uniqueEventIds);

    if (eventsError || !events) {
      return new Response(
        JSON.stringify({ success: false, error: 'Failed to look up events' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Check all events were found
    const foundEventIds = new Set(events.map((e: { id: string }) => e.id.toLowerCase()));
    const missingEventIds = uniqueEventIds.filter(id => !foundEventIds.has(id));
    if (missingEventIds.length > 0) {
      return new Response(
        JSON.stringify({ success: false, error: `Events not found: ${missingEventIds.join(', ')}` }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Check for locked events
    const now = new Date();
    const lockedEventIds: string[] = [];
    for (const event of events) {
      const startTime = new Date(event.start_time);
      if (event.status === 'locked' || startTime <= now) {
        lockedEventIds.push(event.id);
      }
    }

    if (lockedEventIds.length > 0) {
      return new Response(
        JSON.stringify({ success: false, error: `Events locked: [${lockedEventIds.join(', ')}]` }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Validate events belong to bookie or are shared (bookie_id = null)
    for (const event of events) {
      if (event.bookie_id !== null && event.bookie_id?.toLowerCase() !== requestBookieId) {
        return new Response(
          JSON.stringify({ success: false, error: 'Event does not belong to specified bookie' }),
          { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }
    }

    // Check bookie's manual_bet_acceptance setting
    const { data: bookie } = await client
      .from('bookies')
      .select('manual_bet_acceptance')
      .eq('id', requestBookieId)
      .single();

    const isAutoAccept = !bookie?.manual_bet_acceptance;
    const betStatus = isAutoAccept ? 'accepted' : 'pending';
    const acceptedAt = isAutoAccept ? new Date().toISOString() : null;

    // Generate single ticket_id shared by all legs
    const ticketId = crypto.randomUUID();
    const parlayLegsCount = body.legs.length;

    // Build insert records for all legs
    const betInserts = body.legs.map(leg => ({
      bookie_id: requestBookieId,
      player_id: normalizedPlayerId,
      event_id: leg.event_id.toLowerCase(),
      ticket_id: ticketId,
      market: leg.market_id.toLowerCase(),
      side: leg.side_indicator,
      odds: leg.odds,
      stake: stakeNum,
      status: betStatus,
      accepted_at: acceptedAt,
      is_parlay: true,
      parlay_legs: parlayLegsCount,
    }));

    // Insert all legs in a single transaction (batch insert)
    const { data: bets, error: betsError } = await client
      .from('bets')
      .insert(betInserts)
      .select();

    if (betsError || !bets || bets.length === 0) {
      console.error('Error inserting parlay bets:', betsError);
      return new Response(
        JSON.stringify({
          success: false,
          error: 'Failed to create parlay',
          debug: {
            message: betsError?.message,
            details: betsError?.details,
            hint: betsError?.hint,
            code: betsError?.code
          }
        }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Emit audit events for each leg
    for (const bet of bets) {
      await emitAuditEvent(client, {
        bookieId: body.bookie_id,
        actorUserId: userId,
        entityType: 'bet',
        entityId: bet.id,
        actionType: isAutoAccept ? 'bet_auto_accepted' : 'bet_submitted',
        previousState: null,
        newState: bet as unknown as Record<string, unknown>,
      });
    }

    // Prepare success response
    const response = JSON.stringify({ success: true, bets, ticket_id: ticketId });

    // Store idempotency key with response
    await storeIdempotency(client, body.idempotency_key, 'submit_parlay', userId, response);

    return new Response(
      response,
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (error) {
    console.error('Error in submit_parlay:', error);
    return new Response(
      JSON.stringify({ success: false, error: error instanceof Error ? error.message : 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
