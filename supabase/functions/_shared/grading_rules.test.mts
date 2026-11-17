import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

import { gradeBet, isDeferredMarket } from './grading.ts';
import { legStorageError, resolveStoredLeg } from './market_validation.ts';
import { decideParlay, parlaySettlementKey, parlayTooManyLegs } from './parlay_settle.ts';
import { gradeProp, resolvePropTarget } from './prop_stats.ts';
import { runGradeDryRun } from './grade_dry_run.ts';

const receptions = (n) => ({ receptions: n });
const rush = (n) => ({ rushing_yards: n });
const passTd = (n) => ({ passing_touchdowns: n });

test('prop over wins and under loses', () => {
  const over = gradeProp('player_receptions', 'Mark Andrews Over 2.5', receptions(8), { statsFinal: true });
  const under = gradeProp('player_receptions', 'Mark Andrews Under 2.5', receptions(8), { statsFinal: true });
  assert.equal(over.result, 'win');
  assert.equal(over.actual, 8);
  assert.equal(under.result, 'loss');
});

test('prop under wins and over loses', () => {
  const under = gradeProp('player_rush_yds', 'Derrick Henry Under 79.5', rush(10), { statsFinal: true });
  const over = gradeProp('player_rush_yds', 'Derrick Henry Over 20.5', rush(10), { statsFinal: true });
  assert.equal(under.result, 'win');
  assert.equal(over.result, 'loss');
});

test('integer line pushes and a half-point line does not', () => {
  const push = gradeProp('player_rush_yds', 'Saquon Barkley Over 60', rush(60), { statsFinal: true });
  const notPush = gradeProp('player_rush_yds', 'Saquon Barkley Over 60.5', rush(60), { statsFinal: true });
  assert.equal(push.result, 'push');
  assert.match(push.detail, /integer line/);
  assert.equal(notPush.result, 'loss');
});

test('a missing statline after the box score is final is a void, not a push', () => {
  const dnp = gradeProp('player_receptions', 'Mark Andrews Over 2.5', null, { statsFinal: true });
  assert.equal(dnp.result, 'void');
  assert.match(dnp.detail, /did not play/);
  assert.doesNotMatch(dnp.detail, /push/i);
});

test('stats that are not final stay pending, even with no statline', () => {
  const waiting = gradeProp('player_receptions', 'Mark Andrews Over 2.5', null, { statsFinal: false });
  const waitingZero = gradeProp('player_pass_tds', 'Justin Herbert Over 0.5', passTd(0), { statsFinal: false });
  assert.equal(waiting.result, 'pending');
  assert.equal(waitingZero.result, 'pending');
  assert.match(waiting.detail, /not final/);
});

test('Nov 16: Andrews receptions O2.5 with 8 wins', () => {
  const out = gradeProp('player_receptions', 'Mark Andrews Over 2.5', receptions(8), { statsFinal: true });
  assert.equal(out.result, 'win');
  assert.equal(out.actual, 8);
  assert.equal(out.line, 2.5);
});

test('Nov 16: Henry rushing yards O79.5 with 10 loses', () => {
  const out = gradeProp('player_rush_yds', 'Derrick Henry Over 79.5', rush(10), { statsFinal: true });
  assert.equal(out.result, 'loss');
  assert.equal(out.actual, 10);
});

test('Nov 16: Herbert passing TD O0.5 with 0 loses', () => {
  const out = gradeProp('player_pass_tds', 'Justin Herbert Over 0.5', passTd(0), { statsFinal: true });
  assert.equal(out.result, 'loss');
  assert.equal(out.actual, 0);
});

test('a zero row is a played game, not a did-not-play', () => {
  const out = gradeProp('player_rush_yds', 'Dante Fowler Over 0.5', rush(0), { statsFinal: true });
  assert.equal(out.result, 'loss');
});

test('gradeBet skips props and futures instead of pushing them', () => {
  const scores = { homeScore: 24, awayScore: 17, homeTeam: 'Eagles', awayTeam: 'Cowboys' };
  const prop = gradeBet({ id: '1', market: 'player_prop', side: 'Mark Andrews Over 2.5' }, scores);
  const outright = gradeBet({ id: '2', market: 'outright', side: 'Eagles' }, scores);
  assert.equal(prop.result, 'deferred');
  assert.equal(outright.result, 'deferred');
  assert.equal(isDeferredMarket('player_prop'), true);
  assert.equal(isDeferredMarket('futures'), true);
  assert.equal(isDeferredMarket('moneyline'), false);
  const moneyline = gradeBet({ id: '3', market: 'moneyline', side: 'Eagles' }, scores);
  assert.equal(moneyline.result, 'win');
});

test('a prop grades from the bet snapshot when the market row is gone', () => {
  const target = resolvePropTarget(
    { stat_key: 'player_receptions', subject_player_id: 44, side: 'Mark Andrews Over 2.5' },
    null,
  );
  assert.equal('error' in target, false);
  if ('error' in target) return;
  assert.equal(target.source, 'snapshot');
  const out = gradeProp(target.statKey, target.side, receptions(8), { statsFinal: true });
  assert.equal(out.result, 'win');
});

test('without a snapshot or a market row the prop is left pending', () => {
  const target = resolvePropTarget({ stat_key: null, subject_player_id: null, side: 'Over 2.5' }, null);
  assert.equal('error' in target, true);
});

function leg(result, odds, status) {
  return { status: status ?? (result === 'void' ? 'void' : 'graded'), grade_result: result, odds };
}

test('2 voids plus 1 loss is a loss, and it does not wait', () => {
  const decision = decideParlay(100, [
    leg('void', -110),
    leg('void', -110),
    leg('loss', -110),
    leg(null, -110, 'accepted'),
  ]);
  assert.equal(decision.action, 'settle');
  assert.equal(decision.outcome, 'loss');
  assert.equal(decision.amount, 100);
});

test('2 voids plus 2 wins pays the repriced 2-leg payout', () => {
  const decision = decideParlay(100, [
    leg('void', -110),
    leg('void', 150),
    leg('win', -360),
    leg('win', -344),
  ]);
  assert.equal(decision.action, 'settle');
  assert.equal(decision.outcome, 'win');
  assert.equal(decision.activeLegs, 2);
  assert.equal(decision.profit, 64.92);
  assert.equal(decision.amount, -64.92);
});

test('all void is a refund', () => {
  const decision = decideParlay(100, [leg('void', -110), leg('void', -110), leg('push', -110, 'graded')]);
  assert.equal(decision.action, 'settle');
  assert.equal(decision.outcome, 'void');
  assert.equal(decision.amount, 0);
  assert.equal(decision.profit, 0);
});

test('a 5-leg submit is rejected and a 4-leg submit is not', () => {
  assert.equal(parlayTooManyLegs(4, 4), null);
  const reason = parlayTooManyLegs(5, 4);
  assert.ok(reason);
  assert.match(reason, /at most 4 legs/);
  const source = readFileSync(new URL('../submit_parlay/index.ts', import.meta.url), 'utf8');
  assert.match(source, /parlayTooManyLegs\(body\.legs\.length/);
  assert.doesNotMatch(source, /Exceeds max parlay legs/);
  const rejectAt = source.indexOf('parlayTooManyLegs');
  const insertAt = source.indexOf(".from('bets')");
  assert.ok(rejectAt > 0 && rejectAt < insertAt, 'the leg cap is checked before any bet is inserted');
});

test('the parlay settlement key is deterministic', () => {
  const key = parlaySettlementKey('33f8748b-0000-4000-8000-000000000001', 1);
  assert.equal(key, parlaySettlementKey('33f8748b-0000-4000-8000-000000000001', 1));
  assert.equal(key, 'auto_settle_parlay_33f8748b-0000-4000-8000-000000000001_v1');
  assert.doesNotMatch(key, /Date|\d{13}/);
  assert.notEqual(key, parlaySettlementKey('33f8748b-0000-4000-8000-000000000001', 2));
});

test('a market id or a bare side letter is rejected', () => {
  const uuid = '3f2b064e-1111-4000-8000-000000000000';
  assert.match(legStorageError(uuid, 'b', { side_a: 'Ravens', side_b: 'Bengals' }) ?? '', /known market type/);
  assert.match(legStorageError('moneyline', 'b', { side_a: 'Ravens', side_b: 'Bengals' }) ?? '', /selection label/);
  const stored = resolveStoredLeg(
    { id: 'm1', type: 'player_prop', side_a: 'Mark Andrews Over 2.5', side_b: 'Mark Andrews Under 2.5', stat_key: 'player_receptions', subject_player_id: 44 },
    'a',
  );
  assert.equal(stored.ok, true);
  if (!stored.ok) return;
  assert.equal(stored.market, 'player_prop');
  assert.equal(stored.side, 'Mark Andrews Over 2.5');
  assert.equal(stored.snapshot.stat_key, 'player_receptions');
  assert.equal(stored.snapshot.subject_player_id, 44);
  assert.equal(stored.snapshot.prop_line, 2.5);
  const missing = resolveStoredLeg(null, 'b');
  assert.equal(missing.ok, false);
});

function trackingClient(tables) {
  const writes = [];
  const forbid = (name) => () => {
    writes.push(name);
    throw new Error(`dry run tried to ${name}`);
  };
  return {
    writes,
    rpc: forbid('rpc'),
    from(table) {
      const filters = [];
      const builder = {
        select() { return builder; },
        eq(column, value) { filters.push([column, value]); return builder; },
        in() { return builder; },
        limit() { return builder; },
        insert: forbid('insert'),
        update: forbid('update'),
        upsert: forbid('upsert'),
        delete: forbid('delete'),
        maybeSingle() {
          const rows = tables[table] ?? [];
          const hit = rows.find((row) => filters.every(([column, value]) => row[column] === value)) ?? null;
          return Promise.resolve({ data: hit, error: null });
        },
        then(resolve) {
          const rows = (tables[table] ?? []).filter((row) => filters.every(([column, value]) => row[column] === value));
          resolve({ data: rows, error: null });
        },
      };
      return builder;
    },
  };
}

test('grade dry run performs zero writes and reports the repriced parlay', async () => {
  const client = trackingClient({
    bets: [
      { id: 'l1', ticket_id: 't1', is_parlay: true, market: 'player_prop', market_id: null, side: 'Mark Andrews Over 2.5', stat_key: 'player_receptions', subject_player_id: 1, odds: -360, stake: 100, event_id: 'e1', status: 'accepted', grade_result: null },
      { id: 'l2', ticket_id: 't1', is_parlay: true, market: 'player_prop', market_id: null, side: 'Derrick Henry Over 79.5', stat_key: 'player_rush_yds', subject_player_id: 2, odds: -344, stake: 100, event_id: 'e1', status: 'void', grade_result: 'void' },
      { id: 'l3', ticket_id: 't1', is_parlay: true, market: 'player_prop', market_id: null, side: 'Someone Else Over 1.5', stat_key: 'player_receptions', subject_player_id: 3, odds: -110, stake: 100, event_id: 'e1', status: 'void', grade_result: 'void' },
      { id: 'l4', ticket_id: 't1', is_parlay: true, market: 'moneyline', market_id: null, side: 'Ravens', stat_key: null, subject_player_id: null, odds: -344, stake: 100, event_id: 'e2', status: 'graded', grade_result: 'win' },
    ],
    events: [
      { id: 'e1', league: 'NFL', status: 'final', bdl_game_id: 9, home_score: 20, away_score: 17, home_team: 'Ravens', away_team: 'Bengals' },
      { id: 'e2', league: 'NFL', status: 'final', home_score: 20, away_score: 17, home_team: 'Ravens', away_team: 'Bengals' },
    ],
    markets: [],
  });

  const report = await runGradeDryRun(client, { ticket_id: 't1' }, async (_event, subjectId) => {
    if (subjectId === 1) return { statline: receptions(8), statsFinal: true };
    return { statline: null, statsFinal: true };
  });

  assert.equal(client.writes.length, 0);
  assert.equal(report.dry_run, true);
  assert.equal(report.writes, 0);
  assert.equal(report.kind, 'parlay');
  assert.equal(report.result, 'win');
  assert.equal(report.profit, 64.92);
  assert.ok(report.decimal_odds > 1);
  const andrews = report.legs.find((leg) => leg.bet_id === 'l1');
  assert.equal(andrews.result, 'win');
  assert.equal(andrews.actual, 8);
  assert.equal(andrews.source, 'snapshot');
});

test('the dry-run edge function source has no write calls', () => {
  const source = readFileSync(new URL('../grade_dry_run/index.ts', import.meta.url), 'utf8');
  assert.doesNotMatch(source, /\.(insert|update|upsert|delete|rpc)\s*\(/);
});
