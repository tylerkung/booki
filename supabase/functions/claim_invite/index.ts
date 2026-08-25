import { corsHeaders } from '../_shared/cors.ts';
import { createServiceClient } from '../_shared/supabase.ts';
import { checkIdempotency, storeIdempotency } from '../_shared/idempotency.ts';
import { emitAuditEvent } from '../_shared/audit.ts';
import { sendNotification } from '../_shared/notifications.ts';

interface ClaimInviteRequest {
  /**
   * Omit to resolve the invite from the authenticated user's verified email.
   * That path exists because an invitee who cannot claim their link has no code
   * to type — they only have the address the invite was sent to.
   */
  invite_code?: string;
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

    if (body.invite_code !== undefined && typeof body.invite_code !== 'string') {
      return new Response(
        JSON.stringify({ success: false, error: 'invite_code must be a string' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    if (!body.auth_user_id || typeof body.auth_user_id !== 'string') {
      return new Response(
        JSON.stringify({ success: false, error: 'auth_user_id is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const normalizedCode = body.invite_code?.trim().toUpperCase() ?? null;
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

    // Resolve the invite either by code, or — when no code was supplied — by the
    // address it was sent to. Someone who was invited but could not claim the
    // link has no code to type; the only thing they carry is their email, and by
    // this point Supabase has verified it.
    const inviteeEmail = (authUser.user.email ?? '').trim().toLowerCase();
    let invite: {
      id: string; bookie_id: string; invite_code: string;
      email: string | null; expires_at: string; claimed_at: string | null;
    } | null = null;
    let matchedByEmail = false;

    if (normalizedCode) {
      const { data } = await client
        .from('invites')
        .select('id, bookie_id, invite_code, email, expires_at, claimed_at')
        .eq('invite_code', normalizedCode)
        .single();
      invite = data ?? null;
    } else if (inviteeEmail) {
      // Most recent unclaimed invite addressed to this person.
      const { data } = await client
        .from('invites')
        .select('id, bookie_id, invite_code, email, expires_at, claimed_at')
        .ilike('email', inviteeEmail)
        .is('claimed_at', null)
        .order('created_at', { ascending: false })
        .limit(1);
      invite = data && data.length > 0 ? data[0] : null;
      matchedByEmail = invite !== null;
    }

    if (!invite) {
      return new Response(
        JSON.stringify({
          success: false,
          error: normalizedCode ? 'Invalid invite code' : 'No pending invite for this email',
        }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // A code can be forwarded to anyone, so it stays subject to expiry. An
    // invite addressed to a specific person, being claimed by that person after
    // their address was verified, is stronger evidence than any code — the
    // expiry window exists to limit stale shared codes, not to lock the
    // addressee out of their own invite.
    const isAddressee =
      matchedByEmail ||
      (invite.email !== null && invite.email.trim().toLowerCase() === inviteeEmail);

    // Check if invite is already claimed
    if (invite.claimed_at) {
      return new Response(
        JSON.stringify({ success: false, error: 'This invite has already been claimed' }),
        { status: 409, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Check if invite is expired (code-based claims only — see above)
    if (!isAddressee && new Date(invite.expires_at) < new Date()) {
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

    // Fetch bookie's default settings
    let creditLimit = 1000; // fallback default
    let winLimit: number | null = null;
    let winLimitAction: string | null = null;
    const { data: bookieRecord } = await client
      .from('bookies')
      .select('default_credit_limit, default_win_limit, default_win_limit_action, auth_user_id')
      .eq('id', invite.bookie_id)
      .single();

    if (bookieRecord?.default_credit_limit != null) {
      creditLimit = Number(bookieRecord.default_credit_limit);
    }
    if (bookieRecord?.default_win_limit != null) {
      winLimit = Number(bookieRecord.default_win_limit);
      winLimitAction = bookieRecord.default_win_limit_action || 'block';
    }

    // Create new Player record
    const playerInsert: Record<string, unknown> = {
      bookie_id: invite.bookie_id,
      auth_user_id: authUserId,
      name: playerName,
      email: authEmail || null,
      status: 'active',
      credit_limit: creditLimit,
      claimed_at: new Date().toISOString(),
    };
    if (winLimit !== null) {
      playerInsert.win_limit = winLimit;
      playerInsert.win_limit_action = winLimitAction;
    }

    const { data: newPlayer, error: playerError } = await client
      .from('players')
      .insert(playerInsert)
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

    // Send push notification to the bookie (fire-and-forget)
    if (bookieRecord?.auth_user_id) {
      try {
        await sendNotification({
          event: 'new_member',
          recipientUserIds: [bookieRecord.auth_user_id],
          title: 'New member',
          body: `${newPlayer.name} joined your group`,
          data: { deep_link: `booki://members/${newPlayer.id}` },
        });
      } catch (notifError) {
        console.error('Failed to send new member notification:', notifError);
      }
    }

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
