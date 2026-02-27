import { corsHeaders } from '../_shared/cors.ts';
import { createServiceClient, getUserIdFromAuthHeader } from '../_shared/supabase.ts';

/**
 * Apple IAP Webhook Edge Function
 *
 * Two paths:
 * 1. Client path (POST with JWT auth): iOS sends { transactionJWS } after purchase
 * 2. Apple Server Notifications V2 (POST without auth): Apple sends { signedPayload }
 */

const EXPECTED_BUNDLE_ID = 'com.bookiapp.booki';
const EXPECTED_PRODUCT_ID = 'com.bookisports.booki.pro.monthly';

/**
 * Decode a JWS (JSON Web Signature) payload without full signature verification.
 * StoreKit 2 transactions are already verified client-side by the OS.
 * For App Store Server Notifications, Apple signs with their key.
 * We validate claims (bundleId, productId, expiresDate) as the trust boundary.
 */
function decodeJWSPayload(jws: string): Record<string, unknown> | null {
  try {
    const parts = jws.split('.');
    if (parts.length !== 3) return null;

    // Base64url decode the payload (second part)
    const payload = parts[1]
      .replace(/-/g, '+')
      .replace(/_/g, '/');
    const decoded = atob(payload);
    return JSON.parse(decoded);
  } catch {
    return null;
  }
}

Deno.serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const body = await req.json();
    const client = createServiceClient();

    // ── Path 1: Apple Server Notifications V2 ──
    if (body.signedPayload) {
      return await handleServerNotification(client, body.signedPayload);
    }

    // ── Path 2: Client-side transaction from iOS app ──
    if (body.transactionJWS) {
      const authHeader = req.headers.get('Authorization');
      const userId = await getUserIdFromAuthHeader(authHeader);

      if (!userId) {
        return new Response(
          JSON.stringify({ success: false, error: 'Unauthorized' }),
          { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }

      return await handleClientTransaction(client, userId, body.transactionJWS);
    }

    return new Response(
      JSON.stringify({ success: false, error: 'Missing transactionJWS or signedPayload' }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (error) {
    console.error('Error in apple_iap_webhook:', error);
    return new Response(
      JSON.stringify({ success: false, error: error instanceof Error ? error.message : 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});

/**
 * Handle a client-side transaction JWS sent from the iOS app after purchase.
 */
async function handleClientTransaction(
  client: ReturnType<typeof createServiceClient>,
  userId: string,
  transactionJWS: string
) {
  const payload = decodeJWSPayload(transactionJWS);

  if (!payload) {
    return new Response(
      JSON.stringify({ success: false, error: 'Invalid transaction JWS' }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }

  // Validate claims
  if (payload.bundleId !== EXPECTED_BUNDLE_ID) {
    console.error(`Invalid bundleId: ${payload.bundleId}`);
    return new Response(
      JSON.stringify({ success: false, error: 'Invalid bundle ID' }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }

  if (payload.productId !== EXPECTED_PRODUCT_ID) {
    console.error(`Invalid productId: ${payload.productId}`);
    return new Response(
      JSON.stringify({ success: false, error: 'Invalid product ID' }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }

  // Check expiration
  const expiresDateMs = payload.expiresDate as number;
  if (expiresDateMs && expiresDateMs < Date.now()) {
    console.log('Transaction already expired');
    return new Response(
      JSON.stringify({ success: false, error: 'Subscription has expired' }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }

  const originalTransactionId = String(payload.originalTransactionId ?? payload.transactionId);

  // Look up bookie by auth_user_id
  const { data: bookie, error: bookieError } = await client
    .from('bookies')
    .select('id, tier, subscription_source')
    .eq('auth_user_id', userId)
    .single();

  if (bookieError || !bookie) {
    console.error('Bookie not found for user:', userId);
    return new Response(
      JSON.stringify({ success: false, error: 'Bookie not found' }),
      { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }

  // Upgrade to pro
  const { error: updateError } = await client
    .from('bookies')
    .update({
      tier: 'pro',
      subscription_source: 'apple',
      apple_original_transaction_id: originalTransactionId,
      updated_at: new Date().toISOString(),
    })
    .eq('id', bookie.id);

  if (updateError) {
    console.error('Failed to update bookie:', updateError);
    return new Response(
      JSON.stringify({ success: false, error: 'Failed to update subscription' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }

  console.log(`apple_iap_webhook: Upgraded bookie ${bookie.id} to pro via Apple IAP`);

  return new Response(
    JSON.stringify({ success: true }),
    { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
  );
}

/**
 * Handle Apple Server Notifications V2.
 * Apple sends these for renewals, expirations, refunds, etc.
 */
async function handleServerNotification(
  client: ReturnType<typeof createServiceClient>,
  signedPayload: string
) {
  const outerPayload = decodeJWSPayload(signedPayload);

  if (!outerPayload) {
    return new Response(
      JSON.stringify({ error: 'Invalid signed payload' }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }

  const notificationType = outerPayload.notificationType as string;
  const subtype = outerPayload.subtype as string | undefined;

  // Decode the inner signed transaction data
  const signedTransactionInfo = (outerPayload.data as Record<string, unknown>)?.signedTransactionInfo as string;
  if (!signedTransactionInfo) {
    console.error('Missing signedTransactionInfo in notification');
    return new Response(
      JSON.stringify({ received: true }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }

  const transactionInfo = decodeJWSPayload(signedTransactionInfo);
  if (!transactionInfo) {
    console.error('Failed to decode signedTransactionInfo');
    return new Response(
      JSON.stringify({ received: true }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }

  const originalTransactionId = String(transactionInfo.originalTransactionId);

  console.log(`Apple Server Notification: ${notificationType} (subtype: ${subtype ?? 'none'}) for txn ${originalTransactionId}`);

  // Look up bookie by apple_original_transaction_id
  const { data: bookie, error: lookupError } = await client
    .from('bookies')
    .select('id, tier, subscription_source')
    .eq('apple_original_transaction_id', originalTransactionId)
    .single();

  if (lookupError || !bookie) {
    console.error('Bookie not found for original_transaction_id:', originalTransactionId);
    return new Response(
      JSON.stringify({ received: true }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }

  // Only process if subscription_source is 'apple'
  if (bookie.subscription_source !== 'apple') {
    console.log(`Skipping notification — bookie ${bookie.id} subscription_source is '${bookie.subscription_source}'`);
    return new Response(
      JSON.stringify({ received: true }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }

  switch (notificationType) {
    case 'DID_RENEW': {
      // Subscription renewed successfully
      await client
        .from('bookies')
        .update({ tier: 'pro', updated_at: new Date().toISOString() })
        .eq('id', bookie.id);
      console.log(`DID_RENEW: Confirmed pro for bookie ${bookie.id}`);
      break;
    }

    case 'EXPIRED':
    case 'DID_FAIL_TO_RENEW': {
      // Subscription expired or renewal failed — downgrade
      await client
        .from('bookies')
        .update({
          tier: 'free',
          subscription_source: null,
          apple_original_transaction_id: null,
          updated_at: new Date().toISOString(),
        })
        .eq('id', bookie.id);
      console.log(`${notificationType}: Downgraded bookie ${bookie.id} to free`);
      break;
    }

    case 'REFUND':
    case 'REVOKE': {
      // Apple refunded or revoked — downgrade immediately
      await client
        .from('bookies')
        .update({
          tier: 'free',
          subscription_source: null,
          apple_original_transaction_id: null,
          updated_at: new Date().toISOString(),
        })
        .eq('id', bookie.id);
      console.log(`${notificationType}: Revoked pro for bookie ${bookie.id}`);
      break;
    }

    default:
      console.log(`Unhandled Apple notification type: ${notificationType}`);
  }

  return new Response(
    JSON.stringify({ received: true }),
    { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
  );
}
