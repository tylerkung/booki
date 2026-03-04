import { callEdge, uuid, getServiceClient } from '../lib/client.js';
import { eq, ok } from '../lib/assert.js';

export default async function grading(ctx) {
  const svc = getServiceClient();

  // Create fresh bets for grading tests (one per outcome)
  const outcomes = ['win', 'loss', 'push', 'void'];
  const betIds = [];

  for (let i = 0; i < outcomes.length; i++) {
    const { data } = await callEdge('submit_bets', {
      bets: [{ event_id: ctx.eventIds[0], market_id: ctx.marketIds[0], side: 'a', odds: -110, stake: '5' }],
      player_id: ctx.playerId,
      bookie_id: ctx.bookieId,
      idempotency_key: uuid(),
    }, ctx.playerToken);
    betIds.push(data?.bets?.[0]?.id);
  }

  // Grade each with different outcome
  for (let i = 0; i < outcomes.length; i++) {
    const outcome = outcomes[i];
    const betId = betIds[i];
    if (!betId) { ok(false, `bet ${i} missing for ${outcome} grade`); continue; }

    const { status, data } = await callEdge('grade_bet', {
      bet_id: betId,
      outcome,
      idempotency_key: uuid(),
    }, ctx.bookieToken);

    eq(status, 200, `grade ${outcome} → 200`);
    eq(data?.success, true, `grade ${outcome} success`);

    // Verify in DB
    const { data: dbBet } = await svc.from('bets').select('status, grade_result').eq('id', betId).single();
    if (outcome === 'void') {
      eq(dbBet?.status, 'void', `void bet status = void`);
    } else {
      eq(dbBet?.status, 'graded', `${outcome} bet status = graded`);
      eq(dbBet?.grade_result, outcome, `${outcome} grade_result correct`);
    }
  }

  // Grade already-graded bet → 400
  {
    const { status, data } = await callEdge('grade_bet', {
      bet_id: betIds[0],
      outcome: 'loss',
      idempotency_key: uuid(),
    }, ctx.bookieToken);
    eq(status, 400, 'grade already-graded → 400');
  }

  // Invalid outcome → 400
  {
    // Need a fresh accepted bet
    const { data: freshData } = await callEdge('submit_bets', {
      bets: [{ event_id: ctx.eventIds[1], market_id: ctx.marketIds[3], side: 'a', odds: -110, stake: '5' }],
      player_id: ctx.playerId,
      bookie_id: ctx.bookieId,
      idempotency_key: uuid(),
    }, ctx.playerToken);
    const freshId = freshData?.bets?.[0]?.id;
    if (freshId) {
      const { status } = await callEdge('grade_bet', {
        bet_id: freshId,
        outcome: 'invalid_outcome',
        idempotency_key: uuid(),
      }, ctx.bookieToken);
      eq(status, 400, 'invalid outcome → 400');
    }
  }

  // Store graded bet IDs for settlement tests
  ctx._gradedBetIds = betIds.slice(0, 3); // win, loss, push (not void)
}
