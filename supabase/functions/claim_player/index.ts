import { corsHeaders } from '../_shared/cors.ts';
import { createServiceClient, getUserIdFromAuthHeader } from '../_shared/supabase.ts';

/**
 * claim_player Edge Function
 *
 * Called by a player after signUp to link their auth account to their player record.
 * Uses service role to bypass RLS (players can't update their own record via RLS).
 *
 * Request body:
 *   - invite_code: string (the invite code used during signup)
 *
 * Security:
 *   - Requires valid JWT (the newly created player auth user)
 *   - Only updates a player record that has NO auth_user_id yet (unclaimed)
 *   - Only updates the record matching the invite_code
 */
Deno.serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // Validate auth
    const authHeader = req.headers.get('Authorization');
    const userId = await getUserIdFromAuthHeader(authHeader);
    if (!userId) {
      return new Response(
        JSON.stringify({ error: 'Unauthorized' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Parse request body
    const { invite_code } = await req.json();
    if (!invite_code || typeof invite_code !== 'string') {
      return new Response(
        JSON.stringify({ error: 'invite_code is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const normalizedCode = invite_code.trim().toUpperCase();

    // Use service role to bypass RLS
    const serviceClient = createServiceClient();

    // First verify the player record exists, is unclaimed, and matches the invite code
    const { data: player, error: fetchError } = await serviceClient
      .from('players')
      .select('id, name, bookie_id, auth_user_id')
      .eq('invite_code', normalizedCode)
      .single();

    if (fetchError || !player) {
      return new Response(
        JSON.stringify({ error: 'Invalid invite code' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    if (player.auth_user_id) {
      return new Response(
        JSON.stringify({ error: 'This account has already been claimed' }),
        { status: 409, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Update the player record with the auth user's ID
    const { error: updateError } = await serviceClient
      .from('players')
      .update({
        auth_user_id: userId,
        claimed_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      })
      .eq('id', player.id);

    if (updateError) {
      console.error('Failed to claim player:', updateError);
      return new Response(
        JSON.stringify({ error: 'Failed to claim account' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    return new Response(
      JSON.stringify({
        success: true,
        player_id: player.id,
        bookie_id: player.bookie_id,
        name: player.name,
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (error) {
    console.error('claim_player error:', error);
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
