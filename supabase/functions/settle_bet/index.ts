import { corsHeaders } from '../_shared/cors.ts';
import { createServiceClient, getUserIdFromAuthHeader } from '../_shared/supabase.ts';
import { checkIdempotency, storeIdempotency } from '../_shared/idempotency.ts';

interface SettleBetRequest {
  bet_id: string;
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
  bet_id: string;
  amount: number;
  type: string;
  description: string;
  created_at: string;
}

/**
 * Calculate payout amount based on bet outcome and American odds.
 * Positive amount = player wins (money owed to player)
 * Negative amount = player loses (money owed to bookie)
 *
 * For American odds:
 * - Positive odds (e.g., +150): profit = stake * (odds / 100)
 * - Negative odds (e.g., -150): profit = stake * (100 / |odds|)
 *
 * Outcomes:
 * - win: stake + profit (player receives stake back plus winnings)
 * - loss: -stake (player loses their stake to bookie)
 * - push: 0 (no money changes hands)
 * - void: 0 (bet cancelled, no money changes hands)
 */
function calculatePayout(outcome: string, stake: number, odds: number): number {
  switch (outcome) {
    case 'win': {
      // Calculate profit based on American odds
      let profit: number;
      if (odds > 0) {
        // Positive odds: +150 means $100 bet wins $150 profit
        profit = stake * (odds / 100);
      } else {
        // Negative odds: -150 means $150 bet wins $100 profit
        profit = stake * (100 / Math.abs(odds));
      }
      // For a win, player receives their stake back plus profit
      // This is a negative amount because it's money the bookie owes the player
      // (in internal convention: positive = player owes bookie)
      return -profit;
    }
    case 'loss':
      // Player loses stake to bookie (positive = player owes bookie)
      return stake;
    case 'push':
    case 'void':
      // No money changes hands
      return 0;
    default:
      return 0;
  }
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
    const body: SettleBetRequest = await req.json();

    // Validate required fields
    if (!body.bet_id) {
      return new Response(
        JSON.stringify({ success: false, error: 'Missing required field: bet_id' }),
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
    const cachedResponse = await checkIdempotency(client, body.idempotency_key, 'settle_bet');
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

    // Validate: bet must be graded (has outcome in grade_result)
    if (!bet.grade_result) {
      return new Response(
        JSON.stringify({ success: false, error: 'Bet must be graded before settling. Please grade the bet first.' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Validate: bet must not already be settled
    if (bet.status === 'settled') {
      return new Response(
        JSON.stringify({ success: false, error: 'Bet has already been settled' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Validate: bet status should be 'graded' at this point
    if (bet.status !== 'graded') {
      return new Response(
        JSON.stringify({ success: false, error: `Bet cannot be settled (current status: ${bet.status}). Bet must be graded first.` }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Calculate payout based on outcome
    const payoutAmount = calculatePayout(bet.grade_result, Number(bet.stake), bet.odds);

    // Create description for ledger entry
    const outcomeDescriptions: Record<string, string> = {
      'win': 'Bet won',
      'loss': 'Bet lost',
      'push': 'Bet pushed',
      'void': 'Bet voided',
    };
    const description = outcomeDescriptions[bet.grade_result] || `Bet ${bet.grade_result}`;

    // Perform settlement atomically:
    // 1. Update bet status to 'settled'
    // 2. Insert ledger entry
    const now = new Date().toISOString();

    // Update bet status to 'settled'
    const { data: updatedBet, error: updateError } = await client
      .from('bets')
      .update({
        status: 'settled',
        updated_at: now,
      })
      .eq('id', body.bet_id)
      .select()
      .single();

    if (updateError || !updatedBet) {
      console.error('Error updating bet:', updateError);
      return new Response(
        JSON.stringify({ success: false, error: 'Failed to settle bet' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Insert ledger entry for the player
    const { data: ledgerEntry, error: ledgerError } = await client
      .from('ledger_entries')
      .insert({
        bookie_id: bet.bookie_id,
        player_id: bet.player_id,
        bet_id: bet.id,
        amount: payoutAmount,
        type: 'settlement',
        description: description,
      })
      .select()
      .single();

    if (ledgerError || !ledgerEntry) {
      console.error('Error creating ledger entry:', ledgerError);
      // Note: Bet was already updated. In a production system, we'd use a DB transaction.
      // For now, we log the error but still return success since the bet was updated.
      // The ledger entry issue should be investigated separately.
      return new Response(
        JSON.stringify({ success: false, error: 'Bet settled but failed to create ledger entry. Please contact support.' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Prepare success response
    const response = JSON.stringify({
      success: true,
      bet: updatedBet,
      ledger_entry: ledgerEntry
    });

    // Store idempotency key with response
    await storeIdempotency(client, body.idempotency_key, 'settle_bet', userId, response);

    return new Response(
      response,
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (error) {
    console.error('Error in settle_bet:', error);
    return new Response(
      JSON.stringify({ success: false, error: error instanceof Error ? error.message : 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
