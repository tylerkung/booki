import { corsHeaders } from '../_shared/cors.ts';
import { createServiceClient, getUserIdFromAuthHeader } from '../_shared/supabase.ts';

Deno.serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // Validate JWT auth
    const authHeader = req.headers.get('Authorization');
    const userId = await getUserIdFromAuthHeader(authHeader);

    if (!userId) {
      return new Response(
        JSON.stringify({ success: false, error: 'Unauthorized' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const client = createServiceClient();

    // Look up bookie record for the authenticated user
    const { data: bookie, error: bookieError } = await client
      .from('bookies')
      .select('id')
      .eq('auth_user_id', userId)
      .single();

    if (bookieError || !bookie) {
      return new Response(
        JSON.stringify({ success: false, error: 'No organizer record found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const bookieId = bookie.id;

    // Count active players (auth_user_id IS NOT NULL means claimed/active)
    const { count: memberCount } = await client
      .from('players')
      .select('*', { count: 'exact', head: true })
      .eq('bookie_id', bookieId)
      .not('auth_user_id', 'is', null);

    // Count open invites (unclaimed, not expired)
    const { count: inviteCount } = await client
      .from('invites')
      .select('*', { count: 'exact', head: true })
      .eq('bookie_id', bookieId)
      .is('claimed_by', null)
      .gt('expires_at', new Date().toISOString());

    const activeMembers = memberCount ?? 0;
    const openInvites = inviteCount ?? 0;

    if (activeMembers > 0 || openInvites > 0) {
      return new Response(
        JSON.stringify({
          success: false,
          error: 'has_members_or_invites',
          members: activeMembers,
          invites: openInvites,
        }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Delete the bookie record
    const { error: deleteError } = await client
      .from('bookies')
      .delete()
      .eq('id', bookieId);

    if (deleteError) {
      console.error('Error deleting bookie record:', deleteError);
      return new Response(
        JSON.stringify({ success: false, error: 'Failed to remove organizer record' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    return new Response(
      JSON.stringify({ success: true }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (error) {
    console.error('Error in step_down_organizer:', error);
    return new Response(
      JSON.stringify({ success: false, error: error instanceof Error ? error.message : 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
