import { corsHeaders } from '../_shared/cors.ts';
import { createServiceClient, getUserIdFromAuthHeader } from '../_shared/supabase.ts';
import { checkIdempotency, storeIdempotency } from '../_shared/idempotency.ts';
import { emitAuditEvent } from '../_shared/audit.ts';
import { decideParlay } from '../_shared/parlay_settle.ts';

interface SettleParlayRequest {
  ticket_id: string;
  parlay_policy: 'treatAsPush' | 'reduceLegReprice';
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
    const body: SettleParlayRequest = await req.json();

    // Validate required fields
    if (!body.ticket_id) {
      return new Response(
        JSON.stringify({ success: false, error: 'Missing required field: ticket_id' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    if (!body.parlay_policy || !['treatAsPush', 'reduceLegReprice'].includes(body.parlay_policy)) {
      return new Response(
        JSON.stringify({ success: false, error: 'Invalid parlay_policy: must be treatAsPush or reduceLegReprice' }),
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
    const cachedResponse = await checkIdempotency(client, body.idempotency_key, 'settle_parlay');
    if (cachedResponse) {
      return new Response(
        cachedResponse,
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Fetch all bets with matching ticket_id
    const { data: legs, error: legsError } = await client
      .from('bets')
      .select('id, bookie_id, player_id, event_id, ticket_id, market, side, odds, stake, status, grade_result, accepted_at, created_at, updated_at')
      .eq('ticket_id', body.ticket_id);

    if (legsError || !legs || legs.length === 0) {
      return new Response(
        JSON.stringify({ success: false, error: 'No bets found for ticket_id' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Validate: user must be the bookie who owns these bets
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

    // Check all legs belong to the same bookie
    const allBelongToBookie = legs.every((leg: BetRecord) => leg.bookie_id === bookie.id);
    if (!allBelongToBookie) {
      return new Response(
        JSON.stringify({ success: false, error: 'Not all bets in this ticket belong to your bookie account' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Validate all legs share same player_id
    const playerId = legs[0].player_id;
    const allSamePlayer = legs.every((leg: BetRecord) => leg.player_id === playerId);
    if (!allSamePlayer) {
      return new Response(
        JSON.stringify({ success: false, error: 'All parlay legs must belong to the same player' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    if (legs.some((leg: BetRecord) => leg.status === 'settled' || leg.status === 'settling')) {
      return new Response(
        JSON.stringify({ success: false, error: 'This multi-pick is already settled' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Same rules as the auto settler: void and push legs are removed and the
    // ticket is repriced. A void leg is not a push of the whole ticket, and
    // the legs do not all have to be status 'graded'.
    const stake = legs[0].stake;
    const bookieId = legs[0].bookie_id;
    const decision = decideParlay(
      stake,
      (legs as BetRecord[]).map((leg) => ({
        status: leg.status,
        grade_result: leg.grade_result,
        odds: leg.odds,
      })),
    );
    if (decision.action !== 'settle' || decision.outcome == null || decision.amount == null) {
      return new Response(
        JSON.stringify({ success: false, error: decision.detail }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const outcome = decision.outcome;
    const payoutAmount = decision.amount;
    const combinedDecimalOdds = decision.decimalOdds ?? null;

    const now = new Date().toISOString();
    const legCount = legs.length;
    const outcomeLabel = outcome === 'win' ? 'won' : outcome === 'loss' ? 'lost' : 'voided';
    const description = `Multi-Pick (${legCount} legs) ${outcomeLabel}`;

    // Create exactly ONE ledger entry for the whole parlay
    const { data: ledgerEntry, error: ledgerError } = await client
      .from('ledger_entries')
      .insert({
        bookie_id: bookieId,
        player_id: playerId,
        bet_id: legs[0].id, // Reference first leg for traceability
        amount: payoutAmount,
        type: 'settlement',
        description: description,
        created_at: now,
      })
      .select()
      .single();

    if (ledgerError || !ledgerEntry) {
      console.error('Error creating ledger entry:', ledgerError);
      return new Response(
        JSON.stringify({ success: false, error: 'Failed to create ledger entry' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Update ALL legs to status='settled' in a single batch update
    const legIds = legs.map((leg: BetRecord) => leg.id);
    const { error: updateError } = await client
      .from('bets')
      .update({ status: 'settled', updated_at: now })
      .in('id', legIds);

    if (updateError) {
      console.error('Error updating bet statuses:', updateError);
      return new Response(
        JSON.stringify({ success: false, error: 'Failed to update bet statuses' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Write settlement_events row
    try {
      await client
        .from('settlement_events')
        .insert({
          bookie_id: bookieId,
          bet_id: legs[0].id, // Reference first leg
          mode: 'manual',
          actor_user_id: userId,
          idempotency_key: body.idempotency_key,
          ledger_entry_ids: [ledgerEntry.id],
        });
    } catch (err) {
      console.error('Error creating settlement_event (non-blocking):', err);
    }

    // Emit audit event for parlay settlement
    await emitAuditEvent(client, {
      bookieId: bookieId,
      actorUserId: userId,
      entityType: 'bet',
      entityId: legs[0].id,
      actionType: 'settle',
      previousState: {
        ticket_id: body.ticket_id,
        leg_count: legCount,
        leg_ids: legIds,
      },
      newState: {
        ticket_id: body.ticket_id,
        outcome: outcome,
        parlay_policy: body.parlay_policy,
        combined_decimal_odds: combinedDecimalOdds,
        payout: payoutAmount,
        legs_settled: legCount,
        ledger_entry_id: ledgerEntry.id,
      },
    });

    // Prepare success response
    const response = JSON.stringify({
      success: true,
      outcome: outcome,
      payout: payoutAmount,
      ledger_entry: ledgerEntry,
      legs_settled: legCount,
    });

    // Store idempotency key with response
    await storeIdempotency(client, body.idempotency_key, 'settle_parlay', userId, response);

    return new Response(
      response,
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (error) {
    console.error('Error in settle_parlay:', error);
    return new Response(
      JSON.stringify({ success: false, error: error instanceof Error ? error.message : 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
