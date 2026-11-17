// Who a claim_invite / claim_player request is allowed to act as.
//
// Both functions run with the service role and used to trust body.auth_user_id,
// so anyone who knew a user id could join a group as that person, spend their
// invite, confirm their email, or attach an organizer's login to a player row.
//
// The decision is pure so it can be tested without Deno or a database.
// claim_auth.ts does the JWT lookup and the bookies read, then calls these.

export const CLAIM_AUTH_MISMATCH = 'auth_user_id does not match the signed-in user';
export const CLAIM_AUTH_REQUIRED = 'Authentication required';

export type ClaimCallerResolution =
  | { ok: false; status: 401 | 403; error: string }
  | { ok: true; userId: string; mode: 'jwt' | 'interim' };

/**
 * Pick the account this request may act as.
 *
 * A user JWT wins. If the body also names an id, it must be that same user
 * (comparison is case-insensitive) or the request is rejected — a signed-in
 * caller does not get to name someone else.
 *
 * No user JWT (missing header, the anon key, or a token getUser() rejects):
 * the body id is only a candidate. allowInterimClaim still has to agree.
 */
export function resolveClaimCaller(
  jwtUserId: string | null | undefined,
  bodyUserId: unknown,
): ClaimCallerResolution {
  const jwt = normalizeUserId(jwtUserId);
  const body = normalizeUserId(bodyUserId);

  if (jwt && body && jwt !== body) {
    return { ok: false, status: 403, error: CLAIM_AUTH_MISMATCH };
  }
  if (jwt) {
    return { ok: true, userId: jwt, mode: 'jwt' };
  }
  if (!body) {
    return { ok: false, status: 401, error: CLAIM_AUTH_REQUIRED };
  }
  return { ok: true, userId: body, mode: 'interim' };
}

/**
 * The iOS signup claim still posts the anon key and a body id, because that
 * build has no user JWT yet. Allow that only for an account that has not
 * confirmed its email and does not organize a group. Confirmed accounts and
 * organizers require a matching user JWT. The caller must not confirm email
 * on this path — only mode 'jwt' may.
 */
export function allowInterimClaim(account: {
  emailConfirmed: boolean;
  isOrganizer: boolean;
}): { ok: true } | { ok: false; status: 401; error: string } {
  if (account.emailConfirmed || account.isOrganizer) {
    return { ok: false, status: 401, error: CLAIM_AUTH_REQUIRED };
  }
  return { ok: true };
}

function normalizeUserId(id: unknown): string | null {
  if (typeof id !== 'string') return null;
  const trimmed = id.trim().toLowerCase();
  return trimmed.length > 0 ? trimmed : null;
}
