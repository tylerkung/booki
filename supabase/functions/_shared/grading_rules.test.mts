import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

import { gradeBet, isDeferredMarket } from './grading.ts';
import {
  futuresAwaitingResult,
  isOutrightMarket,
  manualSingleSettlementKey,
  outrightGrade,
  outrightSelectionMatches,
  outrightSettlementKey,
} from './outright.ts';
import { deployedSingleSideAccepted, legStorageError, resolveStoredLeg, singleBetIndicator } from './market_validation.ts';
import { decideParlay, parlaySettlementKey, parlayTooManyLegs, placeParlayIfAllowed, roundCents } from './parlay_settle.ts';
import { gradeProp, parsePropSide, resolvePropTarget } from './prop_stats.ts';
import { settlementAmount } from './settlement_math.ts';
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

test('a manual single settles once, through settle_bet_tx, and a future does not', () => {
  assert.equal(manualSingleSettlementKey('c2aa18ec-0000-4000-8000-000000000010'), 'manual_settle_c2aa18ec-0000-4000-8000-000000000010_v1');
  assert.equal(isOutrightMarket('outright'), true);
  assert.equal(isOutrightMarket('Futures'), true);
  assert.equal(isOutrightMarket('moneyline'), false);

  const source = readFileSync(new URL('../grade_bet/index.ts', import.meta.url), 'utf8');
  assert.match(source, /settleBetTx\s*\(/);
  assert.match(source, /manualSingleSettlementKey\s*\(/);
  assert.match(source, /isOutrightMarket\s*\(/);
  assert.doesNotMatch(source, /\.from\('ledger_entries'\)/);

  const page = readFileSync(new URL('../../../landing/dashboard/index.html', import.meta.url), 'utf8');
  assert.match(page, /away_team !== 'Outright'/);
  assert.match(page, /Win \(Home\)/);
});

test('a futures pick matches the selection name, not a market id', () => {
  assert.equal(outrightSelectionMatches('Golden State Warriors', 'Golden State Warriors'), true);
  assert.equal(outrightSelectionMatches('  golden   state warriors ', 'Golden State Warriors'), true);
  assert.equal(outrightSelectionMatches('Golden State Warriors +12000', 'Golden State Warriors'), true);
  assert.equal(outrightSelectionMatches('Warriors +12000', 'Warriors'), true);
  assert.equal(outrightSelectionMatches('Warriors', 'Golden State Warriors'), false);
  assert.equal(outrightSelectionMatches('Boston Celtics', 'Golden State Warriors'), false);
  assert.equal(outrightSelectionMatches('', 'Warriors'), false);
  assert.equal(outrightGrade('Golden State Warriors', 'Golden State Warriors', false), 'win');
  assert.equal(outrightGrade('Boston Celtics', 'Golden State Warriors', false), 'loss');
  assert.equal(outrightGrade('Boston Celtics', null, true), 'void');
  assert.equal(
    outrightSettlementKey('c2aa18ec-0000-4000-8000-000000000010'),
    'outright_settle_c2aa18ec-0000-4000-8000-000000000010_v1',
  );
});

test('futures awaiting a result are the open picks with no recorded winner', () => {
  const events = [
    { id: 'E1', away_team: 'Outright', home_team: 'NBA Championship', start_time: '2026-06-01', status: 'final', sport: 'Basketball', league: 'NBA' },
    { id: 'E2', away_team: 'Outright', home_team: 'Super Bowl', start_time: '2027-02-01', status: 'scheduled', sport: 'Football', league: 'NFL' },
    { id: 'E3', away_team: 'Celtics', home_team: 'Knicks', start_time: '2026-06-04', status: 'scheduled', sport: 'Basketball', league: 'NBA' },
  ];
  const rows = futuresAwaitingResult({
    bets: [
      { event_id: 'e1', side: 'Golden State Warriors', stake: 10 },
      { event_id: 'E1', side: 'Boston Celtics', stake: 5 },
      { event_id: 'E2', side: 'Chiefs', stake: 20 },
      { event_id: 'E3', side: 'Knicks', stake: 10 },
    ],
    events,
    markets: [
      { event_id: 'E1', type: 'outright', side_a: 'Denver Nuggets' },
      { event_id: 'E2', type: 'spread', side_a: 'Ignore' },
    ],
    results: [{ event_id: 'E2' }],
  });
  assert.equal(rows.length, 1);
  assert.equal(rows[0].name, 'NBA Championship');
  assert.equal(rows[0].open_picks, 2);
  assert.equal(rows[0].open_stake, 15);
  assert.deepEqual(rows[0].selections, ['Boston Celtics', 'Denver Nuggets', 'Golden State Warriors']);

  const source = readFileSync(new URL('../settle_outright/index.ts', import.meta.url), 'utf8');
  assert.match(source, /ADMIN_EMAILS/);
  assert.match(source, /settle_outright_tx/);
  assert.match(source, /, 404\)/);
  assert.doesNotMatch(source, /\.from\('ledger_entries'\)/);
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

test('a 5-leg submit returns 400 and does not insert', () => {
  const inserted = [];
  const rejected = placeParlayIfAllowed(5, 4, () => inserted.push('row'));
  assert.equal(rejected.status, 400);
  assert.match(rejected.error, /at most 4 legs/);
  assert.deepEqual(inserted, []);

  const accepted = placeParlayIfAllowed(4, 4, () => inserted.push('row'));
  assert.equal(accepted.status, 200);
  assert.deepEqual(inserted, ['row']);
});

test('a leg cap below 2 is the default of 4, not a confusing 400', () => {
  assert.equal(parlayTooManyLegs(4, 0), null);
  assert.equal(parlayTooManyLegs(4, 1), null);
  assert.match(parlayTooManyLegs(5, 0), /at most 4 legs/);
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

const scoringZeros = {
  rushing_touchdowns: 0,
  receiving_touchdowns: 0,
  kick_return_touchdowns: 0,
  punt_return_touchdowns: 0,
  interception_touchdowns: 0,
  fumbles_touchdowns: 0,
};

test('an unknown stat key stays pending and is not refunded', () => {
  const played = gradeProp('player_made_up', 'Mark Andrews Over 2.5', receptions(8), { statsFinal: true });
  const absent = gradeProp('player_made_up', 'Mark Andrews Over 2.5', null, { statsFinal: true });
  assert.equal(played.result, 'pending');
  assert.equal(absent.result, 'pending');
  assert.match(played.detail, /manual review/);
  assert.match(absent.detail, /manual review/);
  assert.notEqual(played.result, 'void');
  assert.notEqual(absent.result, 'void');
});

test('an unknown market type is manual review, not a push', () => {
  const out = gradeBet(
    { id: 'x', market: 'player_foo', side: 'Over 6.5' },
    { homeScore: 1, awayScore: 0, homeTeam: 'A', awayTeam: 'B' },
  );
  assert.equal(out.result, 'manual');
  assert.match(out.gradeDetails, /manual review/);
  assert.notEqual(out.result, 'push');
});

test('a missing stat field stays pending and a real zero is a zero', () => {
  const absent = gradeProp('player_rush_yds', 'Derrick Henry Over 0.5', { receptions: 4 }, { statsFinal: true });
  const nulled = gradeProp('player_rush_yds', 'Derrick Henry Over 0.5', { rushing_yards: null }, { statsFinal: true });
  const zero = gradeProp('player_rush_yds', 'Derrick Henry Over 0.5', { rushing_yards: 0 }, { statsFinal: true });
  const notFinite = gradeProp('player_rush_yds', 'Derrick Henry Over 0.5', { rushing_yards: Number.NaN }, { statsFinal: true });
  assert.equal(absent.result, 'pending');
  assert.equal(nulled.result, 'pending');
  assert.match(absent.detail, /absent/);
  assert.equal(zero.result, 'loss');
  assert.equal(zero.actual, 0);
  assert.equal(notFinite.result, 'pending');
  assert.match(notFinite.detail, /not a finite stat/);
});

test('d84e919e loss, win, void, void is a loss of the $100 stake', () => {
  const decision = decideParlay(100, [
    leg('loss', -360),
    leg('win', -344),
    leg('void', -217),
    leg('void', -408),
  ]);
  assert.equal(decision.action, 'settle');
  assert.equal(decision.outcome, 'loss');
  assert.equal(decision.amount, 100);
  assert.equal(-decision.amount, -100);
});

test('Andrews O2.5 $50 at -151 with 8 receptions wins $33.11', () => {
  const graded = gradeProp('player_receptions', 'Mark Andrews Over 2.5', receptions(8), { statsFinal: true });
  assert.equal(graded.result, 'win');
  const ledger = settlementAmount('win', 50, -151);
  assert.equal(roundCents(-ledger), 33.11);
  assert.equal(roundCents(ledger), -33.11);
});

test('Henry O81.5 with 10 rush yards loses, Flowers O70.5 with 74 wins, Henry U1.5 loses', () => {
  const henryOver = gradeProp('player_rush_yds', 'Derrick Henry Over 81.5', rush(10), { statsFinal: true });
  const flowers = gradeProp('player_reception_yds', 'Zay Flowers Over 70.5', { receiving_yards: 74 }, { statsFinal: true });
  const henryUnder = gradeProp(
    'player_rush_tds',
    'Derrick Henry Under 1.5',
    { rushing_yards: 10, rushing_touchdowns: 2 },
    { statsFinal: true },
  );
  assert.equal(henryOver.result, 'loss');
  assert.equal(flowers.result, 'win');
  assert.equal(henryUnder.result, 'loss');
});

test('an under on an integer line pushes, including inside a parlay', () => {
  const pushed = gradeProp('player_receptions', 'Mark Andrews Under 8', receptions(8), { statsFinal: true });
  assert.equal(pushed.result, 'push');
  const decision = decideParlay(100, [leg('push', -110, 'graded'), leg('win', -151)]);
  assert.equal(decision.outcome, 'win');
  assert.equal(decision.activeLegs, 1);
  assert.equal(decision.profit, roundCents(100 * (100 / 151)));
});

test('a void leaves one live leg priced as that single', () => {
  const decision = decideParlay(50, [leg('void', -110), leg('win', -151)]);
  assert.equal(decision.outcome, 'win');
  assert.equal(decision.activeLegs, 1);
  assert.equal(decision.profit, 33.11);
});

test('a win plus a push reprices to the winning leg', () => {
  const decision = decideParlay(100, [leg('win', -110), leg('push', 150, 'graded')]);
  assert.equal(decision.outcome, 'win');
  assert.equal(decision.activeLegs, 1);
  assert.equal(decision.profit, roundCents(100 * (100 / 110)));
});

test('a did-not-play under is a void, not a win', () => {
  const out = gradeProp('player_receptions', 'Mark Andrews Under 2.5', null, { statsFinal: true });
  assert.equal(out.result, 'void');
  assert.match(out.detail, /did not play/);
});

test('half-cent rounding', () => {
  assert.equal(roundCents(1.225), 1.23);
  assert.equal(roundCents(1.224), 1.22);
  assert.equal(roundCents(-1.225), -1.23);
  const decision = decideParlay(1.225, [leg('win', 100)]);
  assert.equal(decision.profit, 1.23);
});

test('anytime and over touchdowns treat absent scoring fields as zero', () => {
  // A skill player who only rushed. Return and fumble touchdowns are absent
  // on a real NFL statline; they are 0, not a reason to leave the prop pending.
  const partial = { rushing_yards: 48, rushing_touchdowns: 1, receptions: 0 };
  const anytime = gradeProp('player_anytime_td', 'Derrick Henry Anytime TD Yes', partial, { statsFinal: true });
  const over = gradeProp('player_tds_over', 'Derrick Henry Over 0.5', partial, { statsFinal: true });
  assert.equal(anytime.result, 'win');
  assert.equal(anytime.actual, 1);
  assert.equal(over.result, 'win');
  assert.equal(over.actual, 1);

  const none = gradeProp('player_anytime_td', 'Derrick Henry Anytime TD Yes', { rushing_yards: 10 }, { statsFinal: true });
  assert.equal(none.result, 'loss');
  assert.equal(none.actual, 0);

  const dnp = gradeProp('player_anytime_td', 'Derrick Henry Anytime TD Yes', null, { statsFinal: true });
  assert.equal(dnp.result, 'void');
});

test('passing touchdowns do not count as an anytime touchdown', () => {
  const line = { passing_touchdowns: 2, ...scoringZeros };
  const passing = gradeProp('player_pass_tds', 'Justin Herbert Over 0.5', line, { statsFinal: true });
  const anytime = gradeProp('player_anytime_td', 'Justin Herbert Anytime TD Yes', line, { statsFinal: true });
  assert.equal(passing.result, 'win');
  assert.equal(passing.actual, 2);
  assert.equal(anytime.result, 'loss');
  assert.equal(anytime.actual, 0);
});

test('an outright leg inside a parlay stays pending and is not a push', () => {
  const outright = gradeBet(
    { id: 'f', market: 'outright', side: 'Chiefs' },
    { homeScore: 1, awayScore: 0, homeTeam: 'Chiefs', awayTeam: 'Bills' },
  );
  assert.equal(outright.result, 'deferred');
  assert.notEqual(outright.result, 'push');
  const decision = decideParlay(100, [
    leg('win', -110),
    { status: 'accepted', grade_result: null, odds: 450 },
  ]);
  assert.equal(decision.action, 'wait');
  assert.notEqual(decision.outcome, 'push');
});

test('parsePropSide accepts a trailing space and rejects odd input', () => {
  assert.deepEqual(parsePropSide('  Mark Andrews Over 2.5  '), {
    subject: 'Mark Andrews',
    direction: 'over',
    line: 2.5,
  });
  assert.deepEqual(parsePropSide('Derrick Henry Under 81.5 '), {
    subject: 'Derrick Henry',
    direction: 'under',
    line: 81.5,
  });
  for (const bad of ['', '   ', 'b', 'Over 2.5', 'Andrews Over', 'just a name', '3f2b064e-1111-4000-8000-000000000000']) {
    assert.equal(parsePropSide(bad), null, bad);
  }
});

test('refresh_live_scores settles singles and does not send dead columns', () => {
  const source = readFileSync(new URL('../refresh_live_scores/index.ts', import.meta.url), 'utf8');
  assert.doesNotMatch(source, /grade_details\s*:/);
  assert.doesNotMatch(source, /settled_amount\s*:/);
  assert.match(source, /settleBetTx\s*\(/);
  assert.doesNotMatch(source, /from\('ledger_entries'\)\s*\.insert/);
});

test('manual settle_parlay uses the shared RPC and reprices voids', () => {
  const source = readFileSync(new URL('../settle_parlay/index.ts', import.meta.url), 'utf8');
  assert.match(source, /settleParlayTx\s*\(/);
  assert.doesNotMatch(source, /determineParlayOutcome/);
  assert.doesNotMatch(source, /['"]settling['"]/);
  const decision = decideParlay(100, [
    leg('loss', -360),
    leg('win', -344),
    leg('void', -217),
    leg('void', -408),
  ]);
  assert.equal(decision.outcome, 'loss');
  assert.equal(decision.amount, 100);
  assert.equal(-decision.amount, -100);
});

test('parlay settlement has no settling status', () => {
  const apply = readFileSync(new URL('./parlay_apply.ts', import.meta.url), 'utf8');
  assert.doesNotMatch(apply, /['"]settling['"]/);
  assert.match(apply, /settleParlayTx\s*\(/);
  assert.throws(() => readFileSync(new URL('./parlay_claim.ts', import.meta.url), 'utf8'));
});

test('the singles payload still satisfies the deployed submit_bets contract', () => {
  const code = readFileSync(new URL('../../../landing/dashboard/slip-payload.js', import.meta.url), 'utf8');
  const sandbox = {};
  vm.runInNewContext(code, sandbox);
  const sel = {
    event_id: 'ev',
    market_id: 'mk',
    side: 'Chiefs -3.5',
    side_indicator: 'a',
    odds: -110,
  };
  const single = sandbox.BookiSlip.singleBetPayload(sel, 25);
  assert.equal(single.side, 'a');
  assert.equal(single.side_label, 'Chiefs -3.5');
  assert.equal(deployedSingleSideAccepted(single), true);
  assert.equal(singleBetIndicator(single), 'a');

  const labelForm = { side: sel.side, side_indicator: sel.side_indicator };
  assert.equal(deployedSingleSideAccepted(labelForm), false);
  assert.equal(singleBetIndicator(labelForm), 'a');

  const parlay = sandbox.BookiSlip.parlayLegPayload(sel);
  assert.equal(parlay.side, 'Chiefs -3.5');
  assert.equal(parlay.side_indicator, 'a');
  assert.equal(parlay.side_indicator === 'a' || parlay.side_indicator === 'b', true);
  assert.ok(parlay.side);
});
