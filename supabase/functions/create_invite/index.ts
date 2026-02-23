import { corsHeaders } from '../_shared/cors.ts';
import { createServiceClient, getUserIdFromAuthHeader } from '../_shared/supabase.ts';
import { checkIdempotency, storeIdempotency } from '../_shared/idempotency.ts';
import { emitAuditEvent } from '../_shared/audit.ts';

interface CreateInviteRequest {
  email?: string;
  idempotency_key: string;
}

// Charset: A-Z (excluding O, I, L) + 2-9 (excluding 0, 1)
const INVITE_CODE_CHARSET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
const INVITE_CODE_LENGTH = 8;
const INVITE_EXPIRY_HOURS = 24;
const MAX_CODE_RETRIES = 5;

function generateInviteCode(): string {
  const bytes = new Uint8Array(INVITE_CODE_LENGTH);
  crypto.getRandomValues(bytes);
  let code = '';
  for (let i = 0; i < INVITE_CODE_LENGTH; i++) {
    code += INVITE_CODE_CHARSET[bytes[i] % INVITE_CODE_CHARSET.length];
  }
  return code;
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
    const body: CreateInviteRequest = await req.json();

    // Validate idempotency key
    if (!body.idempotency_key) {
      return new Response(
        JSON.stringify({ success: false, error: 'Missing required field: idempotency_key' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const client = createServiceClient();

    // Check idempotency - if key exists, return cached response
    const cachedResponse = await checkIdempotency(client, body.idempotency_key, 'create_invite');
    if (cachedResponse) {
      return new Response(
        cachedResponse,
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Validate caller is a bookie
    const { data: bookie, error: bookieError } = await client
      .from('bookies')
      .select('id')
      .eq('auth_user_id', userId)
      .single();

    if (bookieError || !bookie) {
      return new Response(
        JSON.stringify({ success: false, error: 'Only bookies can create invites' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const bookieId = bookie.id;

    // Generate unique invite code with collision retry
    let inviteCode = '';
    let codeIsUnique = false;

    for (let attempt = 0; attempt < MAX_CODE_RETRIES; attempt++) {
      inviteCode = generateInviteCode();

      const { data: existing } = await client
        .from('invites')
        .select('id')
        .eq('invite_code', inviteCode)
        .single();

      if (!existing) {
        codeIsUnique = true;
        break;
      }
    }

    if (!codeIsUnique) {
      return new Response(
        JSON.stringify({ success: false, error: 'Failed to generate unique invite code. Please try again.' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Calculate expiration (24 hours from now)
    const expiresAt = new Date(Date.now() + INVITE_EXPIRY_HOURS * 60 * 60 * 1000).toISOString();

    // Insert invite record
    const { data: invite, error: insertError } = await client
      .from('invites')
      .insert({
        bookie_id: bookieId,
        invite_code: inviteCode,
        email: body.email ?? null,
        expires_at: expiresAt,
      })
      .select()
      .single();

    if (insertError || !invite) {
      console.error('Error inserting invite:', insertError);
      return new Response(
        JSON.stringify({ success: false, error: 'Failed to create invite' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Emit audit event
    await emitAuditEvent(client, {
      bookieId: bookieId,
      actorUserId: userId,
      entityType: 'invite',
      entityId: invite.id,
      actionType: 'invite_created',
      previousState: null,
      newState: invite as unknown as Record<string, unknown>,
    });

    // Prepare success response
    const response = JSON.stringify({
      success: true,
      invite_id: invite.id,
      invite_code: inviteCode,
      invite_url: `booki://invite/${inviteCode}`,
      expires_at: expiresAt,
    });

    // Store idempotency key with response
    await storeIdempotency(client, body.idempotency_key, 'create_invite', userId, response);

    return new Response(
      response,
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (error) {
    console.error('Error in create_invite:', error);
    return new Response(
      JSON.stringify({ success: false, error: error instanceof Error ? error.message : 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
