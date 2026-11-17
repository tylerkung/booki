import assert from 'node:assert/strict';
import fs from 'node:fs';
import {
  allowInterimClaim,
  resolveClaimCaller,
  CLAIM_AUTH_MISMATCH,
  CLAIM_AUTH_REQUIRED,
} from '../supabase/functions/_shared/claim_caller.ts';

const jwt = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
const other = '11111111-2222-3333-4444-555555555555';

assert.deepEqual(
  resolveClaimCaller(jwt, jwt),
  { ok: true, userId: jwt, mode: 'jwt' },
  'matching jwt and body',
);
assert.deepEqual(
  resolveClaimCaller(jwt.toUpperCase(), `  ${jwt}  `),
  { ok: true, userId: jwt, mode: 'jwt' },
  'uuid compare ignores case and surrounding space',
);
assert.deepEqual(
  resolveClaimCaller(jwt, null),
  { ok: true, userId: jwt, mode: 'jwt' },
  'jwt alone is enough',
);
assert.deepEqual(
  resolveClaimCaller(jwt, ''),
  { ok: true, userId: jwt, mode: 'jwt' },
  'blank body id is omitted, not a mismatch',
);

const mismatch = resolveClaimCaller(jwt, other);
assert.equal(mismatch.ok, false);
assert.equal(mismatch.status, 403);
assert.equal(mismatch.error, CLAIM_AUTH_MISMATCH);

const missing = resolveClaimCaller(null, undefined);
assert.equal(missing.ok, false);
assert.equal(missing.status, 401);
assert.equal(missing.error, CLAIM_AUTH_REQUIRED);

const interim = resolveClaimCaller(null, other);
assert.deepEqual(interim, { ok: true, userId: other, mode: 'interim' });

assert.deepEqual(allowInterimClaim({ emailConfirmed: false, isOrganizer: false }), { ok: true });

for (const account of [
  { emailConfirmed: true, isOrganizer: false },
  { emailConfirmed: false, isOrganizer: true },
  { emailConfirmed: true, isOrganizer: true },
]) {
  const denied = allowInterimClaim(account);
  assert.equal(denied.ok, false, JSON.stringify(account));
  assert.equal(denied.status, 401);
  assert.equal(denied.error, CLAIM_AUTH_REQUIRED);
}

// Both claim endpoints must use the helper, and email confirmation must be
// inside the matching-JWT branch. A second unconditional email_confirm would
// re-open the anon-key path.
for (const file of [
  'supabase/functions/claim_invite/index.ts',
  'supabase/functions/claim_player/index.ts',
]) {
  const src = fs.readFileSync(file, 'utf8');
  assert.match(src, /authorizeClaimRequest\(/, `${file} authorizes the caller`);
  assert.match(src, /caller\.confirmEmail && !/, `${file} confirms only for a matching JWT`);
  const confirms = src.split('email_confirm: true').length - 1;
  assert.equal(confirms, 1, `${file} has one email_confirm write`);
}

const dashboard = fs.readFileSync('landing/dashboard/dashboard.js', 'utf8');
assert.match(
  dashboard,
  /Authorization': `Bearer \$\{this\.session\.access_token\}`/,
  'web edge calls send the session JWT',
);
assert.match(dashboard, /callEdgeFunction\('claim_invite'/, 'web claim_invite uses that helper');
assert.doesNotMatch(dashboard, /functions\/v1\/claim_player/, 'web does not call claim_player');

console.log('claim-caller: passed');
