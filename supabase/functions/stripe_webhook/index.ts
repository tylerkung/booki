import { corsHeaders } from '../_shared/cors.ts';
import { createServiceClient } from '../_shared/supabase.ts';
import { createHmac } from 'node:crypto';

/**
 * Verify Stripe webhook signature.
 * Compares the HMAC SHA256 signature from the stripe-signature header
 * against the computed signature of the raw request body.
 */
function verifyStripeSignature(
  payload: string,
  signatureHeader: string,
  secret: string,
  toleranceSeconds = 300
): boolean {
  const elements = signatureHeader.split(',');
  let timestamp: string | null = null;
  const signatures: string[] = [];

  for (const element of elements) {
    const [key, value] = element.split('=');
    if (key === 't') {
      timestamp = value;
    } else if (key === 'v1') {
      signatures.push(value);
    }
  }

  if (!timestamp || signatures.length === 0) {
    return false;
  }

  // Check timestamp tolerance to prevent replay attacks
  const timestampAge = Math.floor(Date.now() / 1000) - parseInt(timestamp, 10);
  if (timestampAge > toleranceSeconds) {
    return false;
  }

  // Compute expected signature
  const signedPayload = `${timestamp}.${payload}`;
  const expectedSignature = createHmac('sha256', secret)
    .update(signedPayload)
    .digest('hex');

  // Compare with provided signatures (timing-safe comparison)
  return signatures.some((sig) => {
    if (sig.length !== expectedSignature.length) return false;
    let result = 0;
    for (let i = 0; i < sig.length; i++) {
      result |= sig.charCodeAt(i) ^ expectedSignature.charCodeAt(i);
    }
    return result === 0;
  });
}

Deno.serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const webhookSecret = Deno.env.get('STRIPE_WEBHOOK_SECRET');

    if (!webhookSecret) {
      console.error('Missing STRIPE_WEBHOOK_SECRET environment variable');
      return new Response(
        JSON.stringify({ error: 'Webhook configuration error' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Read raw body for signature verification
    const rawBody = await req.text();

    // Verify webhook signature
    const signatureHeader = req.headers.get('stripe-signature');
    if (!signatureHeader) {
      return new Response(
        JSON.stringify({ error: 'Missing stripe-signature header' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const isValid = verifyStripeSignature(rawBody, signatureHeader, webhookSecret);
    if (!isValid) {
      console.error('Invalid Stripe webhook signature');
      return new Response(
        JSON.stringify({ error: 'Invalid signature' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const event = JSON.parse(rawBody);
    const client = createServiceClient();

    console.log(`Processing Stripe event: ${event.type} (${event.id})`);

    switch (event.type) {
      case 'checkout.session.completed': {
        const session = event.data.object;
        const bookieId = session.metadata?.bookie_id;
        const subscriptionId = session.subscription;

        if (!bookieId) {
          console.error('checkout.session.completed: Missing bookie_id in metadata');
          break;
        }

        if (!subscriptionId) {
          console.error('checkout.session.completed: Missing subscription ID');
          break;
        }

        // Update bookie to pro tier with subscription ID
        const { error: updateError } = await client
          .from('bookies')
          .update({
            tier: 'pro',
            stripe_subscription_id: subscriptionId,
          })
          .eq('id', bookieId);

        if (updateError) {
          console.error('checkout.session.completed: Failed to update bookie:', updateError);
        } else {
          console.log(`checkout.session.completed: Upgraded bookie ${bookieId} to pro`);
        }

        break;
      }

      case 'customer.subscription.deleted': {
        const subscription = event.data.object;
        const subscriptionId = subscription.id;

        // Look up bookie by stripe_subscription_id
        const { data: bookie, error: lookupError } = await client
          .from('bookies')
          .select('id')
          .eq('stripe_subscription_id', subscriptionId)
          .single();

        if (lookupError || !bookie) {
          console.error('customer.subscription.deleted: Bookie not found for subscription:', subscriptionId);
          break;
        }

        // Downgrade to free tier, clear subscription ID
        const { error: updateError } = await client
          .from('bookies')
          .update({
            tier: 'free',
            stripe_subscription_id: null,
          })
          .eq('id', bookie.id);

        if (updateError) {
          console.error('customer.subscription.deleted: Failed to update bookie:', updateError);
        } else {
          console.log(`customer.subscription.deleted: Downgraded bookie ${bookie.id} to free`);
        }

        break;
      }

      case 'invoice.payment_failed': {
        const invoice = event.data.object;
        const customerId = invoice.customer;

        if (!customerId) {
          console.error('invoice.payment_failed: Missing customer ID');
          break;
        }

        // Look up bookie by stripe_customer_id
        const { data: bookie, error: lookupError } = await client
          .from('bookies')
          .select('id, tier')
          .eq('stripe_customer_id', customerId)
          .single();

        if (lookupError || !bookie) {
          console.error('invoice.payment_failed: Bookie not found for customer:', customerId);
          break;
        }

        // Downgrade to free on payment failure
        const { error: updateError } = await client
          .from('bookies')
          .update({ tier: 'free' })
          .eq('id', bookie.id);

        if (updateError) {
          console.error('invoice.payment_failed: Failed to update bookie:', updateError);
        } else {
          console.log(`invoice.payment_failed: Downgraded bookie ${bookie.id} to free`);
        }

        break;
      }

      default:
        console.log(`Unhandled Stripe event type: ${event.type}`);
    }

    return new Response(
      JSON.stringify({ received: true }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (error) {
    console.error('Error in stripe_webhook:', error);
    return new Response(
      JSON.stringify({ error: error instanceof Error ? error.message : 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
