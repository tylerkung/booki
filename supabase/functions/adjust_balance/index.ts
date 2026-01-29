import { corsHeaders } from '../_shared/cors.ts';
import { createServiceClient, getUserIdFromAuthHeader } from '../_shared/supabase.ts';
import { checkIdempotency, storeIdempotency } from '../_shared/idempotency.ts';

interface AdjustBalanceRequest {
  player_id: string;
  amount: string; // Decimal string, positive or negative
  reason: string;
  idempotency_key: string;
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
    const body: AdjustBalanceRequest = await req.json();

    // Validate required fields
    if (!body.player_id) {
      return new Response(
        JSON.stringify({ success: false, error: 'Missing required field: player_id' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    if (body.amount === undefined || body.amount === null || body.amount === '') {
      return new Response(
        JSON.stringify({ success: false, error: 'Missing required field: amount' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Parse and validate amount
    const amount = parseFloat(body.amount);
    if (isNaN(amount)) {
      return new Response(
        JSON.stringify({ success: false, error: 'Invalid amount: must be a valid decimal number' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    if (!body.reason || body.reason.trim() === '') {
      return new Response(
        JSON.stringify({ success: false, error: 'Missing required field: reason' }),
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
    const cachedResponse = await checkIdempotency(client, body.idempotency_key, 'adjust_balance');
    if (cachedResponse) {
      return new Response(
        cachedResponse,
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Validate: user must be a bookie
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

    // Validate: player exists and belongs to this bookie
    const { data: player, error: playerError } = await client
      .from('players')
      .select('id, bookie_id')
      .eq('id', body.player_id)
      .single();

    if (playerError || !player) {
      return new Response(
        JSON.stringify({ success: false, error: 'Player not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    if (player.bookie_id !== bookie.id) {
      return new Response(
        JSON.stringify({ success: false, error: 'Player does not belong to your bookie account' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Insert ledger entry for the adjustment
    const { data: ledgerEntry, error: ledgerError } = await client
      .from('ledger_entries')
      .insert({
        bookie_id: bookie.id,
        player_id: body.player_id,
        bet_id: null, // Adjustments are not tied to a specific bet
        amount: amount,
        type: 'adjustment',
        description: body.reason.trim(),
      })
      .select()
      .single();

    if (ledgerError || !ledgerEntry) {
      console.error('Error creating ledger entry:', ledgerError);
      return new Response(
        JSON.stringify({ success: false, error: 'Failed to create balance adjustment' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Prepare success response
    const response = JSON.stringify({
      success: true,
      ledger_entry: ledgerEntry
    });

    // Store idempotency key with response
    await storeIdempotency(client, body.idempotency_key, 'adjust_balance', userId, response);

    return new Response(
      response,
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (error) {
    console.error('Error in adjust_balance:', error);
    return new Response(
      JSON.stringify({ success: false, error: error instanceof Error ? error.message : 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
