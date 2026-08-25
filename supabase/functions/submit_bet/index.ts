import { corsHeaders } from '../_shared/cors.ts';
import { createServiceClient, getUserIdFromAuthHeader } from '../_shared/supabase.ts';
import { checkIdempotency, storeIdempotency } from '../_shared/idempotency.ts';
import { emitAuditEvent } from '../_shared/audit.ts';
import { sendNotification } from '../_shared/notifications.ts';

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

/**
 * Has this line been superseded?
 *
 * Market rows are keyed by event + type + LINE VALUE, so when a spread moves
 * -3 -> -3.5 the sync inserts a NEW row and never touches the old one again.
 * The -3 row lingers, still bettable, frozen at its old price — and it passes a
 * pure odds comparison, because its odds genuinely are what that row says.
 *
 * A superseded row is identifiable without help from the client: its updated_at
 * falls behind the event's last_odds_update, because the latest feed did not
 * contain that line. The grace window absorbs clock skew and sync batching.
 */
function isSupersededLine(marketUpdatedAt: string | null, eventLastOddsUpdate: string | null): boolean {
  if (!marketUpdatedAt || !eventLastOddsUpdate) return false;
  const GRACE_MS = 15 * 60 * 1000;
  return new Date(marketUpdatedAt).getTime() < new Date(eventLastOddsUpdate).getTime() - GRACE_MS;
}

/**
 * American odds -> decimal payout multiplier, so two prices compare on one
 * scale. Higher is always better for the member.
 */
function americanToDecimal(odds: number): number {
  return odds > 0 ? 1 + odds / 100 : 1 + 100 / Math.abs(odds);
}

/**
 * Phase 1 price guardrail — refuse only a price BETTER for the member than the
 * one currently offered, so a line moving against them never fails a
 * submission on a client that cannot yet explain it.
 * See tasks/prd-line-change-guardrails.md.
 */
function isBetterForMember(submitted: number, current: number): boolean {
  const EPSILON = 0.001;
  return americanToDecimal(submitted) > americanToDecimal(current) + EPSILON;
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

    // Normalize UUIDs to lowercase (iOS sends uppercase, DB stores lowercase)
    const normalizedPlayerId = body.player_id?.toLowerCase();

    // Validate: player exists and belongs to the specified bookie
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

    // Normalize UUIDs to lowercase for comparison (iOS sends uppercase, DB stores lowercase)
    const playerBookieId = player.bookie_id?.toLowerCase();
    const requestBookieId = body.bookie_id?.toLowerCase();

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

    // Validate: event exists and is not locked
    const normalizedEventId = body.event_id?.toLowerCase();

    const { data: event, error: eventError } = await client
      .from('events')
      .select('id, status, start_time, bookie_id, last_odds_update')
      .eq('id', normalizedEventId)
      .single();

    if (eventError || !event) {
      return new Response(
        JSON.stringify({ success: false, error: 'Event not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Validate event belongs to the same bookie (shared events have bookie_id = NULL)
    const eventBookieId = event.bookie_id?.toLowerCase() ?? null;
    if (eventBookieId !== null && eventBookieId !== requestBookieId) {
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
    };

    // Check bookie's manual_bet_acceptance setting for auto-pilot mode
    // Default is false (auto-accept enabled), meaning bets are accepted immediately
    const { data: bookie, error: bookieReadError } = await client
      .from('bookies')
      .select('manual_bet_acceptance, auth_user_id')
      .eq('id', requestBookieId)
      .single();

    // A failed read here costs the organizer their notification, silently.
    // PostgREST fails the whole select if one column is missing, which is
    // exactly how manual_bet_acceptance went unnoticed for so long.
    if (bookieReadError) console.error('Bookie settings read failed:', bookieReadError);

    // Collect policy violation reasons
    const policyViolations: string[] = [];

    // Check stake thresholds
    if (effectivePolicy.require_approval_above !== null && stakeNum > effectivePolicy.require_approval_above) {
      policyViolations.push(`Stake exceeds review threshold ($${effectivePolicy.require_approval_above})`);
    } else if (stakeNum > effectivePolicy.max_stake) {
      policyViolations.push(`Stake exceeds auto-accept limit ($${effectivePolicy.max_stake})`);
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
    // If manual_bet_acceptance is true, ALL bets go to pending regardless of policy
    // If there are policy violations, bet goes to pending
    // Otherwise, auto-accept
    const manualMode = bookie?.manual_bet_acceptance === true;
    const hasPolicyViolations = policyViolations.length > 0;
    const isAutoAccept = !manualMode && !hasPolicyViolations && effectivePolicy.auto_accept_enabled;
    const betStatus = isAutoAccept ? 'accepted' : 'pending';
    const acceptedAt = isAutoAccept ? new Date().toISOString() : null;
    const policyViolationReason = hasPolicyViolations ? policyViolations.join(', ') : null;

    // Look up the market to resolve the full side label and market type
    // The client sends side as 'a' or 'b'; we store the human-readable label
    const normalizedMarketId = body.market_id?.toLowerCase();
    const { data: market, error: marketError } = await client
      .from('markets')
      .select('id, type, side_a, side_b, odds_a, odds_b, updated_at')
      .eq('id', normalizedMarketId)
      .single();

    if (marketError || !market) {
      return new Response(
        JSON.stringify({ success: false, error: 'Market not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Resolve the full side label from the market
    const resolvedSide = body.side === 'a' ? market.side_a : market.side_b;

    if (isSupersededLine(market.updated_at, event.last_odds_update)) {
      console.warn('Superseded line rejected');
      return new Response(
        JSON.stringify({ success: false, error: 'line_no_longer_offered' }),
        { status: 409, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Price guardrail — the server decides what price is on offer.
    const currentOdds = body.side === 'a' ? market.odds_a : market.odds_b;
    if (typeof currentOdds !== 'number') {
      return new Response(
        JSON.stringify({ success: false, error: 'Market has no price' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }
    if (isBetterForMember(body.odds, currentOdds)) {
      console.warn(`Line changed: submitted ${body.odds}, offered ${currentOdds}`);
      return new Response(
        JSON.stringify({
          success: false,
          error: 'line_changed',
          market_id: body.market_id,
          submitted_odds: body.odds,
          current_odds: currentOdds,
          current_side: resolvedSide,
        }),
        { status: 409, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Line moved in the member's favour — give them the better price.
    const priceToStore = isBetterForMember(currentOdds, body.odds) ? currentOdds : body.odds;
    const marketType = market.type; // 'moneyline', 'spread', 'total'

    // Generate ticket_id for this bet submission
    const ticketId = crypto.randomUUID();

    // Insert bet record with appropriate status based on auto-pilot setting
    // Use normalized (lowercase) UUIDs for consistency
    const { data: bet, error: betError } = await client
      .from('bets')
      .insert({
        bookie_id: requestBookieId,
        player_id: normalizedPlayerId,
        event_id: normalizedEventId,
        ticket_id: ticketId,
        market: marketType,
        side: resolvedSide,
        odds: priceToStore,
        stake: stakeNum,
        status: betStatus,
        accepted_at: acceptedAt,
        is_parlay: false,
        parlay_legs: 1,
        policy_violation_reason: policyViolationReason,
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
    // Include auto_accepted flag to distinguish from manual acceptance
    await emitAuditEvent(client, {
      bookieId: body.bookie_id,
      actorUserId: userId,
      entityType: 'bet',
      entityId: bet.id,
      actionType: isAutoAccept ? 'bet_auto_accepted' : 'bet_submitted',
      previousState: null,
      newState: bet as unknown as Record<string, unknown>,
    });

    // Prepare success response
    const response = JSON.stringify({ success: true, bet });

    // Store idempotency key with response
    await storeIdempotency(client, body.idempotency_key, 'submit_bet', userId, response);

    // Notify bookie of new pick (fire-and-forget)
    try {
      if (bookie?.auth_user_id) {
        const playerName = player.name || 'A member';
        const stakeDisplay = `$${stakeNum}`;
        await sendNotification({
          event: 'pick_submitted',
          recipientUserIds: [bookie.auth_user_id],
          title: 'New pick',
          body: `${playerName} — ${resolvedSide} ${marketType} ${stakeDisplay}`,
          data: { deep_link: `booki://bet/${bet.id}` },
        });
      }
    } catch (notifError) {
      console.error('Notification error (submit_bet):', notifError);
    }

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
