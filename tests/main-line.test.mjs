import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import {
  isMainLine,
  planSharedMainLine,
  isSharedMainLineConflict,
} from '../supabase/functions/_shared/main_line.ts';

const require = createRequire(import.meta.url);
const board = require('../landing/dashboard/board_markets.js');

// Colts @ Texans, 19 Nov 2026. Four bettable shared spreads, each written at
// a different time. The board showed +11.5 (08:00Z). The feed at 20:00Z was
// +12.5. submit_bets refused +11.5 because it trailed that sibling.
const colts = [
  row('spread-10', '2026-11-17T04:00:00Z'),
  row('spread-105', '2026-11-17T06:00:00Z'),
  row('spread-115', '2026-11-17T08:00:00Z'),
  row('spread-125', '2026-11-17T20:00:00Z'),
];

const plan = planSharedMainLine(colts);
assert.equal(plan.canonicalId, 'spread-125', 'newest spread is the row the feed overwrites');
assert.deepEqual(
  [...plan.retireIds].sort(),
  ['spread-10', 'spread-105', 'spread-115'],
  'older main lines are retired, not left bettable',
);
assert.equal(plan.retireIds.includes(plan.canonicalId), false);
assert.equal('deleteIds' in plan, false, 'the plan has no delete list');

// A row already flagged stays the canonical id even if an older duplicate
// was touched more recently. The id the board has been using does not hop.
const flagged = planSharedMainLine([
  { ...row('old-flag', '2026-11-17T08:00:00Z'), main_line: true },
  { ...row('newer-dup', '2026-11-17T20:00:00Z'), main_line: null },
]);
assert.equal(flagged.canonicalId, 'old-flag');
assert.deepEqual(flagged.retireIds, ['newer-dup']);

// Already retired rows are not retired again, and they are not chosen while
// a bettable sibling exists.
const mixed = planSharedMainLine([
  { ...row('dead', '2026-11-17T21:00:00Z'), bettable: false, main_line: false },
  row('live', '2026-11-17T20:00:00Z'),
]);
assert.equal(mixed.canonicalId, 'live');
assert.deepEqual(mixed.retireIds, []);

// No shared row yet: the caller inserts. An organizer-owned row is not the
// shared line and is not retired.
const owned = planSharedMainLine([
  { ...row('private', '2026-11-17T20:00:00Z'), bookie_id: 'bookie-1' },
]);
assert.equal(owned.canonicalId, null);
assert.deepEqual(owned.retireIds, []);

// One row, the line moved: same id, nothing to retire. That is the upsert.
const single = planSharedMainLine([row('only', '2026-11-17T20:00:00Z')]);
assert.equal(single.canonicalId, 'only');
assert.deepEqual(single.retireIds, []);

// Same timestamp: the lower id wins, so two runs pick the same row.
const tie = planSharedMainLine([
  row('b-id', '2026-11-17T20:00:00Z'),
  row('a-id', '2026-11-17T20:00:00Z'),
]);
assert.equal(tie.canonicalId, 'a-id');
assert.deepEqual(tie.retireIds, ['b-id']);

assert.equal(isMainLine('spread'), true);
assert.equal(isMainLine('total'), true);
assert.equal(isMainLine('moneyline'), true);
assert.equal(isMainLine('alternate_spread'), false);
assert.equal(isMainLine('team_total'), false);
assert.equal(isMainLine('player_prop'), false);
assert.equal(isMainLine('outright'), false);

assert.equal(isSharedMainLineConflict({ code: '23505', message: 'duplicate key' }), true);
assert.equal(
  isSharedMainLineConflict({ message: 'conflict on markets_one_shared_main_line' }),
  true,
);
assert.equal(isSharedMainLineConflict({ message: 'permission denied' }), false);
assert.equal(isSharedMainLineConflict(null), false);

// Board: the 20:00Z spread wins even when the unordered query returns the
// 08:00Z row last. A retired row with a newer updated_at does not.
const markets = [
  { id: 'spread-125', type: 'spread', updated_at: '2026-11-17T20:00:00Z', bettable: true, side_a: 'Colts +12.5' },
  { id: 'spread-115', type: 'spread', updated_at: '2026-11-17T08:00:00Z', bettable: true, side_a: 'Colts +11.5' },
  { id: 'ml-old', type: 'moneyline', updated_at: '2026-11-17T08:00:00Z', bettable: true },
  { id: 'ml-new', type: 'moneyline', updated_at: '2026-11-17T20:00:00Z', bettable: true },
  { id: 'tot-old', type: 'total', updated_at: '2026-11-17T08:00:00Z', bettable: true, side_a: 'Over 44.5' },
  { id: 'tot-new', type: 'total', updated_at: '2026-11-17T20:00:00Z', bettable: true, side_a: 'Over 47.5' },
  { id: 'retired', type: 'spread', updated_at: '2026-11-17T21:00:00Z', bettable: false, side_a: 'Colts +10' },
  { id: 'alt', type: 'alternate_spread', updated_at: '2026-11-17T20:00:00Z', bettable: true, side_a: 'Colts +7.5' },
];
const featuredSpread = board.featuredMainList(markets, 'spread');
assert.equal(featuredSpread.length, 1);
assert.equal(featuredSpread[0].id, 'spread-125');
assert.equal(featuredSpread.some((m) => m.id === 'alt'), false, 'an alternate is not the featured spread');
assert.equal(board.featuredMainList(markets, 'moneyline')[0].id, 'ml-new');
assert.equal(board.featuredMainList(markets, 'total')[0].id, 'tot-new');

// Every row unbettable: the cell is empty, not the retired price.
assert.deepEqual(
  board.featuredMainList(
    [{ id: 'dead', type: 'spread', updated_at: '2026-11-17T21:00:00Z', bettable: false }],
    'spread',
  ),
  [],
);

// Missing bettable means "still offered" (the column defaults to true).
const implied = board.preferBoardMarket(null, {
  id: 'legacy', type: 'spread', updated_at: '2026-11-17T20:00:00Z', side_a: 'Colts +3',
});
assert.equal(implied.id, 'legacy');

// Slip: a line_no_longer_offered failure keeps the pick and refreshes.
const stale = board.submitFailureDisposition('line_no_longer_offered');
assert.equal(stale.clearSlip, false);
assert.equal(stale.refreshBoard, true);
for (const msg of ['Event not found: abc', 'Events not found', 'Market not found', 'Market has no price']) {
  const d = board.submitFailureDisposition(msg);
  assert.equal(d.clearSlip, false, msg);
  assert.equal(d.refreshBoard, true, msg);
}
const other = board.submitFailureDisposition('win_limit_reached');
assert.equal(other.clearSlip, false);
assert.equal(other.refreshBoard, false);
const blank = board.submitFailureDisposition('');
assert.equal(blank.clearSlip, false, 'an empty error still does not wipe the slip');

// Wiring. The ingest must call the planner and must not delete the rows it
// retires. The finished-game prune is a different delete and stays; PR #9
// changes that one to skip markets with open picks.
const sync = fs.readFileSync(
  new URL('../supabase/functions/sync_games/index.ts', import.meta.url),
  'utf8',
);
assert.match(sync, /planSharedMainLine/);
assert.match(sync, /bettable: false, main_line: false/);
assert.match(sync, /isSharedMainLineConflict/);
const syncRetire = sync.slice(sync.indexOf('uniqueRetire'), sync.indexOf('uniqueRetire') + 500);
assert.doesNotMatch(syncRetire, /\.delete\(/);

const refresh = fs.readFileSync(
  new URL('../supabase/functions/auto_refresh_games/index.ts', import.meta.url),
  'utf8',
);
assert.match(refresh, /planSharedMainLine/);
assert.match(refresh, /bettable: false, main_line: false/);
// Withdrawn-line deletes remain for non-main markets only.
assert.match(refresh, /otherExisting/);
assert.match(refresh, /!isMainLine\(r\.type\)/);

const dash = fs.readFileSync(
  new URL('../landing/dashboard/dashboard.js', import.meta.url),
  'utf8',
);
assert.match(dash, /preferBoardMarket/);
assert.match(dash, /featuredMainList\(all, 'spread'\)/);
assert.match(dash, /byType\('alternate_spread'\)/);
assert.match(dash, /submitFailureDisposition/);
const slipCatch = dash.slice(dash.indexOf("console.error('Submit bet slip error:'"));
const slipCatchBody = slipCatch.slice(0, slipCatch.indexOf('this.isSubmittingBets = false'));
assert.doesNotMatch(slipCatchBody, /betSlipSelections = \[\]/);
assert.match(dash, /updated_at, bettable/);

const migration = fs.readFileSync(
  new URL('../supabase/migrations/064_main_line_identity.sql', import.meta.url),
  'utf8',
);
assert.match(migration, /ADD COLUMN IF NOT EXISTS main_line/);
assert.match(migration, /markets_one_shared_main_line/);
assert.match(migration, /m\.bettable IS DISTINCT FROM FALSE/);
assert.match(migration, /HAVING count\(\*\) > 1/);
assert.doesNotMatch(migration, /UPDATE\s+markets/i);
assert.doesNotMatch(migration, /DELETE\s+FROM\s+markets/i);

function row(id, updatedAt) {
  return {
    id,
    bookie_id: null,
    updated_at: updatedAt,
    bettable: true,
    main_line: null,
  };
}

console.log('main-line: colts spread, board picker, slip disposition, migration guards passed');
