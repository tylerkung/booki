import { corsHeaders } from '../_shared/cors.ts';
import { createServiceClient, getUserIdFromAuthHeader } from '../_shared/supabase.ts';

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

    console.log(`delete_account: userId=${userId}`);

    // Look up bookie record (if user is a bookie)
    const { data: bookie } = await client
      .from('bookies')
      .select('id, stripe_customer_id, stripe_subscription_id')
      .eq('auth_user_id', userId)
      .single();

    // If bookie has an active Stripe subscription, cancel it
    if (bookie?.stripe_subscription_id) {
      const stripeSecretKey = Deno.env.get('STRIPE_SECRET_KEY');
      if (stripeSecretKey) {
        try {
          const cancelResponse = await fetch(
            `https://api.stripe.com/v1/subscriptions/${bookie.stripe_subscription_id}`,
            {
              method: 'DELETE',
              headers: {
                'Authorization': `Bearer ${stripeSecretKey}`,
              },
            }
          );
          if (cancelResponse.ok) {
            console.log(`delete_account: Canceled Stripe subscription ${bookie.stripe_subscription_id}`);
          } else {
            const err = await cancelResponse.json();
            console.error('delete_account: Failed to cancel Stripe subscription:', err);
          }
        } catch (stripeErr) {
          console.error('delete_account: Stripe cancellation error:', stripeErr);
          // Continue with deletion even if Stripe cancel fails
        }
      }
    }

    // Delete user data in order (respecting foreign key constraints)

    if (bookie) {
      // Delete ledger entries for this bookie
      await client.from('ledger_entries').delete().eq('bookie_id', bookie.id);

      // Delete bets for this bookie
      await client.from('bets').delete().eq('bookie_id', bookie.id);

      // Delete audit events for this bookie
      await client.from('audit_events').delete().eq('bookie_id', bookie.id);

      // Delete settlement events for this bookie
      await client.from('settlement_events').delete().eq('bookie_id', bookie.id);

      // Delete invites for this bookie
      await client.from('invites').delete().eq('bookie_id', bookie.id);

      // Delete players for this bookie
      await client.from('players').delete().eq('bookie_id', bookie.id);

      // Delete the bookie record itself
      await client.from('bookies').delete().eq('id', bookie.id);

      console.log(`delete_account: Deleted bookie data for ${bookie.id}`);
    }

    // Check if user is a player (claimed account)
    const { data: playerRecords } = await client
      .from('players')
      .select('id')
      .eq('auth_user_id', userId);

    if (playerRecords && playerRecords.length > 0) {
      for (const player of playerRecords) {
        // Null out auth_user_id to unlink (preserves bookie's historical data)
        await client
          .from('players')
          .update({ auth_user_id: null })
          .eq('id', player.id);
      }
      console.log(`delete_account: Unlinked ${playerRecords.length} player record(s)`);
    }

    // Delete the auth user (this is permanent)
    const { error: deleteError } = await client.auth.admin.deleteUser(userId);

    if (deleteError) {
      console.error('delete_account: Failed to delete auth user:', deleteError);
      return new Response(
        JSON.stringify({ success: false, error: 'Failed to delete account' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    console.log(`delete_account: Successfully deleted auth user ${userId}`);

    return new Response(
      JSON.stringify({ success: true }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (error) {
    console.error('Error in delete_account:', error);
    return new Response(
      JSON.stringify({ success: false, error: error instanceof Error ? error.message : 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
