import { corsHeaders } from '../_shared/cors.ts';
import { createServiceClient, getUserIdFromAuthHeader } from '../_shared/supabase.ts';
import { checkIdempotency, storeIdempotency } from '../_shared/idempotency.ts';
import { emitAuditEvent } from '../_shared/audit.ts';
import { sendNotification } from '../_shared/notifications.ts';

interface BatchBetInput {
  event_id: string;
  market_id: string;
  side: string;
  odds: number;
  stake: string;
}

interface SubmitBetsRequest {
  bets: BatchBetInput[];
  player_id: string;
  bookie_id: string;
  idempotency_key: string;
}

interface FailedBet {
  index: number;
  event_id: string;
  error: string;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get('Authorization');
    const userId = await getUserIdFromAuthHeader(authHeader);

    if (!userId) {
      return new Response(
        JSON.stringify({ success: false, error: 'Unauthorized' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const body: SubmitBetsRequest = await req.json();

    // Validate required fields
    if (!body.bets || !Array.isArray(body.bets) || body.bets.length === 0) {
      return new Response(
        JSON.stringify({ success: false, error: 'At least one bet is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const requiredTopLevel = ['player_id', 'bookie_id', 'idempotency_key'];
    for (const field of requiredTopLevel) {
      if (body[field as keyof SubmitBetsRequest] === undefined || body[field as keyof SubmitBetsRequest] === null) {
        return new Response(
          JSON.stringify({ success: false, error: `Missing required field: ${field}` }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }
    }

    // Validate each bet input
    for (let i = 0; i < body.bets.length; i++) {
      const bet = body.bets[i];
      const betFields = ['event_id', 'market_id', 'side', 'odds', 'stake'];
      for (const field of betFields) {
        if (bet[field as keyof BatchBetInput] === undefined || bet[field as keyof BatchBetInput] === null) {
          return new Response(
            JSON.stringify({ success: false, error: `Missing required field in bet ${i}: ${field}` }),
            { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
          );
        }
      }
      if (bet.side !== 'a' && bet.side !== 'b') {
        return new Response(
          JSON.stringify({ success: false, error: `Side must be 'a' or 'b' in bet ${i}` }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }
      if (!Number.isInteger(bet.odds)) {
        return new Response(
          JSON.stringify({ success: false, error: `Odds must be an integer in bet ${i}` }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }
      const stakeNum = parseFloat(bet.stake);
      if (isNaN(stakeNum) || stakeNum <= 0) {
        return new Response(
          JSON.stringify({ success: false, error: `Stake must be a positive number in bet ${i}` }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }
    }

    const client = createServiceClient();

    // 1. Idempotency check
    const cachedResponse = await checkIdempotency(client, body.idempotency_key, 'submit_bets');
    if (cachedResponse) {
      return new Response(
        cachedResponse,
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Normalize UUIDs
    const normalizedPlayerId = body.player_id.toLowerCase();
    const requestBookieId = body.bookie_id.toLowerCase();

    // 2. Player lookup + validation
    const { data: player, error: playerError } = await client
      .from('players')
      .select('id, bookie_id, auth_user_id, name')
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
        JSON.stringify({ success: false, error: 'Player does not belong to specified bookie' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

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

    // 3. Batch event lookup
    const normalizedEventIds = body.bets.map(b => b.event_id.toLowerCase());
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

    const eventMap = new Map(
      events.map((e: { id: string; status: string; start_time: string; bookie_id: string | null }) => [e.id.toLowerCase(), e])
    );

    // Validate events belong to bookie or are shared
    for (const event of events) {
      if (event.bookie_id !== null && event.bookie_id?.toLowerCase() !== requestBookieId) {
        return new Response(
          JSON.stringify({ success: false, error: 'Event does not belong to specified bookie' }),
          { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }
    }

    // 4. Acceptance policy
    const { data: policy } = await client
      .from('acceptance_policies')
      .select('*')
      .eq('bookie_id', requestBookieId)
      .single();

    const effectivePolicy = {
      max_stake: policy?.max_stake ?? 100,
      require_approval_above: policy?.require_approval_above ?? null,
      auto_accept_enabled: policy?.auto_accept_enabled ?? true,
      auto_accept_new_players: policy?.auto_accept_new_players ?? true,
      new_player_bet_threshold: policy?.new_player_bet_threshold ?? 5,
    };

    // 5. Bookie manual mode
    const { data: bookie } = await client
      .from('bookies')
      .select('manual_bet_acceptance, auth_user_id')
      .eq('id', requestBookieId)
      .single();

    const manualMode = bookie?.manual_bet_acceptance === true;

    // 6. Player bet count for new-player check
    let isNewPlayer = false;
    if (!effectivePolicy.auto_accept_new_players) {
      const { count: betCount } = await client
        .from('bets')
        .select('*', { count: 'exact', head: true })
        .eq('player_id', normalizedPlayerId);

      if ((betCount ?? 0) < effectivePolicy.new_player_bet_threshold) {
        isNewPlayer = true;
      }
    }

    // 7. Batch market lookup
    const marketIds = body.bets.map(b => b.market_id.toLowerCase());
    const uniqueMarketIds = Array.from(new Set(marketIds));

    const { data: markets, error: marketsError } = await client
      .from('markets')
      .select('id, type, side_a, side_b')
      .in('id', uniqueMarketIds);

    if (marketsError) {
      console.error('Error fetching markets:', marketsError);
    }

    const marketMap = new Map(
      (markets ?? []).map(m => [m.id.toLowerCase(), m])
    );

    // 8. Per-bet validation loop — no DB calls, uses cached lookups
    const now = new Date();
    const failed: FailedBet[] = [];
    const validBetInserts: Record<string, unknown>[] = [];
    const validBetIndices: number[] = [];

    for (let i = 0; i < body.bets.length; i++) {
      const bet = body.bets[i];
      const normalizedEventId = bet.event_id.toLowerCase();
      const normalizedMarketId = bet.market_id.toLowerCase();
      const stakeNum = parseFloat(bet.stake);

      // Check event exists
      const event = eventMap.get(normalizedEventId);
      if (!event) {
        failed.push({ index: i, event_id: bet.event_id, error: 'Event not found' });
        continue;
      }

      // Check event not locked
      const startTime = new Date(event.start_time);
      if (event.status === 'locked' || startTime <= now) {
        failed.push({ index: i, event_id: bet.event_id, error: 'Event is locked for betting' });
        continue;
      }

      // Check market exists
      const market = marketMap.get(normalizedMarketId);
      if (!market) {
        failed.push({ index: i, event_id: bet.event_id, error: 'Market not found' });
        continue;
      }

      // Resolve side label and market type
      const resolvedSide = bet.side === 'a' ? market.side_a : market.side_b;
      const marketType = market.type;

      // Per-bet policy violations
      const policyViolations: string[] = [];

      if (effectivePolicy.require_approval_above !== null && stakeNum > effectivePolicy.require_approval_above) {
        policyViolations.push(`Stake exceeds review threshold ($${effectivePolicy.require_approval_above})`);
      } else if (stakeNum > effectivePolicy.max_stake) {
        policyViolations.push(`Stake exceeds auto-accept limit ($${effectivePolicy.max_stake})`);
      }

      if (isNewPlayer) {
        policyViolations.push('New player requires review');
      }

      const hasPolicyViolations = policyViolations.length > 0;
      const isAutoAccept = !manualMode && !hasPolicyViolations && effectivePolicy.auto_accept_enabled;
      const betStatus = isAutoAccept ? 'accepted' : 'pending';
      const acceptedAt = isAutoAccept ? new Date().toISOString() : null;
      const policyViolationReason = hasPolicyViolations ? policyViolations.join(', ') : null;

      const ticketId = crypto.randomUUID();

      validBetInserts.push({
        bookie_id: requestBookieId,
        player_id: normalizedPlayerId,
        event_id: normalizedEventId,
        ticket_id: ticketId,
        market: marketType,
        side: resolvedSide,
        odds: bet.odds,
        stake: stakeNum,
        status: betStatus,
        accepted_at: acceptedAt,
        is_parlay: false,
        parlay_legs: 1,
        policy_violation_reason: policyViolationReason,
      });
      validBetIndices.push(i);
    }

    // If all bets failed validation, return early
    if (validBetInserts.length === 0) {
      return new Response(
        JSON.stringify({ success: false, error: 'All bets failed validation', failed }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // 9. Batch insert all valid bets
    const { data: createdBets, error: betsError } = await client
      .from('bets')
      .insert(validBetInserts)
      .select();

    if (betsError || !createdBets || createdBets.length === 0) {
      console.error('Error inserting bets:', betsError);
      return new Response(
        JSON.stringify({
          success: false,
          error: 'Failed to create bets',
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

    // 10. Audit events (fire-and-forget)
    for (const bet of createdBets) {
      const isAutoAccept = bet.status === 'accepted';
      emitAuditEvent(client, {
        bookieId: body.bookie_id,
        actorUserId: userId,
        entityType: 'bet',
        entityId: bet.id,
        actionType: isAutoAccept ? 'bet_auto_accepted' : 'bet_submitted',
        previousState: null,
        newState: bet as unknown as Record<string, unknown>,
      }).catch(err => console.error('Audit event error:', err));
    }

    // Prepare response
    const response = JSON.stringify({
      success: true,
      bets: createdBets,
      failed: failed.length > 0 ? failed : undefined,
    });

    // 11. Store idempotency
    await storeIdempotency(client, body.idempotency_key, 'submit_bets', userId, response);

    // Notify bookie of batch pick submission (fire-and-forget)
    try {
      if (bookie?.auth_user_id && createdBets.length > 0) {
        const playerName = player.name || 'A member';
        await sendNotification({
          event: 'pick_submitted',
          recipientUserIds: [bookie.auth_user_id],
          title: 'New picks',
          body: `${playerName} submitted ${createdBets.length} pick${createdBets.length > 1 ? 's' : ''}`,
          data: { deep_link: 'booki://picks' },
        });
      }
    } catch (notifError) {
      console.error('Notification error (submit_bets):', notifError);
    }

    return new Response(
      response,
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (error) {
    console.error('Error in submit_bets:', error);
    return new Response(
      JSON.stringify({ success: false, error: error instanceof Error ? error.message : 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
