import assert from 'node:assert/strict';
import fs from 'node:fs';
import { memberNameFromAuthUser } from '../supabase/functions/_shared/member_name.ts';

const cases = [
  {
    name: 'typed name is kept',
    user: { email: 'tylerbkung+bookiqa1@gmail.com', user_metadata: { name: 'QA Test One' } },
    expect: 'QA Test One',
  },
  {
    name: 'surrounding whitespace is trimmed and collapsed',
    user: { email: 'a@b.co', user_metadata: { name: '  QA   Test  ' } },
    expect: 'QA Test',
  },
  {
    name: 'blank name falls back to the email prefix',
    user: { email: 'tylerbkung+bookiqa1@gmail.com', user_metadata: { name: '   ' } },
    expect: 'tylerbkung+bookiqa1',
  },
  {
    name: 'missing metadata falls back to the email prefix',
    user: { email: 'member@example.com', user_metadata: {} },
    expect: 'member',
  },
  {
    name: 'non-string name is ignored',
    user: { email: 'member@example.com', user_metadata: { name: 12 } },
    expect: 'member',
  },
  {
    name: 'email without @ is used whole',
    user: { email: 'not-an-email', user_metadata: null },
    expect: 'not-an-email',
  },
  {
    name: 'nothing at all becomes Member',
    user: { email: '', user_metadata: {} },
    expect: 'Member',
  },
  {
    name: 'a very long name is capped',
    user: { email: 'a@b.co', user_metadata: { name: 'N'.repeat(200) } },
    expect: 'N'.repeat(120),
  },
];

for (const c of cases) {
  assert.equal(memberNameFromAuthUser(c.user), c.expect, c.name);
}

const claim = fs.readFileSync(new URL('../supabase/functions/claim_invite/index.ts', import.meta.url), 'utf8');
assert.match(claim, /memberNameFromAuthUser\(authUser\.user\)/);
assert.doesNotMatch(claim, /split\('@'\)/);

console.log(`member-name: ${cases.length} cases passed`);
