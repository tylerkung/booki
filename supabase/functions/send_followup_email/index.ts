import { corsHeaders } from '../_shared/cors.ts';
import { createServiceClient } from '../_shared/supabase.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const EMAIL_TYPE = 'invite_followup';

// Kill switch. While true, the daily cron run is a no-op — nothing is sent and
// no lifecycle_emails rows are written, so nobody is burned while sends are
// paused. A manual call with {"force": true} still sends, for testing.
//
// PAUSED until the invite flow is verified end to end. There is no point
// telling 12 dormant organizers to go create an invite if invites are broken.
// To resume: flip to false and redeploy.
const PAUSED = true;

interface DormantOrganizer {
  bookie_id: string;
  auth_user_id: string;
  name: string | null;
  email: string | null;
  created_at: string;
  /** Invites this organizer has ever created. >0 means they tried and it failed. */
  invites_created?: number;
  last_invite_at?: string | null;
}

function getFollowupEmailHtml(name: string, invitesCreated = 0): string {
  // Someone who already created an invite does not need to be told how. Their
  // invites expired unclaimed because the flow was broken, not because they
  // lost interest — every web invite created between 21 Mar and 17 Aug 2026
  // failed that way. Saying "you haven't invited anyone yet" to that person is
  // both wrong and insulting.
  const tried = invitesCreated > 0;
  const opener = tried
    ? `I can see you sent ${invitesCreated === 1 ? 'an invite' : `${invitesCreated} invites`} and nobody landed. That was almost certainly us — invites created before 17 August hit a bug where the code never showed up properly and the invite page loaded unstyled. Both are fixed now, and any link from back then has expired.`
    : `I noticed you set up your organizer account but haven't invited anyone yet. Booki doesn't do much until your group is in it — and getting them there takes about a minute.`;
  const howLabel = tried ? 'Worth Another Go' : 'How To Invite';
  const headline = tried
    ? `That invite didn't work, ${name}`
    : `Still just you in there, ${name}`;
  const ctaLabel = tried ? 'Send Another Invite' : 'Invite Your First Member';
  // The steps describe the invite modal, which now asks which kind of invite
  // you want before anything else. Copy that still says "email (optional)" is
  // describing a form that no longer exists.
  const step2 = tried
    ? 'Pick <strong style="color: #F8F8F8;">Send an email</strong> — it goes straight to them and only they can use it'
    : 'Choose <strong style="color: #F8F8F8;">Send an email</strong>, or <strong style="color: #F8F8F8;">Create a link</strong> to paste in your group chat';
  const step3 = tried
    ? 'Links now last a week instead of a day, so nobody misses the window'
    : 'An emailed invite never expires for them; a shared link lasts a week';
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Your book is still empty</title>
</head>
<body style="margin: 0; padding: 0; background-color: #0A0A12; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color: #0A0A12; min-height: 100vh;">
    <tr>
      <td align="center" style="padding: 40px 16px;">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width: 480px;">
          <tr>
            <td align="center" style="padding-bottom: 32px;">
              <img src="https://bookisports.com/assets/logo-booki-wh.png" alt="Booki" width="140" style="display: block;" />
            </td>
          </tr>
          <tr>
            <td style="background-color: #14141F; border-radius: 16px; border: 1px solid #2A2A3A; padding: 40px 32px;">
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
                <tr>
                  <td align="center" style="padding-bottom: 12px;">
                    <h1 style="margin: 0; font-size: 24px; font-weight: 700; color: #F8F8F8; letter-spacing: -0.3px;">
                      ${headline}
                    </h1>
                  </td>
                </tr>
                <tr>
                  <td align="center" style="padding-bottom: 28px;">
                    <p style="margin: 0; font-size: 15px; line-height: 1.6; color: #A8A8B8;">
                      ${opener}
                    </p>
                  </td>
                </tr>
                <tr>
                  <td style="padding-bottom: 28px;">
                    <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
                      <tr>
                        <td style="background-color: #0A0A12; border: 1px solid #2A2A3A; border-radius: 10px; padding: 20px;">
                          <p style="margin: 0 0 14px; font-size: 13px; text-transform: uppercase; letter-spacing: 1.5px; color: #6B6B7B; font-weight: 600;">${howLabel}</p>
                          <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
                            <tr><td style="padding-bottom: 12px;"><p style="margin: 0; font-size: 14px; color: #F8F8F8;"><span style="color: #00F5D4; font-weight: 700;">1.</span>&nbsp; Open the <strong style="color: #F8F8F8;">Members</strong> tab and hit <strong style="color: #F8F8F8;">+ Invite</strong></p></td></tr>
                            <tr><td style="padding-bottom: 12px;"><p style="margin: 0; font-size: 14px; color: #F8F8F8;"><span style="color: #00F5D4; font-weight: 700;">2.</span>&nbsp; ${step2}</p></td></tr>
                            <tr><td><p style="margin: 0; font-size: 14px; color: #F8F8F8;"><span style="color: #00F5D4; font-weight: 700;">3.</span>&nbsp; ${step3}</p></td></tr>
                          </table>
                        </td>
                      </tr>
                    </table>
                  </td>
                </tr>
                <tr>
                  <td align="center" style="padding-bottom: 24px;">
                    <p style="margin: 0; font-size: 14px; line-height: 1.6; color: #A8A8B8;">
                      Once they're in, they browse games and place picks on their own. Everything grades automatically and you settle up with one tap.
                    </p>
                  </td>
                </tr>
                <tr>
                  <td align="center" style="padding-bottom: 24px;">
                    <a href="https://bookisports.com/dashboard/#/members" style="display: inline-block; background-color: #00F5D4; color: #0A0A12; font-size: 16px; font-weight: 700; text-decoration: none; padding: 16px 40px; border-radius: 10px; letter-spacing: 0.5px;">${ctaLabel}</a>
                  </td>
                </tr>
                <tr>
                  <td style="padding-bottom: 24px;">
                    <p style="margin: 0 0 10px; font-size: 13px; text-transform: uppercase; letter-spacing: 1.5px; color: #6B6B7B; font-weight: 600;">If you'd rather read first</p>
                    <p style="margin: 0 0 6px; font-size: 14px; line-height: 1.6;"><a href="https://bookisports.com/help/how-to-run-your-group.html" style="color: #00F5D4; text-decoration: none;">How to run your group</a><span style="color: #6B6B7B;"> &mdash; the whole loop in one page</span></p>
                    <p style="margin: 0 0 6px; font-size: 14px; line-height: 1.6;"><a href="https://bookisports.com/help/credit-and-win-limits.html" style="color: #00F5D4; text-decoration: none;">Credit and win limits</a><span style="color: #6B6B7B;"> &mdash; how you cap what a member can risk</span></p>
                    <p style="margin: 0; font-size: 14px; line-height: 1.6;"><a href="https://bookisports.com/help/settling-up.html" style="color: #00F5D4; text-decoration: none;">Settling up</a><span style="color: #6B6B7B;"> &mdash; you handle the money, Booki keeps the record</span></p>
                  </td>
                </tr>
                <tr>
                  <td style="padding: 20px 0;"><div style="height: 1px; background-color: #2A2A3A;"></div></td>
                </tr>
                <tr>
                  <td>
                    <p style="margin: 0; font-size: 14px; line-height: 1.7; color: #A8A8B8;">If something's holding you up — a question about <a href="https://bookisports.com/help/credit-and-win-limits.html" style="color: #00F5D4; text-decoration: none;">how credit limits work</a>, whether this fits how your group already does things, or anything else — just reply to this email and ask. It comes straight to me.</p>
                    <p style="margin: 16px 0 0; font-size: 14px; line-height: 1.7; color: #A8A8B8;">And if you tried it and it wasn't what you expected, I'd genuinely like to hear that too. That feedback is the most useful thing I get.</p>
                    <p style="margin: 16px 0 0; font-size: 14px; color: #F8F8F8; font-weight: 600;">— Tyler</p>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
          <tr>
            <td align="center" style="padding-top: 32px;">
              <p style="margin: 0; font-size: 12px; color: #4A4A5A;">
                <a href="https://bookisports.com" style="color: #4A4A5A; text-decoration: none;">bookisports.com</a>
                &nbsp;&middot;&nbsp;
                <a href="https://bookisports.com/terms.html" style="color: #4A4A5A; text-decoration: none;">Terms</a>
                &nbsp;&middot;&nbsp;
                <a href="https://bookisports.com/privacy.html" style="color: #4A4A5A; text-decoration: none;">Privacy</a>
              </p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;
}

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // Only a service-role caller (the cron job) may trigger a batch send.
    // Rather than string-matching a platform key — the value injected into the
    // runtime and the key the API gateway accepts are not guaranteed to be the
    // same string — probe whether the caller's token actually carries
    // service-role privileges. auth.admin is service-role only.
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const token = req.headers.get('Authorization')?.replace('Bearer ', '').trim();
    if (!supabaseUrl || !token) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const callerClient = createClient(supabaseUrl, token, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const { error: probeError } = await callerClient.auth.admin.listUsers({ page: 1, perPage: 1 });
    if (probeError) {
      console.warn('Rejected non-service-role caller:', probeError.message);
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    let body: Record<string, unknown> = {};
    try {
      body = await req.json();
    } catch {
      // No body — use defaults
    }

    const minAgeDays = typeof body.min_age_days === 'number' ? body.min_age_days : 10;
    const limit = typeof body.limit === 'number' ? body.limit : 50;
    const dryRun = body.dry_run === true;
    const force = body.force === true;

    // Paused: the cron still fires but does nothing. Returns 200 so the run is
    // not logged as a failure. Dry runs and {"force": true} still work.
    if (PAUSED && !force && !dryRun) {
      console.log('send_followup_email: PAUSED — no emails sent');
      return new Response(
        JSON.stringify({ success: true, paused: true, sent: 0 }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const resendApiKey = Deno.env.get('RESEND_API_KEY');
    if (!resendApiKey && !dryRun) {
      return new Response(JSON.stringify({ error: 'Email service not configured' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const client = createServiceClient();

    // Organizers with no invites, no members, and no prior follow-up
    const { data: candidates, error: queryError } = await client.rpc('get_dormant_organizers', {
      p_min_age_days: minAgeDays,
      p_email_type: EMAIL_TYPE,
      p_limit: limit,
    });

    if (queryError) {
      console.error('get_dormant_organizers error:', queryError);
      return new Response(JSON.stringify({ error: 'Query failed' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const organizers = (candidates ?? []) as DormantOrganizer[];
    let sent = 0;
    let skipped = 0;
    let failed = 0;

    for (const org of organizers) {
      // Prefer the bookie record's email, fall back to the auth user
      let email = org.email;
      if (!email) {
        const { data: userData } = await client.auth.admin.getUserById(org.auth_user_id);
        email = userData?.user?.email ?? null;
      }

      if (!email) {
        console.warn(`No email for bookie ${org.bookie_id} — skipping`);
        skipped++;
        continue;
      }

      const name = org.name || email.split('@')[0];

      if (dryRun) {
        console.log(
          `[dry_run] would send to ${email} (${name}) ` +
            `invites_created=${org.invites_created ?? 0}`,
        );
        sent++;
        continue;
      }

      const emailRes = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${resendApiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          from: 'Tyler from Booki <tyler@bookisports.com>',
          reply_to: 'tyler@bookisports.com',
          to: [email],
          subject: (org.invites_created ?? 0) > 0
            ? `That invite didn't work, ${name} — that was our fault`
            : `Still just you in there, ${name}`,
          html: getFollowupEmailHtml(name, org.invites_created ?? 0),
          headers: {
            'List-Unsubscribe': '<mailto:tyler@bookisports.com?subject=unsubscribe>',
            'List-Unsubscribe-Post': 'List-Unsubscribe=One-Click',
          },
        }),
      });

      if (!emailRes.ok) {
        const errBody = await emailRes.text();
        console.error(`Resend error for ${email}:`, errBody);
        failed++;
        // No ledger row — this organizer is retried on the next run
        continue;
      }

      const resendBody = await emailRes.json().catch(() => ({}));

      // Record the send so this organizer is never emailed twice
      const { error: insertError } = await client.from('lifecycle_emails').insert({
        auth_user_id: org.auth_user_id,
        email_type: EMAIL_TYPE,
        provider_message_id: resendBody?.id ?? null,
      });

      if (insertError) {
        console.error(`Failed to record send for ${org.auth_user_id}:`, insertError);
      }

      sent++;
      await sleep(250); // stay under Resend's rate limit
    }

    console.log(`send_followup_email: ${sent} sent, ${skipped} skipped, ${failed} failed (${organizers.length} candidates)`);

    return new Response(
      JSON.stringify({ success: true, candidates: organizers.length, sent, skipped, failed, dry_run: dryRun }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );

  } catch (err) {
    console.error('send_followup_email error:', err);
    return new Response(JSON.stringify({ error: 'Internal error' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
