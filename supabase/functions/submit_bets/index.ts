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
  submitted_odds?: number;
  current_odds?: number;
  market_id?: string;
  current_side?: string;
}

/**
 * Has this line been superseded?
 *
 * Market rows are keyed by event + type + LINE VALUE, so when a spread moves
 * -3 -> -3.5 the sync inserts a NEW row and never touches the old one again.
 * The -3 row lingers, still bettable, frozen at its old price — and it passes a
 * pure odds comparison, because its odds genuinely are what that row says.
 *
 * A superseded row is identifiable without any help from the client: its
 * updated_at falls behind the event's last_odds_update, because the latest feed
 * did not contain that line. The grace window absorbs clock skew and the time a
 * sync run takes to work through its batches.
 */
function isSupersededLine(marketUpdatedAt: string | null, eventLastOddsUpdate: string | null): boolean {
  if (!marketUpdatedAt || !eventLastOddsUpdate) return false; // cannot tell — let it through
  const GRACE_MS = 15 * 60 * 1000;
  return new Date(marketUpdatedAt).getTime() < new Date(eventLastOddsUpdate).getTime() - GRACE_MS;
}

/**
 * American odds -> decimal payout multiplier, so two prices can be compared on
 * one scale. Higher is always better for the member.
 */
function americanToDecimal(odds: number): number {
  return odds > 0 ? 1 + odds / 100 : 1 + 100 / Math.abs(odds);
}

/**
 * Is `submitted` a better price for the member than `current`?
 *
 * Phase 1 of the line-change guardrails is deliberately one-sided: a bet is
 * refused only when the member would get a BETTER price than the one currently
 * offered. Taking the same or a worse price is allowed through, so a line
 * moving against a member never turns into a failed submission on a client that
 * cannot yet explain why. See tasks/prd-line-change-guardrails.md.
 *
 * Without this the server stored whatever odds the request contained, so any
 * price at all could be submitted — a coin flip at +5000 would have been
 * accepted and paid.
 */
function isBetterForMember(submitted: number, current: number): boolean {
  const EPSILON = 0.001; // absorbs float noise, not a real tolerance
  return americanToDecimal(submitted) > americanToDecimal(current) + EPSILON;
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
      .select('id, bookie_id, auth_user_id, name, win_limit, win_limit_action')
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

    // Win limit check
    let winLimitRequireApproval = false;
    if (player.win_limit !== null && player.win_limit !== undefined) {
      // Calculate balance from ledger entries
      const { data: ledgerEntries } = await client
        .from('ledger_entries')
        .select('amount')
        .eq('player_id', normalizedPlayerId);

      const balanceOwed = (ledgerEntries || []).reduce((sum: number, e: { amount: number }) => sum + (Number(e.amount) || 0), 0);
      const netWinnings = -balanceOwed; // Negative balance = player has won

      if (netWinnings >= Number(player.win_limit)) {
        const action = player.win_limit_action || 'block';
        if (action === 'block') {
          return new Response(
            JSON.stringify({ success: false, error: 'win_limit_reached', net_winnings: netWinnings, win_limit: Number(player.win_limit) }),
            { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
          );
        } else {
          // require_approval — flag for policy violations
          winLimitRequireApproval = true;
        }
      }
    }

    // 3. Batch event lookup
    const normalizedEventIds = body.bets.map(b => b.event_id.toLowerCase());
    const uniqueEventIds = Array.from(new Set(normalizedEventIds));

    const { data: events, error: eventsError } = await client
      .from('events')
      .select('id, status, start_time, bookie_id, last_odds_update')
      .in('id', uniqueEventIds);

    if (eventsError || !events) {
      return new Response(
        JSON.stringify({ success: false, error: 'Failed to look up events' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const eventMap = new Map(
      events.map((e: { id: string; status: string; start_time: string; bookie_id: string | null; last_odds_update: string | null }) => [e.id.toLowerCase(), e])
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
    const { data: bookie, error: bookieReadError } = await client
      .from('bookies')
      .select('manual_bet_acceptance, auth_user_id')
      .eq('id', requestBookieId)
      .single();

    // A failed read here costs the organizer their notification, silently.
    // PostgREST fails the whole select if one column is missing, which is
    // exactly how manual_bet_acceptance went unnoticed for so long.
    if (bookieReadError) console.error('Bookie settings read failed:', bookieReadError);

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

    console.log('Looking up market IDs:', uniqueMarketIds);

    const { data: markets, error: marketsError } = await client
      .from('markets')
      .select('id, type, side_a, side_b, odds_a, odds_b, updated_at')
      .in('id', uniqueMarketIds);

    if (marketsError) {
      console.error('Error fetching markets:', marketsError);
    }

    console.log('Markets found:', markets?.length ?? 0, 'of', uniqueMarketIds.length, 'requested');
    if (markets && markets.length < uniqueMarketIds.length) {
      const foundIds = new Set(markets.map(m => m.id.toLowerCase()));
      const missingIds = uniqueMarketIds.filter(id => !foundIds.has(id));
      console.log('Missing market IDs:', missingIds);
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

      // Price guardrail — the server decides what price is on offer.
      const currentOdds = bet.side === 'a' ? market.odds_a : market.odds_b;
      if (typeof currentOdds !== 'number') {
        failed.push({ index: i, event_id: bet.event_id, error: 'Market has no price' });
        continue;
      }
      if (isSupersededLine(market.updated_at, event.last_odds_update)) {
        console.warn(
          `Superseded line on ${normalizedMarketId}: market ${market.updated_at}, event ${event.last_odds_update}`,
        );
        failed.push({
          index: i,
          event_id: bet.event_id,
          error: 'line_no_longer_offered',
        });
        continue;
      }
      // The line moved against the member since they saw it: they are asking
      // for a better price than is now on offer. Report it with everything the
      // client needs to render a confirmation, rather than a bare failure.
      if (isBetterForMember(bet.odds, currentOdds)) {
        console.warn(
          `Line changed on ${normalizedMarketId}: submitted ${bet.odds}, offered ${currentOdds}`,
        );
        failed.push({
          index: i,
          event_id: bet.event_id,
          error: 'line_changed',
          market_id: bet.market_id,
          submitted_odds: bet.odds,
          current_odds: currentOdds,
          current_side: resolvedSide,
        });
        continue;
      }

      // The line moved in the member's favour. Give them the better price
      // rather than the one they submitted — a book that quietly holds someone
      // to a worse number than it is currently offering is not one people trust.
      const priceToStore = isBetterForMember(currentOdds, bet.odds) ? currentOdds : bet.odds;

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

      if (winLimitRequireApproval) {
        policyViolations.push('Win limit reached');
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
        market_id: market.id,
        side: resolvedSide,
        odds: priceToStore,
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
