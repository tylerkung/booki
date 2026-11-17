import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

function memoryStorage() {
  const data = new Map();
  return {
    getItem(key) { return data.has(key) ? data.get(key) : null; },
    setItem(key, value) { data.set(key, String(value)); },
    removeItem(key) { data.delete(key); },
  };
}

function loadHandoff(search) {
  const local = memoryStorage();
  const session = memoryStorage();
  const window = {
    location: new URL('https://preview.example/dashboard/login.html' + (search || '')),
    localStorage: local,
    sessionStorage: session,
    history: { replaceState() {} },
  };
  const code = fs.readFileSync(new URL('../landing/invite-handoff.js', import.meta.url), 'utf8');
  vm.runInNewContext(code, { window, URL, URLSearchParams });
  return { invite: window.BookiInvite, local, session };
}

const fresh = loadHandoff('?invite=ab12cd');
assert.equal(fresh.invite.readCode(), 'AB12CD');

fresh.invite.writeAwaiting('qa@example.com');
assert.equal(fresh.invite.readAwaiting().email, 'qa@example.com');
assert.equal(fresh.local.getItem('booki_awaiting_verification') !== null, true);

fresh.invite.writeVerifySecret('s3cret');
assert.equal(fresh.invite.readVerifySecret(), 's3cret');
assert.equal(fresh.local.getItem('booki_verify_password'), null, 'password stays out of localStorage');
assert.equal(fresh.session.getItem('booki_verify_password'), 's3cret');

// A reload is a new page object over the same storage.
const reloaded = loadHandoff('?invite=AB12CD');
reloaded.local.getItem = fresh.local.getItem.bind(fresh.local);
reloaded.local.setItem = fresh.local.setItem.bind(fresh.local);
reloaded.local.removeItem = fresh.local.removeItem.bind(fresh.local);
reloaded.session.getItem = fresh.session.getItem.bind(fresh.session);
reloaded.session.setItem = fresh.session.setItem.bind(fresh.session);
reloaded.session.removeItem = fresh.session.removeItem.bind(fresh.session);
assert.equal(reloaded.invite.readAwaiting().email, 'qa@example.com', 'reload still knows we are waiting');
assert.equal(reloaded.invite.readVerifySecret(), 's3cret', 'same tab still has the password');
assert.equal(reloaded.invite.readCode(), 'AB12CD');

fresh.invite.clearAwaiting();
assert.equal(fresh.invite.readAwaiting(), null);
assert.equal(fresh.invite.readVerifySecret(), '', 'clearing the wait also drops the password');

assert.equal(fresh.invite.emailConfirmOrigin('https://bookisports.com/'), 'https://bookisports.com');
assert.equal(fresh.invite.emailConfirmOrigin('https://deploy-preview-4--booki.netlify.app'), 'https://deploy-preview-4--booki.netlify.app');
assert.equal(fresh.invite.emailConfirmOrigin('javascript:alert(1)'), '');

assert.equal(fresh.invite.dashboardTarget('ab12'), '/dashboard/?invite=AB12');
assert.equal(fresh.invite.dashboardTarget(''), '/dashboard/');
assert.equal(fresh.invite.alreadyInGroupCopy('E2E Group'), 'You\u2019re already in E2E Group\u2019s group');
assert.equal(fresh.invite.alreadyInGroupCopy('  '), 'You\u2019re already in this group');

const login = fs.readFileSync(new URL('../landing/dashboard/login.html', import.meta.url), 'utf8');
assert.match(login, /emailRedirectTo: redirectTo/);
assert.match(login, /writeAwaiting\(email\)/);
assert.match(login, /startVerificationWatch\(\)/);
assert.match(login, /readAwaiting/);
assert.doesNotMatch(login, /bookisports\.com\/verify/);

const verify = fs.readFileSync(new URL('../landing/verify.html', import.meta.url), 'utf8');
assert.match(verify, /verifyOtp/);
assert.match(verify, /dashboardTarget/);
assert.doesNotMatch(verify, /redirect: 'manual'/);

const template = fs.readFileSync(new URL('../landing/email-confirm.html', import.meta.url), 'utf8');
assert.match(template, /\{\{ \.RedirectTo \}\}\/verify\?token=\{\{ \.TokenHash \}\}/);
assert.doesNotMatch(template, /bookisports\.com\/verify/);

console.log('invite-handoff: passed');
