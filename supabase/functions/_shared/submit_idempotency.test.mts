import assert from 'node:assert/strict';
import test from 'node:test';

import {
  canonicalSubmitPayload,
  payloadsMatch,
  submissionDecision,
  isPayloadMismatch,
} from './submit_idempotency.ts';

const player = '33333333-3333-4333-8333-333333333333';
const bookie = '22222222-2222-4222-8222-222222222222';
const eventId = 'EEEEEEEE-EEEE-4EEE-8EEE-EEEEEEEEEEEE';
const marketId = '1050EA8A-0000-4000-8000-0000001050EA';

test('a single payload ignores the key, the label, and uuid case', () => {
  const payload = canonicalSubmitPayload('submit_bets', {
    player_id: player.toUpperCase(),
    bookie_id: bookie,
    idempotency_key: '0845800d-0000-4000-8000-000000084580',
    bets: [{
      event_id: eventId,
      market_id: marketId,
      side: 'a',
      side_label: 'Colorado +3',
      odds: -110,
      stake: 1,
    }],
  });
  assert.deepEqual(payload, {
    operation: 'submit_bets',
    player_id: player,
    bookie_id: bookie,
    bets: [{
      event_id: eventId.toLowerCase(),
      market_id: marketId.toLowerCase(),
      side: 'a',
      odds: -110,
      stake: '1.00',
    }],
  });
});

test('1, "1", and "1.00" are one stake', () => {
  const forms = [1, '1', '1.00', '1.0'];
  const payloads = forms.map((stake) => canonicalSubmitPayload('submit_bet', {
    player_id: player,
    bookie_id: bookie,
    event_id: eventId,
    market_id: marketId,
    side: 'a',
    odds: '-110',
    stake,
  }));
  for (const payload of payloads) {
    assert.equal(payloadsMatch(payloads[0], payload), true);
  }
  assert.equal(payloads[0].stake, '1.00');
  assert.equal(payloads[0].odds, -110);
});

test('a different stake is a different payload', () => {
  const first = canonicalSubmitPayload('submit_bets', {
    player_id: player,
    bookie_id: bookie,
    bets: [{ event_id: eventId, market_id: marketId, side: 'a', odds: -110, stake: '1.00' }],
  });
  const second = canonicalSubmitPayload('submit_bets', {
    player_id: player,
    bookie_id: bookie,
    bets: [{ event_id: eventId, market_id: marketId, side: 'a', odds: -110, stake: '5.00' }],
  });
  assert.equal(payloadsMatch(first, second), false);
});

test('key order does not make two payloads different', () => {
  const first = canonicalSubmitPayload('submit_bet', {
    bookie_id: bookie,
    player_id: player,
    stake: '1.00',
    odds: -110,
    side: 'a',
    market_id: marketId,
    event_id: eventId,
  });
  const reversed = {
    stake: '1.00',
    side: 'a',
    odds: -110,
    operation: 'submit_bet',
    market_id: marketId.toLowerCase(),
    event_id: eventId.toLowerCase(),
    bookie_id: bookie,
    player_id: player,
  };
  assert.equal(payloadsMatch(first, reversed), true);
});

test('a parlay keeps the letter and the label', () => {
  const payload = canonicalSubmitPayload('submit_parlay', {
    player_id: player,
    bookie_id: bookie,
    stake: '2.5',
    combined_odds: '+264',
    legs: [{
      event_id: eventId,
      market_id: marketId,
      side: 'Colorado +3',
      side_indicator: 'a',
      odds: -110,
    }],
  });
  assert.equal(payload.stake, '2.50');
  assert.equal(payload.combined_odds, 264);
  assert.deepEqual(payload.legs, [{
    event_id: eventId.toLowerCase(),
    market_id: marketId.toLowerCase(),
    side: 'Colorado +3',
    side_indicator: 'a',
    odds: -110,
  }]);
});

test('decision: insert, legacy replay, same payload, different payload', () => {
  const request = canonicalSubmitPayload('submit_bets', {
    player_id: player,
    bookie_id: bookie,
    bets: [{ event_id: eventId, market_id: marketId, side: 'a', odds: -110, stake: 1 }],
  });
  assert.equal(submissionDecision(null, request), 'insert');
  assert.equal(submissionDecision({ request_payload: null }, request), 'replay');
  assert.equal(submissionDecision({ request_payload: undefined }, request), 'replay');
  assert.equal(submissionDecision({ request_payload: request }, request), 'replay');
  const bets = request.bets;
  if (!Array.isArray(bets) || bets.length !== 1 || typeof bets[0] !== 'object' || bets[0] === null) {
    throw new Error('expected one bet in the canonical payload');
  }
  const firstBet = bets[0] as Record<string, unknown>;
  const other = { ...request, bets: [{ ...firstBet, stake: '5.00' }] };
  assert.equal(submissionDecision({ request_payload: other }, request), 'mismatch');
});

test('P0422 and the exception message are the payload mismatch', () => {
  assert.equal(isPayloadMismatch({ code: 'P0422', message: 'idempotency_payload_mismatch' }), true);
  assert.equal(isPayloadMismatch({ message: 'idempotency_payload_mismatch' }), true);
  assert.equal(isPayloadMismatch({ code: '23505', message: 'duplicate key' }), false);
  assert.equal(isPayloadMismatch(null), false);
});
