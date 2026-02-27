import { corsHeaders } from '../_shared/cors.ts';
import { sendNotification } from '../_shared/notifications.ts';

interface SendNotificationRequest {
  event: string;
  recipient_user_ids: string[];
  title: string;
  body: string;
  data?: Record<string, string>;
}

Deno.serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // Note: Auth validation skipped — function deployed with --no-verify-jwt
    // and called internally by other edge functions. Supabase gateway handles routing.

    // Parse and validate request body
    const body: SendNotificationRequest = await req.json();

    if (!body.event || !body.recipient_user_ids || !body.title || !body.body) {
      return new Response(
        JSON.stringify({ success: false, error: 'Missing required fields: event, recipient_user_ids, title, body' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    if (!Array.isArray(body.recipient_user_ids) || body.recipient_user_ids.length === 0) {
      return new Response(
        JSON.stringify({ success: false, error: 'recipient_user_ids must be a non-empty array' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Send notifications
    const result = await sendNotification({
      event: body.event,
      recipientUserIds: body.recipient_user_ids,
      title: body.title,
      body: body.body,
      data: body.data,
    });

    return new Response(
      JSON.stringify({ success: true, sent: result.sent }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (err) {
    console.error('send_notification error:', err);
    return new Response(
      JSON.stringify({ success: false, error: 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
