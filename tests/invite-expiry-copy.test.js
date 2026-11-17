/**
 * Local copy checks for invite expiry. No Supabase credentials.
 *
 * Run: node tests/invite-expiry-copy.test.js
 *
 * The live suites (12, 16) still need SUPABASE_URL / SERVICE_KEY / ANON_KEY
 * and are not invoked from here. They hit claim/create behaviour, not the
 * email HTML, which is why this file exists.
 */
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
let failed = 0;

function eq(actual, expected, label) {
  if (actual !== expected) {
    failed++;
    console.error(`FAIL ${label}\n  expected: ${expected}\n  actual:   ${actual}`);
  } else {
    console.log(`ok   ${label}`);
  }
}

function ok(cond, label) {
  if (!cond) {
    failed++;
    console.error(`FAIL ${label}`);
  } else {
    console.log(`ok   ${label}`);
  }
}

function extractFunction(src, name) {
  const sig = src.indexOf(`function ${name}`);
  if (sig < 0) throw new Error(`missing function ${name}`);
  let i = src.indexOf('{', sig);
  let depth = 0;
  for (; i < src.length; i++) {
    const c = src[i];
    if (c === "'" || c === '"' || c === '`') {
      const q = c;
      i++;
      while (i < src.length) {
        if (src[i] === '\\') { i += 2; continue; }
        if (src[i] === q) break;
        i++;
      }
      continue;
    }
    if (c === '{') depth++;
    else if (c === '}') {
      depth--;
      if (depth === 0) return src.slice(sig, i + 1);
    }
  }
  throw new Error(`unbalanced ${name}`);
}

function stripSignatureTypes(fn) {
  const open = fn.indexOf('{');
  const sig = fn.slice(0, open)
    .replace(/:\s*[A-Za-z_][\w.]*/g, '');
  return sig + fn.slice(open);
}

// ── dashboard confirmation ────────────────────────────────────────────────
const dash = fs.readFileSync(path.join(root, 'landing/dashboard/dashboard.js'), 'utf8');
const formatSrc = extractFunction(dash, 'formatBearerInviteExpiry');
const formatBearerInviteExpiry = new Function(
  `${formatSrc}; return formatBearerInviteExpiry;`,
)();

const now = Date.parse('2026-11-16T18:00:00Z');
const plus = (ms) => new Date(now + ms).toISOString();
const HOUR = 3600000;

function expectPhrase(ms, phrase) {
  const iso = plus(ms);
  const label = formatBearerInviteExpiry(iso, now);
  const date = new Date(iso).toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
  eq(label, `Expires ${phrase} (${date})`, phrase);
}

// Just-created 7-day link: 168h minus a minute used to render as "167 hours".
expectPhrase(7 * 24 * HOUR - 60 * 1000, 'in 7 days');
// A real partial day, not a raw hour count.
expectPhrase((6 * 24 + 5) * HOUR, 'in 6 days, 5 hours');
expectPhrase(24 * HOUR, 'in 1 day');
expectPhrase(25 * HOUR, 'in 1 day, 1 hour');
expectPhrase(5 * HOUR, 'in 5 hours');
expectPhrase(45 * 60 * 1000, 'in 45 minutes');
eq(formatBearerInviteExpiry(plus(-HOUR), now), 'Expired', 'past invite is Expired');
eq(formatBearerInviteExpiry('', now), '', 'missing timestamp is empty');
ok(!/167/.test(formatBearerInviteExpiry(plus(7 * 24 * HOUR - 60 * 1000), now)),
  'just-created link does not say 167');
ok(!/24 hours/.test(formatBearerInviteExpiry(plus(7 * 24 * HOUR), now)),
  'a 7-day link does not say 24 hours');

// ── email, both kinds ─────────────────────────────────────────────────────
const inviteFn = fs.readFileSync(
  path.join(root, 'supabase/functions/create_invite/index.ts'),
  'utf8',
);
const emailFns = ['invitePageUrl', 'inviteAccountLine', 'inviteExpiryLine', 'buildInviteEmail']
  .map((name) => stripSignatureTypes(extractFunction(inviteFn, name)))
  .join('\n');
const buildInviteEmail = new Function(
  `function escapeHtml(str) {
    return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }
  ${emailFns}; return buildInviteEmail;`,
)();

const addressed = buildInviteEmail('Alex & Co', 'AB23CD45', true);
const link = buildInviteEmail('Alex & Co', 'AB23CD45', false);
const url = 'https://bookisports.com/invite/AB23CD45';

for (const [kind, msg] of [['addressed', addressed], ['link', link]]) {
  ok(msg.html.includes(`href="${url}"`), `${kind} CTA href is the web invite URL`);
  ok(msg.text.includes(`Join: ${url}`), `${kind} text body includes the web invite URL`);
  ok(msg.html.includes('Log in at bookisports.com'), `${kind} html is web wording`);
  ok(!/open the app/i.test(msg.html + msg.text), `${kind} does not say open the app`);
  ok(!/download the app/i.test(msg.html + msg.text), `${kind} does not say download the app`);
  ok(!/24 hours/.test(msg.html + msg.text), `${kind} does not say 24 hours`);
  ok(msg.html.includes('Alex &amp; Co'), `${kind} escapes the organizer name`);
}

ok(addressed.html.includes("This invite doesn't expire. Only this email address can use it."),
  'addressed html says it does not expire');
ok(addressed.text.includes("This invite doesn't expire. Only this email address can use it."),
  'addressed text says it does not expire');
ok(!/expires in 7 days/i.test(addressed.html + addressed.text),
  'addressed email does not claim the 7-day link deadline');

ok(link.html.includes('This invite expires in 7 days. Anyone with this link can join.'),
  'link html says 7 days');
ok(link.text.includes('This invite expires in 7 days. Anyone with this link can join.'),
  'link text says 7 days');
ok(!/doesn't expire/.test(link.html + link.text),
  'link email does not say it does not expire');

const preview = fs.readFileSync(path.join(root, 'landing/email-invite.html'), 'utf8');
ok(preview.includes("This invite doesn't expire. Only this email address can use it."),
  'preview html matches the addressed email');
ok(preview.includes('https://bookisports.com/invite/{{INVITE_CODE}}'),
  'preview CTA is the web invite URL');
ok(!/24 hours/.test(preview), 'preview does not say 24 hours');
ok(!/open the app/i.test(preview), 'preview does not say open the app');

const outDir = process.env.INVITE_EMAIL_OUT;
if (outDir) {
  fs.mkdirSync(outDir, { recursive: true });
  fs.writeFileSync(path.join(outDir, 'addressed.html'), addressed.html);
  fs.writeFileSync(path.join(outDir, 'link.html'), link.html);
  console.log(`wrote email samples to ${outDir}`);
}

if (failed) {
  console.error(`\n${failed} failed`);
  process.exit(1);
}
console.log('\nall invite expiry copy checks passed');
