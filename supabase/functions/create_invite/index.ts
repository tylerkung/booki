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
const MAX_OPEN_INVITES = 5;
const MEMBER_LIMIT_FREE = 3;
const MEMBER_LIMIT_PRO = 50;

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
      .select('id, tier')
      .eq('auth_user_id', userId)
      .single();

    if (bookieError || !bookie) {
      return new Response(
        JSON.stringify({ success: false, error: 'Only bookies can create invites' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const bookieId = bookie.id;

    // Check open invite limit
    const { count: openInviteCount } = await client
      .from('invites')
      .select('*', { count: 'exact', head: true })
      .eq('bookie_id', bookieId)
      .is('claimed_by', null)
      .gt('expires_at', new Date().toISOString());

    if ((openInviteCount ?? 0) >= MAX_OPEN_INVITES) {
      return new Response(
        JSON.stringify({ success: false, error: `You can have at most ${MAX_OPEN_INVITES} open invites at a time` }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Check tier-based member limit
    const bookieTier = bookie.tier ?? 'free';
    const memberLimit = bookieTier === 'pro' ? MEMBER_LIMIT_PRO : MEMBER_LIMIT_FREE;

    const { count: playerCount } = await client
      .from('players')
      .select('*', { count: 'exact', head: true })
      .eq('bookie_id', bookieId)
      .not('auth_user_id', 'is', null);

    if ((playerCount ?? 0) >= memberLimit) {
      return new Response(
        JSON.stringify({ success: false, error: 'member_limit_reached', limit: memberLimit, current: playerCount ?? 0 }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

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

    // Send invite email via Resend if email provided
    if (body.email) {
      const resendApiKey = Deno.env.get('RESEND_API_KEY');
      if (resendApiKey) {
        // Fetch bookie name for the email
        const { data: bookieRecord } = await client
          .from('bookies')
          .select('name')
          .eq('id', bookieId)
          .single();
        const bookieName = bookieRecord?.name || 'Your organizer';

        try {
          await fetch('https://api.resend.com/emails', {
            method: 'POST',
            headers: {
              'Authorization': `Bearer ${resendApiKey}`,
              'Content-Type': 'application/json',
            },
            body: JSON.stringify({
              from: 'Booki <noreply@bookisports.com>',
              to: [body.email],
              subject: `${bookieName} invited you to join Booki`,
              html: getInviteEmailHtml(bookieName, inviteCode),
            }),
          });
        } catch (emailError) {
          // Non-blocking — invite still created even if email fails
          console.error('Failed to send invite email:', emailError);
        }
      }
    }

    // Prepare success response
    const response = JSON.stringify({
      success: true,
      invite_id: invite.id,
      invite_code: inviteCode,
      invite_url: `https://bookisports.com/invite/${inviteCode}`,
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

function getInviteEmailHtml(bookieName: string, inviteCode: string): string {
  return `<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"></head>
<body style="margin:0;padding:0;background-color:#0A0A12;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color:#0A0A12;min-height:100vh;">
<tr><td align="center" style="padding:40px 16px;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:480px;">
<tr><td align="center" style="padding-bottom:32px;">
  <img src="https://bookisports.com/assets/logo-booki-wh.png" alt="Booki" width="140" style="display:block;" />
</td></tr>
<tr><td style="background-color:#14141F;border-radius:16px;border:1px solid #2A2A3A;padding:40px 32px;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0">
<tr><td align="center" style="padding-bottom:12px;">
  <h1 style="margin:0;font-size:24px;font-weight:700;color:#F8F8F8;letter-spacing:-0.3px;">You're Invited</h1>
</td></tr>
<tr><td align="center" style="padding-bottom:28px;">
  <p style="margin:0;font-size:15px;line-height:1.6;color:#A8A8B8;">
    <strong style="color:#F8F8F8;">${escapeHtml(bookieName)}</strong> invited you to join their group on Booki.
  </p>
</td></tr>
<tr><td align="center" style="padding-bottom:28px;">
  <table role="presentation" cellpadding="0" cellspacing="0"><tr>
    <td style="background-color:#0A0A12;border:1px solid #2A2A3A;border-radius:10px;padding:16px 32px;text-align:center;">
      <p style="margin:0 0 4px;font-size:11px;text-transform:uppercase;letter-spacing:1.5px;color:#6B6B7B;font-weight:600;">Your Invite Code</p>
      <p style="margin:0;font-size:28px;font-weight:700;color:#00F5D4;letter-spacing:4px;font-family:'SF Mono','Menlo','Courier New',monospace;">${inviteCode}</p>
    </td>
  </tr></table>
</td></tr>
<tr><td align="center" style="padding-bottom:24px;">
  <a href="https://bookisports.com/invite/${inviteCode}" style="display:inline-block;background-color:#00F5D4;color:#0A0A12;font-size:16px;font-weight:700;text-decoration:none;padding:16px 40px;border-radius:10px;letter-spacing:0.5px;text-transform:uppercase;">Join Now</a>
</td></tr>
<tr><td align="center" style="padding-bottom:8px;">
  <p style="margin:0;font-size:13px;line-height:1.6;color:#6B6B7B;">Already have Booki? Open the app and enter the code above.</p>
</td></tr>
<tr><td style="padding:20px 0;"><div style="height:1px;background-color:#2A2A3A;"></div></td></tr>
<tr><td align="center">
  <p style="margin:0;font-size:12px;color:#6B6B7B;">This invite expires in 24 hours.</p>
</td></tr>
</table>
</td></tr>
<tr><td align="center" style="padding-top:32px;">
  <p style="margin:0 0 8px;font-size:13px;color:#6B6B7B;">If you weren't expecting this invite, you can safely ignore this email.</p>
  <p style="margin:0;font-size:12px;color:#4A4A5A;">
    <a href="https://bookisports.com" style="color:#4A4A5A;text-decoration:none;">bookisports.com</a>
    &nbsp;&middot;&nbsp;
    <a href="https://bookisports.com/terms.html" style="color:#4A4A5A;text-decoration:none;">Terms</a>
    &nbsp;&middot;&nbsp;
    <a href="https://bookisports.com/privacy.html" style="color:#4A4A5A;text-decoration:none;">Privacy</a>
  </p>
</td></tr>
</table>
</td></tr>
</table>
</body></html>`;
}

function escapeHtml(str: string): string {
  return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}
