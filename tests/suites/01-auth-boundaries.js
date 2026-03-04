import { callEdge, uuid } from '../lib/client.js';
import { eq, ok } from '../lib/assert.js';

export default async function authBoundaries(ctx) {
  // No auth header → 401
  {
    const { status } = await callEdge('submit_bets', {
      bets: [{ event_id: ctx.eventIds[0], market_id: ctx.marketIds[0], side: 'a', odds: -110, stake: '10' }],
      player_id: ctx.playerId,
      bookie_id: ctx.bookieId,
      idempotency_key: uuid(),
    });
    eq(status, 401, 'submit_bets with no auth → 401');
  }

  // Invalid JWT → 401
  {
    const { status } = await callEdge('submit_bets', {
      bets: [{ event_id: ctx.eventIds[0], market_id: ctx.marketIds[0], side: 'a', odds: -110, stake: '10' }],
      player_id: ctx.playerId,
      bookie_id: ctx.bookieId,
      idempotency_key: uuid(),
    }, 'invalid.jwt.token');
    eq(status, 401, 'submit_bets with invalid JWT → 401');
  }

  // Player can't call grade_bet (bookie-only)
  {
    const { status } = await callEdge('grade_bet', {
      bet_id: uuid(),
      outcome: 'win',
      idempotency_key: uuid(),
    }, ctx.playerToken);
    // Should be 403 (not a bookie) or 404 (bet not found)
    ok(status === 403 || status === 404, `grade_bet by player → ${status} (403 or 404)`);
  }

  // Player can't call adjust_balance
  {
    const { status } = await callEdge('adjust_balance', {
      player_id: ctx.playerId,
      amount: '50',
      idempotency_key: uuid(),
    }, ctx.playerToken);
    eq(status, 403, 'adjust_balance by player → 403');
  }

  // Player can't call settle_bet
  {
    const { status } = await callEdge('settle_bet', {
      bet_id: uuid(),
      idempotency_key: uuid(),
    }, ctx.playerToken);
    ok(status === 403 || status === 404, `settle_bet by player → ${status} (403 or 404)`);
  }

  // No auth on grade_bet → 401
  {
    const { status } = await callEdge('grade_bet', {
      bet_id: uuid(),
      outcome: 'win',
      idempotency_key: uuid(),
    });
    eq(status, 401, 'grade_bet with no auth → 401');
  }

  // No auth on accept_bet → 401
  {
    const { status } = await callEdge('accept_bet', {
      bet_id: uuid(),
      idempotency_key: uuid(),
    });
    eq(status, 401, 'accept_bet with no auth → 401');
  }

  // No auth on adjust_balance → 401
  {
    const { status } = await callEdge('adjust_balance', {
      player_id: ctx.playerId,
      amount: '10',
      idempotency_key: uuid(),
    });
    eq(status, 401, 'adjust_balance with no auth → 401');
  }
}
