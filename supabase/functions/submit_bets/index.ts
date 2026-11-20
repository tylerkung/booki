import { corsHeaders } from '../_shared/cors.ts';
import { createServiceClient, getUserIdFromAuthHeader } from '../_shared/supabase.ts';
import { claimedResponse, replayedResponse } from '../_shared/submit_claim.ts';
import { emitAuditEvent } from '../_shared/audit.ts';
import { sendNotification } from '../_shared/notifications.ts';
import { supersededMarketIds, isBetterForMember } from '../_shared/line_guard.ts';
import { resolveStoredLeg, singleBetIndicator } from '../_shared/market_validation.ts';

interface BatchBetInput {
  event_id: string;
  market_id: string;
  side: string;
  /** Readable label. Optional. Production ignores it; the new function stores the market's label either way. */
  side_label?: string;
  side_indicator?: 'a' | 'b';
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
      // 'a'/'b' in side is the deployed contract. A label in side is accepted
      // only when side_indicator carries the letter, so an old client and a
      // new client both pass, in either deploy order.
      if (!singleBetIndicator(bet)) {
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

    // Replay before the line, limit, and lock checks. A retry of a ticket
    // that already landed must return that ticket even if the game has
    // since locked or the price has moved. A different payload is 422 and
    // writes nothing. A miss falls through and the claim below is what
    // makes two in-flight calls insert once.
    const replay = await replayedResponse(
      client,
      'submit_bets',
      userId,
      normalizedPlayerId,
      body.idempotency_key,
      body as unknown as Record<string, unknown>,
      corsHeaders,
    );
    if (replay) return replay;

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
      .select('id, type, side_a, side_b, odds_a, odds_b, updated_at, bettable, stat_key, subject_player_id')
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

    // One RPC for the whole batch rather than one per bet — the loop below is
    // deliberately free of DB calls.
    const superseded = await supersededMarketIds(
      client,
      (markets ?? []).map(m => m.id),
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

      // A market can be priced and shown without being gradeable — MLB player
      // props are the first case, since balldontlie has no MLB statlines on
      // this plan. The client disables those controls, but the client is not
      // the authority: an ungradeable bet has no correct outcome, so it is
      // refused here too.
      if (market.bettable === false) {
        failed.push({ index: i, event_id: bet.event_id, error: 'This market is not available to bet' });
        continue;
      }

      // Letter in `side` wins, so the payload production already accepts
      // resolves the same way. side_indicator covers a label sent in `side`.
      const indicator = singleBetIndicator(bet);
      const stored = resolveStoredLeg(market, indicator);
      if (!stored.ok) {
        failed.push({ index: i, event_id: bet.event_id, error: stored.error });
        continue;
      }
      const resolvedSide = stored.side;
      const marketType = stored.market;

      // Price guardrail — the server decides what price is on offer.
      const currentOdds = indicator === 'a' ? market.odds_a : market.odds_b;
      if (typeof currentOdds !== 'number') {
        failed.push({ index: i, event_id: bet.event_id, error: 'Market has no price' });
        continue;
      }
      if (superseded.has(normalizedMarketId)) {
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
        stat_key: stored.snapshot.stat_key,
        subject_player_id: stored.snapshot.subject_player_id,
        prop_line: stored.snapshot.prop_line,
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

    // Claim the key and insert the bets in one transaction. A second call
    // with this key returns the original rows and does not insert again.
    const claimed = await claimedResponse(
      client,
      'submit_bets',
      userId,
      normalizedPlayerId,
      requestBookieId,
      body.idempotency_key,
      body as unknown as Record<string, unknown>,
      validBetInserts,
      failed.length > 0 ? { failed } : {},
      corsHeaders,
    );
    if (claimed.http.status !== 200) return claimed.http;

    if (!claimed.replayed) {
      const payload = JSON.parse(claimed.body) as { bets?: Array<Record<string, unknown>> };
      const createdBets = payload.bets ?? [];

      for (const bet of createdBets) {
        const isAutoAccept = bet.status === 'accepted';
        emitAuditEvent(client, {
          bookieId: body.bookie_id,
          actorUserId: userId,
          entityType: 'bet',
          entityId: String(bet.id),
          actionType: isAutoAccept ? 'bet_auto_accepted' : 'bet_submitted',
          previousState: null,
          newState: bet,
        }).catch(err => console.error('Audit event error:', err));
      }

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
    }

    return claimed.http;
  } catch (error) {
    console.error('Error in submit_bets:', error);
    return new Response(
      JSON.stringify({ success: false, error: error instanceof Error ? error.message : 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
