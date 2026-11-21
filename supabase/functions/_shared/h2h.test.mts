import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import test from 'node:test';

import { planSharedMainLine } from './main_line.ts';
import {
  bettableSharedIds,
  canonicalTeamName,
  MONEYLINE_MAX_AGE_MS,
  moneylineOffBoardError,
  OFF_BOARD_AMERICAN,
  selectMoneyline,
  sameTeam,
} from './h2h.ts';
import { oddsRefreshSkip } from './odds_refresh.ts';

const require = createRequire(import.meta.url);
const board = require('../../../landing/dashboard/board_markets.js');

const NOW = Date.parse('2026-11-20T23:00:00Z');

function book(key, outcomes, marketKey = 'h2h') {
  return { key, markets: [{ key: marketKey, outcomes }] };
}

function h2h(homeName, homePrice, awayName, awayPrice) {
  return [
    { name: homeName, price: homePrice },
    { name: awayName, price: awayPrice },
  ];
}

test('Nov 20 names that the exact match dropped', () => {
  const pairs = [
    ['Loyola (MD)', 'Loyola Maryland'],
    ['Loyola (MD)', 'Loyola Maryland Greyhounds'],
    ['E. Illinois', 'Eastern Illinois'],
    ['E. Illinois', 'Eastern Illinois Panthers'],
    ['MVSU', 'Mississippi Valley State'],
    ['MVSU', 'Mississippi Valley State Delta Devils'],
    ['Le Moyne', 'LeMoyne'],
    ['Le Moyne', 'Le Moyne Dolphins'],
    ['Ole Miss', 'Mississippi'],
    ['Ole Miss', 'Mississippi Rebels'],
    ['Wagner', 'Wagner Seahawks'],
    ['Wofford', 'Wofford Terriers'],
    ['Chattanooga', 'Chattanooga Mocs'],
    ['Samford', 'Samford Bulldogs'],
    ['Nebraska', 'Nebraska Cornhuskers'],
    ['Iowa', 'Iowa Hawkeyes'],
  ];
  for (const [eventName, bookName] of pairs) {
    assert.equal(sameTeam(eventName, bookName), true, `${eventName} vs ${bookName}`);
  }
});

test('a different school is not a match', () => {
  assert.equal(sameTeam('Ole Miss', 'Mississippi State'), false);
  assert.equal(sameTeam('Mississippi', 'Mississippi State'), false);
  assert.equal(sameTeam('Miami', 'Miami (OH)'), false);
  assert.equal(sameTeam('Loyola (MD)', 'Loyola Marymount'), false);
  assert.equal(sameTeam('Illinois', 'Eastern Illinois'), false);
  assert.equal(sameTeam('Georgia', 'Georgia Southern'), false);
  assert.equal(sameTeam('Texas', 'Texas A&M'), false);
  assert.equal(canonicalTeamName('Texas A&M'), canonicalTeamName('Texas AM'));
});

test('DraftKings prices the moneyline when it can name both teams', () => {
  const pick = selectMoneyline(
    [
      book('fanduel', h2h('Virginia', -200, 'Loyola Maryland', 170)),
      book('fanatics', h2h('Virginia', -190, 'Loyola Maryland', 165)),
      book('draftkings', h2h('Virginia', -180, 'Loyola (MD)', 155)),
    ],
    'Virginia',
    'Loyola (MD)',
  );
  assert.equal(pick.bookmaker, 'draftkings');
  assert.equal(pick.homePrice, -180);
  assert.equal(pick.awayPrice, 155);
});

test('Fanatics is the fallback, and the two sides are not mixed', () => {
  // DraftKings has the spread-style names on h2h but only one of them matches,
  // and a home price that must not be paired with Fanatics' away price.
  const pick = selectMoneyline(
    [
      book('draftkings', [
        { name: 'Virginia', price: -500 },
        { name: 'Some Other School', price: 400 },
      ]),
      book('fanduel', h2h('Virginia Cavaliers', -210, 'Loyola Maryland', 175)),
      book('fanatics', h2h('Virginia', -175, 'Loyola Maryland', 150)),
    ],
    'Virginia',
    'Loyola (MD)',
  );
  assert.equal(pick.bookmaker, 'fanatics');
  assert.equal(pick.homePrice, -175);
  assert.equal(pick.awayPrice, 150);
});

test('another book is used when DraftKings and Fanatics have no moneyline', () => {
  const pick = selectMoneyline(
    [
      book('draftkings', [], 'spreads'),
      book('fanatics', h2h('Over', -110, 'Under', -110), 'totals'),
      book('betrivers', h2h('Iowa Hawkeyes', -140, 'Nebraska Cornhuskers', 120)),
    ],
    'Iowa',
    'Nebraska',
  );
  assert.equal(pick.bookmaker, 'betrivers');
  assert.equal(pick.homePrice, -140);
  assert.equal(pick.awayPrice, 120);
});

test('a price worse than -10000 is off the board, and the next sane book is used', () => {
  const extreme = selectMoneyline(
    [book('draftkings', h2h('Tennessee', -20000, 'Coastal Carolina', 3500))],
    'Tennessee',
    'Coastal Carolina',
  );
  assert.equal(extreme, null);

  const fallback = selectMoneyline(
    [
      book('draftkings', h2h('Tennessee', -20000, 'Coastal Carolina', 3500)),
      book('fanatics', h2h('Tennessee', -450, 'Coastal Carolina', 360)),
    ],
    'Tennessee',
    'Coastal Carolina',
  );
  assert.equal(fallback.bookmaker, 'fanatics');
  assert.equal(fallback.homePrice, -450);
  assert.equal(fallback.awayPrice, 360);

  assert.equal(moneylineOffBoardError(
    { type: 'moneyline', odds_a: 3500, odds_b: -20000, updated_at: '2026-11-20T22:00:00Z' },
    3500,
    NOW,
  ), 'off_the_board');
  assert.equal(isFinite(OFF_BOARD_AMERICAN), true);
  assert.equal(moneylineOffBoardError(
    { type: 'moneyline', odds_a: 3500, odds_b: -10000, updated_at: '2026-11-20T22:00:00Z' },
    -10000,
    NOW,
  ), null);
});

test('a pick\'em moneyline stays on the board', () => {
  const pick = selectMoneyline(
    [book('draftkings', h2h('Fighter A', -115, 'Fighter B', -105))],
    'Fighter A',
    'Fighter B',
  );
  assert.equal(pick.bookmaker, 'draftkings');
  assert.equal(moneylineOffBoardError(
    { type: 'moneyline', odds_a: -105, odds_b: -115, updated_at: '2026-11-20T22:00:00Z' },
    -115,
    NOW,
  ), null);
  assert.equal(moneylineOffBoardError(
    { type: 'spread', odds_a: -110, odds_b: -110, updated_at: '2026-11-18T00:00:00Z' },
    -110,
    NOW,
  ), null);
});

test('a moneyline older than 18 hours is off the board', () => {
  const fresh = new Date(NOW - MONEYLINE_MAX_AGE_MS + 60_000).toISOString();
  const stale = new Date(NOW - MONEYLINE_MAX_AGE_MS - 60_000).toISOString();
  const row = (updated_at) => ({ type: 'moneyline', odds_a: 150, odds_b: -170, updated_at });
  assert.equal(moneylineOffBoardError(row(fresh), 150, NOW), null);
  assert.equal(moneylineOffBoardError(row(stale), 150, NOW), 'off_the_board');
  assert.equal(moneylineOffBoardError(row(null), 150, NOW), 'off_the_board');
});

test('Campbell @ K-State: writing the new moneyline retires the older one', () => {
  const plan = planSharedMainLine([
    { id: 'ml-nov19', bookie_id: null, updated_at: '2026-11-19T20:00:00Z', bettable: true, main_line: null },
    { id: 'ml-nov20', bookie_id: null, updated_at: '2026-11-20T12:00:00Z', bettable: true, main_line: null },
  ]);
  assert.equal(plan.canonicalId, 'ml-nov20');
  assert.deepEqual(plan.retireIds, ['ml-nov19']);
});

test('a moneyline missing from the latest feed retires the bettable rows', () => {
  const ids = bettableSharedIds([
    { id: 'live', bookie_id: null, bettable: true },
    { id: 'already', bookie_id: null, bettable: false },
    { id: 'private', bookie_id: 'bookie-1', bettable: true },
  ]);
  assert.deepEqual(ids, ['live']);
});

test('a game never auto-refreshed is priced even when the tier clock says no', () => {
  const base = {
    startTime: '2026-11-21T23:00:00Z',
    now: NOW,
    isOutright: false,
    league: 'UFC',
    includeNearTier: false,
    includeMidTier: false,
    includeFutures: false,
  };
  assert.equal(oddsRefreshSkip({ ...base, lastAutoOddsRefresh: null }), null);
  assert.equal(
    oddsRefreshSkip({ ...base, lastAutoOddsRefresh: '2026-11-20T12:00:00Z' }),
    'mid_tier',
  );
  // Started, and outside the member window, still wait.
  assert.equal(oddsRefreshSkip({
    ...base,
    startTime: '2026-11-20T20:00:00Z',
    lastAutoOddsRefresh: null,
  }), 'started');
  assert.equal(oddsRefreshSkip({
    ...base,
    startTime: '2026-11-25T23:00:00Z',
    lastAutoOddsRefresh: null,
  }), 'not_soon');
  // Championship markets stay on the daily futures run.
  assert.equal(oddsRefreshSkip({
    ...base,
    isOutright: true,
    lastAutoOddsRefresh: null,
  }), 'futures');
});

test('the board says Off the board and will not offer the price', () => {
  assert.equal(board.OFF_BOARD_LABEL, 'Off the board');
  assert.equal(board.OFF_BOARD_AMERICAN, OFF_BOARD_AMERICAN);
  assert.equal(board.MONEYLINE_MAX_AGE_MS, MONEYLINE_MAX_AGE_MS);
  const stale = { odds_a: 150, odds_b: -170, bettable: true, updated_at: '2026-11-18T20:00:00Z' };
  assert.equal(board.moneylineMarketOnBoard(stale, NOW), false);
  assert.equal(board.moneylineMarketOnBoard(
    { odds_a: 3500, odds_b: -20000, bettable: true, updated_at: '2026-11-20T22:00:00Z' },
    NOW,
  ), false);
  assert.equal(board.moneylineMarketOnBoard(
    { odds_a: -105, odds_b: -115, bettable: true, updated_at: '2026-11-20T22:00:00Z' },
    NOW,
  ), true);
  assert.equal(board.moneylineMarketOnBoard(
    { odds_a: 140, odds_b: -160, bettable: false, updated_at: '2026-11-20T22:00:00Z' },
    NOW,
  ), false);
  assert.equal(board.moneylineMarketOnBoard(null, NOW), false);

  const group = {
    events: [
      { away_team: 'Chiefs' },
      { away_team: 'Bills' },
      { away_team: 'Outright' },
    ],
    games: [{ away_team: 'Chiefs' }, { away_team: 'Bills' }],
    outrights: [{ away_team: 'Outright' }],
  };
  assert.equal(board.leagueHeaderCount(group), 2);
  assert.equal(group.outrights.length, 1, 'the count does not remove the futures row');
});

test('the ingest, the submits, and the board are wired to this', () => {
  const sync = fs.readFileSync(new URL('../sync_games/index.ts', import.meta.url), 'utf8');
  const refresh = fs.readFileSync(new URL('../auto_refresh_games/index.ts', import.meta.url), 'utf8');
  const boardJs = fs.readFileSync(new URL('../../../landing/dashboard/board_markets.js', import.meta.url), 'utf8');
  const html = fs.readFileSync(new URL('../../../landing/dashboard/index.html', import.meta.url), 'utf8');
  for (const source of [sync, refresh]) {
    assert.match(source, /selectMoneyline/);
    assert.match(source, /bettableSharedIds/);
    assert.match(source, /bookmaker:/);
    assert.doesNotMatch(source, /o\.name === oddsEvent\.home_team/);
  }
  assert.match(refresh, /oddsRefreshSkip/);
  assert.match(refresh, /last_auto_odds_refresh/);
  assert.match(boardJs, /Off the board/);
  assert.match(html, /leagueHeaderCount\(leagueGroup\)/);
  assert.match(html, /leagueGroup\.outrights/);
  assert.doesNotMatch(html, /leagueGroup\.events\.length/);
  for (const name of ['submit_bet', 'submit_bets', 'submit_parlay']) {
    const src = fs.readFileSync(new URL(`../${name}/index.ts`, import.meta.url), 'utf8');
    assert.match(src, /moneylineOffBoardError/);
    assert.match(src, /startTime <= now/);
  }
  const migration = fs.readFileSync(
    new URL('../../migrations/066_market_bookmaker.sql', import.meta.url),
    'utf8',
  );
  assert.match(migration, /ADD COLUMN IF NOT EXISTS bookmaker/);
  assert.doesNotMatch(migration, /UPDATE\s+markets/i);
  assert.doesNotMatch(migration, /DELETE\s+FROM\s+markets/i);
});
