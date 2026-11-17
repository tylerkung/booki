import { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { getUserIdFromAuthHeader } from './supabase.ts';
import { allowInterimClaim, resolveClaimCaller } from './claim_caller.ts';

export type ClaimAuthUser = {
  id: string;
  email?: string | null;
  email_confirmed_at?: string | null;
  user_metadata?: Record<string, unknown> | null;
};

export type ClaimAuthorization =
  | { ok: true; userId: string; confirmEmail: boolean; user: ClaimAuthUser }
  | { ok: false; status: number; error: string };

/**
 * Derive the caller of claim_invite / claim_player from the Authorization
 * header. body.auth_user_id is not trusted on its own.
 *
 * confirmEmail is true only when the user JWT matches the account being
 * claimed. The interim (no user JWT) path never confirms email.
 */
export async function authorizeClaimRequest(
  client: SupabaseClient,
  authHeader: string | null,
  bodyUserId: unknown,
): Promise<ClaimAuthorization> {
  const jwtUserId = await getUserIdFromAuthHeader(authHeader);
  const resolved = resolveClaimCaller(jwtUserId, bodyUserId);
  if (!resolved.ok) {
    return resolved;
  }

  const { data: authUser, error: authError } = await client.auth.admin.getUserById(resolved.userId);
  if (authError || !authUser?.user) {
    return { ok: false, status: 400, error: 'Invalid auth_user_id' };
  }

  if (resolved.mode === 'interim') {
    const { data: books, error: bookError } = await client
      .from('bookies')
      .select('id')
      .eq('auth_user_id', resolved.userId)
      .limit(1);
    if (bookError) {
      console.error('claim auth organizer lookup failed:', bookError);
      return { ok: false, status: 500, error: 'Failed to verify account status' };
    }
    const interim = allowInterimClaim({
      emailConfirmed: Boolean(authUser.user.email_confirmed_at),
      isOrganizer: (books?.length ?? 0) > 0,
    });
    if (!interim.ok) return interim;
  }

  return {
    ok: true,
    userId: resolved.userId,
    // A matching user JWT is the only request allowed to confirm the email.
    confirmEmail: resolved.mode === 'jwt',
    user: authUser.user,
  };
}
