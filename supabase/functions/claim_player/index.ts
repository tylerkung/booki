import { corsHeaders } from '../_shared/cors.ts';
import { createServiceClient } from '../_shared/supabase.ts';
import { authorizeClaimRequest } from '../_shared/claim_auth.ts';

/**
 * claim_player Edge Function
 *
 * Links an auth account to an existing unclaimed player row. Uses the service
 * role to bypass RLS (players can't update their own record via RLS).
 *
 * Request body:
 *   - invite_code: string (the invite code on the player row)
 *   - auth_user_id: optional when the Authorization header is a user JWT
 *
 * The caller comes from the user JWT. A body id that names someone else is
 * 403. With no user JWT, the body id is accepted only for an unconfirmed
 * account that is not an organizer, and that path does not confirm email.
 * The web dashboard does not call this function; claim_invite is the join
 * path. Shipped iOS signup calls claim_invite with the anon key.
 */
Deno.serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // Parse request body
    const { invite_code, auth_user_id } = await req.json();
    if (!invite_code || typeof invite_code !== 'string') {
      return new Response(
        JSON.stringify({ error: 'invite_code is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }
    const normalizedCode = invite_code.trim().toUpperCase();

    // Service role bypasses RLS. The caller is still the JWT user.
    const serviceClient = createServiceClient();
    const caller = await authorizeClaimRequest(
      serviceClient,
      req.headers.get('Authorization'),
      auth_user_id,
    );
    if (!caller.ok) {
      return new Response(
        JSON.stringify({ error: caller.error }),
        { status: caller.status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const userId = caller.userId;
    const authUser = { user: caller.user };

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

    // Update the player record with the auth user's ID and email
    const authEmail = authUser.user.email ?? null;
    const { error: updateError } = await serviceClient
      .from('players')
      .update({
        auth_user_id: userId,
        email: authEmail,
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

    // A matching user JWT may confirm the email. The interim path (no user
    // JWT) must not — caller.confirmEmail is false there.
    if (caller.confirmEmail && !authUser.user.email_confirmed_at) {
      const { error: confirmError } = await serviceClient.auth.admin.updateUserById(userId, {
        email_confirm: true,
      });
      if (confirmError) {
        console.error('Failed to confirm email:', confirmError);
      }
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
