import { corsHeaders } from '../_shared/cors.ts';
import { createServiceClient } from '../_shared/supabase.ts';
import { checkIdempotency, storeIdempotency } from '../_shared/idempotency.ts';
import { emitAuditEvent } from '../_shared/audit.ts';

interface ClaimInviteRequest {
  invite_code: string;
  auth_user_id: string;
  idempotency_key?: string;
}

Deno.serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // Parse request body
    const body: ClaimInviteRequest = await req.json();

    if (!body.invite_code || typeof body.invite_code !== 'string') {
      return new Response(
        JSON.stringify({ success: false, error: 'invite_code is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    if (!body.auth_user_id || typeof body.auth_user_id !== 'string') {
      return new Response(
        JSON.stringify({ success: false, error: 'auth_user_id is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const normalizedCode = body.invite_code.trim().toUpperCase();
    const authUserId = body.auth_user_id.toLowerCase();

    // Use service role to bypass RLS
    const client = createServiceClient();

    // Check idempotency if key provided
    if (body.idempotency_key) {
      const cachedResponse = await checkIdempotency(client, body.idempotency_key, 'claim_invite');
      if (cachedResponse) {
        return new Response(
          cachedResponse,
          { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }
    }

    // Verify the auth user actually exists
    const { data: authUser, error: authError } = await client.auth.admin.getUserById(authUserId);
    if (authError || !authUser?.user) {
      return new Response(
        JSON.stringify({ success: false, error: 'Invalid auth_user_id' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Validate invite code exists, is not expired, and is not already claimed
    const { data: invite, error: inviteError } = await client
      .from('invites')
      .select('id, bookie_id, invite_code, email, expires_at, claimed_at')
      .eq('invite_code', normalizedCode)
      .single();

    if (inviteError || !invite) {
      return new Response(
        JSON.stringify({ success: false, error: 'Invalid invite code' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Check if invite is already claimed
    if (invite.claimed_at) {
      return new Response(
        JSON.stringify({ success: false, error: 'This invite has already been claimed' }),
        { status: 409, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Check if invite is expired
    if (new Date(invite.expires_at) < new Date()) {
      return new Response(
        JSON.stringify({ success: false, error: 'This invite has expired' }),
        { status: 410, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Check if auth user is already linked to any bookie (already a member of a group)
    const { data: existingPlayers, error: playerCheckError } = await client
      .from('players')
      .select('id, bookie_id')
      .eq('auth_user_id', authUserId)
      .not('claimed_at', 'is', null);

    if (playerCheckError) {
      console.error('Error checking existing players:', playerCheckError);
      return new Response(
        JSON.stringify({ success: false, error: 'Failed to verify account status' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    if (existingPlayers && existingPlayers.length > 0) {
      return new Response(
        JSON.stringify({
          success: false,
          error: 'already_in_group',
          message: "You're already a member of another organizer's group.",
        }),
        { status: 409, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Derive player name from email (prefix before @)
    const authEmail = authUser.user.email ?? '';
    const playerName = authEmail.includes('@') ? authEmail.split('@')[0] : authEmail || 'Member';

    // Create new Player record
    const { data: newPlayer, error: playerError } = await client
      .from('players')
      .insert({
        bookie_id: invite.bookie_id,
        auth_user_id: authUserId,
        name: playerName,
        email: authEmail || null,
        status: 'active',
        credit_limit: 10000,
        claimed_at: new Date().toISOString(),
      })
      .select('id, name, bookie_id')
      .single();

    if (playerError || !newPlayer) {
      console.error('Error creating player:', playerError);
      return new Response(
        JSON.stringify({ success: false, error: 'Failed to create member account' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Update invite record with claim info
    const { error: updateInviteError } = await client
      .from('invites')
      .update({
        claimed_at: new Date().toISOString(),
        claimed_by_player_id: newPlayer.id,
        version: (invite as Record<string, unknown>).version
          ? Number((invite as Record<string, unknown>).version) + 1
          : 1,
      })
      .eq('id', invite.id);

    if (updateInviteError) {
      console.error('Error updating invite:', updateInviteError);
      // Non-fatal — player was already created, continue
    }

    // Auto-confirm email on auth user (invite code serves as verification)
    if (!authUser.user.email_confirmed_at) {
      const { error: confirmError } = await client.auth.admin.updateUserById(authUserId, {
        email_confirm: true,
      });
      if (confirmError) {
        console.error('Failed to confirm email:', confirmError);
        // Non-fatal — continue with claim
      }
    }

    // Emit audit event
    await emitAuditEvent(client, {
      bookieId: invite.bookie_id,
      actorUserId: authUserId,
      entityType: 'invite',
      entityId: invite.id,
      actionType: 'invite_claimed',
      previousState: { claimed_at: null, claimed_by_player_id: null },
      newState: {
        claimed_at: new Date().toISOString(),
        claimed_by_player_id: newPlayer.id,
        player_name: newPlayer.name,
      },
    });

    // Prepare success response
    const response = JSON.stringify({
      success: true,
      player_id: newPlayer.id,
      bookie_id: newPlayer.bookie_id,
      player_name: newPlayer.name,
    });

    // Store idempotency key if provided
    if (body.idempotency_key) {
      await storeIdempotency(client, body.idempotency_key, 'claim_invite', authUserId, response);
    }

    return new Response(
      response,
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (error) {
    console.error('Error in claim_invite:', error);
    return new Response(
      JSON.stringify({ success: false, error: error instanceof Error ? error.message : 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
