import { corsHeaders } from '../_shared/cors.ts';
import { createServiceClient, getUserIdFromAuthHeader } from '../_shared/supabase.ts';

interface CheckoutRequest {
  success_url?: string;
  cancel_url?: string;
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

    const client = createServiceClient();

    console.log(`create_checkout_session: userId=${userId}`);

    // Look up bookie record
    const { data: bookie, error: bookieError } = await client
      .from('bookies')
      .select('id, stripe_customer_id, tier')
      .eq('auth_user_id', userId)
      .single();

    console.log(`create_checkout_session: bookie=${JSON.stringify(bookie)}, error=${JSON.stringify(bookieError)}`);

    if (bookieError || !bookie) {
      return new Response(
        JSON.stringify({ success: false, error: 'Bookie not found for current user' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const stripeSecretKey = Deno.env.get('STRIPE_SECRET_KEY');
    const stripePriceId = Deno.env.get('STRIPE_PRICE_ID');

    if (!stripeSecretKey || !stripePriceId) {
      console.error('Missing STRIPE_SECRET_KEY or STRIPE_PRICE_ID environment variables');
      return new Response(
        JSON.stringify({ success: false, error: 'Stripe configuration error' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Parse optional request body
    let body: CheckoutRequest = {};
    try {
      body = await req.json();
    } catch {
      // No body is fine, we use defaults
    }

    let stripeCustomerId = bookie.stripe_customer_id;

    // Create Stripe customer if one doesn't exist
    if (!stripeCustomerId) {
      // Get user email from auth
      const { data: { user }, error: userError } = await client.auth.admin.getUserById(userId);

      if (userError || !user) {
        return new Response(
          JSON.stringify({ success: false, error: 'Failed to look up user email' }),
          { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }

      const customerResponse = await fetch('https://api.stripe.com/v1/customers', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${stripeSecretKey}`,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: new URLSearchParams({
          email: user.email ?? '',
          'metadata[bookie_id]': bookie.id,
          'metadata[auth_user_id]': userId,
        }).toString(),
      });

      if (!customerResponse.ok) {
        const errorData = await customerResponse.json();
        console.error('Stripe customer creation failed:', errorData);
        return new Response(
          JSON.stringify({ success: false, error: 'Failed to create Stripe customer' }),
          { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }

      const customer = await customerResponse.json();
      stripeCustomerId = customer.id;

      // Save stripe_customer_id back to bookies table
      const { error: updateError } = await client
        .from('bookies')
        .update({ stripe_customer_id: stripeCustomerId })
        .eq('id', bookie.id);

      if (updateError) {
        console.error('Failed to save stripe_customer_id:', updateError);
        // Continue anyway - the customer was created in Stripe
      }
    }

    // Create Stripe Checkout Session
    const sessionResponse = await fetch('https://api.stripe.com/v1/checkout/sessions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${stripeSecretKey}`,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: new URLSearchParams({
        mode: 'subscription',
        customer: stripeCustomerId!,
        'line_items[0][price]': stripePriceId,
        'line_items[0][quantity]': '1',
        success_url: body.success_url ?? 'booki://checkout-success?session_id={CHECKOUT_SESSION_ID}',
        cancel_url: body.cancel_url ?? 'booki://checkout-cancel',
        'metadata[bookie_id]': bookie.id,
        'subscription_data[metadata][bookie_id]': bookie.id,
      }).toString(),
    });

    if (!sessionResponse.ok) {
      const errorData = await sessionResponse.json();
      console.error('Stripe checkout session creation failed:', errorData);
      return new Response(
        JSON.stringify({ success: false, error: 'Failed to create checkout session' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const session = await sessionResponse.json();

    return new Response(
      JSON.stringify({
        success: true,
        sessionId: session.id,
        url: session.url,
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (error) {
    console.error('Error in create_checkout_session:', error);
    return new Response(
      JSON.stringify({ success: false, error: error instanceof Error ? error.message : 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
