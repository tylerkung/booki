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

function loadSlip() {
  const code = fs.readFileSync(new URL('../landing/dashboard/slip-payload.js', import.meta.url), 'utf8');
  const sandbox = {};
  vm.runInNewContext(code, sandbox);
  return sandbox.BookiSlip;
}

const slip = {
  mode: 'singles',
  player_id: '33333333-3333-4333-8333-333333333333',
  bookie_id: '22222222-2222-4222-8222-222222222222',
  selections: [
    { event_id: 'E1', market_id: 'M1', side: 'Colorado +3', side_indicator: 'a', odds: -110 },
    { event_id: 'E2', market_id: 'M2', side: 'Over 8.5', side_indicator: 'b', odds: -105 },
  ],
  stakes: { 0: '1', 1: 0 },
  multiStake: '',
};

const api = loadSlip();
const fingerprint = api.slipFingerprint(slip);
const again = api.slipFingerprint({
  ...slip,
  player_id: slip.player_id.toUpperCase(),
  stakes: { 0: 1, 1: '' },
});
assert.equal(fingerprint, again, 'the same slip fingerprints once');

const changed = api.slipFingerprint({ ...slip, stakes: { 0: '5.00' } });
assert.notEqual(fingerprint, changed, 'a new stake is a new slip');

const storage = memoryStorage();
let minted = 0;
const mint = () => `key-${++minted}`;
const first = api.claimSlipKey(storage, fingerprint, mint);
const second = api.claimSlipKey(storage, fingerprint, mint);
assert.equal(first, second, 'a double tap reuses the key');
assert.equal(minted, 1);

const otherStorage = memoryStorage();
const third = api.claimSlipKey(otherStorage, fingerprint, mint);
assert.equal(third, first, 'a second caller on this page reuses the in-memory key');

const fresh = loadSlip();
const fromDisk = fresh.claimSlipKey(storage, fingerprint, mint);
assert.equal(fromDisk, first, 'a retry in this tab reads the stored key');

const newKey = fresh.claimSlipKey(storage, changed, mint);
assert.notEqual(newKey, first);
fresh.releaseSlipKey(storage, changed);
const reminted = fresh.claimSlipKey(storage, changed, () => 'after-release');
assert.equal(reminted, 'after-release');

const multi = fresh.slipFingerprint({
  mode: 'multi',
  player_id: slip.player_id,
  bookie_id: slip.bookie_id,
  selections: slip.selections,
  multiStake: 2,
  combinedOdds: 264,
});
const multiAgain = fresh.slipFingerprint({
  mode: 'multi',
  player_id: slip.player_id,
  bookie_id: slip.bookie_id,
  selections: slip.selections,
  multiStake: '2.00',
  combinedOdds: '264',
});
assert.equal(multi, multiAgain);
assert.notEqual(multi, fingerprint);

const dashboard = fs.readFileSync(new URL('../landing/dashboard/dashboard.js', import.meta.url), 'utf8');
const start = dashboard.indexOf('async submitBetSlip()');
const end = dashboard.indexOf('closeBetSlipSuccess', start);
const fn = dashboard.slice(start, end);
assert.match(fn, /claimSlipKey/);
assert.match(fn, /releaseSlipKey/);
assert.doesNotMatch(fn, /crypto\.randomUUID/);
assert.match(fn, /idempotency_payload_mismatch/);

const migration = fs.readFileSync(new URL('../supabase/migrations/065_submit_idempotency.sql', import.meta.url), 'utf8');
assert.match(migration, /defc7465/);
assert.match(migration, /51bd1346/);
assert.match(migration, /0845800d/);
assert.match(migration, /claim_bet_submission/);
assert.doesNotMatch(migration, /UPDATE\s+bets/i);
assert.doesNotMatch(migration, /DELETE\s+FROM\s+bets/i);
assert.doesNotMatch(migration, /DELETE\s+FROM\s+idempotency_keys/i);
assert.doesNotMatch(migration, /UPDATE\s+idempotency_keys/i);
