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
      .select('id, bookie_id, auth_user_id, win_limit, win_limit_action')
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

    // Standalone open bet limit: 25 max for players without a bookie
    if (!player.bookie_id) {
      const { count: openBetCount } = await client
        .from('bets')
        .select('*', { count: 'exact', head: true })
        .eq('player_id', normalizedPlayerId)
        .in('status', ['pending', 'accepted']);

      if ((openBetCount ?? 0) >= 25) {
        return new Response(
          JSON.stringify({ success: false, error: 'open_bet_limit_reached', limit: 25, current: openBetCount ?? 0 }),
          { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }
    }

    // Win limit check
    let winLimitRequireApproval = false;
    if (player.win_limit !== null && player.win_limit !== undefined) {
      const { data: ledgerEntries } = await client
        .from('ledger_entries')
        .select('amount')
        .eq('player_id', normalizedPlayerId);

      const balanceOwed = (ledgerEntries || []).reduce((sum: number, e: { amount: number }) => sum + (Number(e.amount) || 0), 0);
      const netWinnings = -balanceOwed;

      if (netWinnings >= Number(player.win_limit)) {
        const action = player.win_limit_action || 'block';
        if (action === 'block') {
          return new Response(
            JSON.stringify({ success: false, error: 'win_limit_reached', net_winnings: netWinnings, win_limit: Number(player.win_limit) }),
            { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
          );
        } else {
          winLimitRequireApproval = true;
        }
      }
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

    // Fetch acceptance policy for this bookie
    const { data: policy } = await client
      .from('acceptance_policies')
      .select('*')
      .eq('bookie_id', requestBookieId)
      .single();

    // Default policy values if none exists
    const effectivePolicy = {
      max_stake: policy?.max_stake ?? 100,
      require_approval_above: policy?.require_approval_above ?? null,
      auto_accept_enabled: policy?.auto_accept_enabled ?? true,
      auto_accept_new_players: policy?.auto_accept_new_players ?? true,
      new_player_bet_threshold: policy?.new_player_bet_threshold ?? 5,
      auto_accept_parlays: policy?.auto_accept_parlays ?? true,
      parlay_max_legs: policy?.parlay_max_legs ?? 4,
    };

    // Check bookie's tier and manual_bet_acceptance setting
    const { data: bookie } = await client
      .from('bookies')
      .select('manual_bet_acceptance, tier')
      .eq('id', requestBookieId)
      .single();

    // Tier enforcement: parlays require Pro
    const bookieTier = bookie?.tier ?? 'free';
    if (bookieTier !== 'pro') {
      return new Response(
        JSON.stringify({ success: false, error: 'pro_required' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Collect policy violation reasons
    const policyViolations: string[] = [];

    // Check stake thresholds (same as single bets)
    if (effectivePolicy.require_approval_above !== null && stakeNum > effectivePolicy.require_approval_above) {
      policyViolations.push(`Stake exceeds review threshold ($${effectivePolicy.require_approval_above})`);
    } else if (stakeNum > effectivePolicy.max_stake) {
      policyViolations.push(`Stake exceeds auto-accept limit ($${effectivePolicy.max_stake})`);
    }

    // Check parlay-specific rules
    if (!effectivePolicy.auto_accept_parlays) {
      policyViolations.push('Parlays require review');
    }

    if (body.legs.length > effectivePolicy.parlay_max_legs) {
      policyViolations.push(`Exceeds max parlay legs (${effectivePolicy.parlay_max_legs})`);
    }

    if (winLimitRequireApproval) {
      policyViolations.push('Win limit reached');
    }

    // Check new player bet count
    if (!effectivePolicy.auto_accept_new_players) {
      const { count: betCount } = await client
        .from('bets')
        .select('*', { count: 'exact', head: true })
        .eq('player_id', normalizedPlayerId);

      if ((betCount ?? 0) < effectivePolicy.new_player_bet_threshold) {
        policyViolations.push('New player requires review');
      }
    }

    // Determine bet status based on policy violations and auto-pilot setting
    const manualMode = bookie?.manual_bet_acceptance === true;
    const hasPolicyViolations = policyViolations.length > 0;
    const isAutoAccept = !manualMode && !hasPolicyViolations && effectivePolicy.auto_accept_enabled;
    const betStatus = isAutoAccept ? 'accepted' : 'pending';
    const policyViolationReason = hasPolicyViolations ? policyViolations.join(', ') : null;

    // Generate single ticket_id shared by all legs
    const ticketId = crypto.randomUUID();
    const parlayLegsCount = body.legs.length;

    // Look up all markets to resolve full side labels and market types
    const marketIds = body.legs.map(leg => leg.market_id.toLowerCase());
    const { data: markets, error: marketsError } = await client
      .from('markets')
      .select('id, type, side_a, side_b')
      .in('id', marketIds);

    if (marketsError) {
      console.error('Error fetching markets:', marketsError);
    }

    const marketMap = new Map(
      (markets ?? []).map(m => [m.id.toLowerCase(), m])
    );

    // Build insert records for all legs
    const betInserts = body.legs.map(leg => {
      const market = marketMap.get(leg.market_id.toLowerCase());
      const resolvedSide = market
        ? (leg.side_indicator === 'a' ? market.side_a : market.side_b)
        : leg.side; // fallback to client-provided side
      const marketType = market?.type ?? leg.market_id.toLowerCase();

      return {
        bookie_id: requestBookieId,
        player_id: normalizedPlayerId,
        event_id: leg.event_id.toLowerCase(),
        ticket_id: ticketId,
        market: marketType,
        side: resolvedSide,
        odds: leg.odds,
        stake: stakeNum,
        status: betStatus,
        is_parlay: true,
        parlay_legs: parlayLegsCount,
        policy_violation_reason: policyViolationReason,
      };
    });

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
