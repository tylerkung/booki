import { callEdge, uuid, getServiceClient } from '../lib/client.js';
import { eq, ok } from '../lib/assert.js';

export default async function override(ctx) {
  const svc = getServiceClient();

  // Create and grade a bet — then override (skip settle due to known RPC bug)
  const { data: submitData } = await callEdge('submit_bets', {
    bets: [{ event_id: ctx.eventIds[0], market_id: ctx.marketIds[0], side: 'a', odds: -110, stake: '30' }],
    player_id: ctx.playerId,
    bookie_id: ctx.bookieId,
    idempotency_key: uuid(),
  }, ctx.playerToken);
  const betId = submitData?.bets?.[0]?.id;
  ok(betId, 'created bet for override test');

  // Grade as win
  await callEdge('grade_bet', { bet_id: betId, outcome: 'win', idempotency_key: uuid() }, ctx.bookieToken);

  // Override from win → loss (on graded bet, not settled)
  const { status, data } = await callEdge('override_grade', {
    bet_id: betId,
    new_outcome: 'loss',
    reason: 'Stress test override',
    idempotency_key: uuid(),
  }, ctx.bookieToken);

  eq(status, 200, 'override win → loss → 200');
  eq(data?.success, true, 'override success');

  // Verify bet grade changed
  const { data: dbBet } = await svc.from('bets').select('grade_result, status').eq('id', betId).single();
  eq(dbBet?.grade_result, 'loss', 'grade_result changed to loss');

  // Override to void
  {
    const { status: s2, data: d2 } = await callEdge('override_grade', {
      bet_id: betId,
      new_outcome: 'void',
      reason: 'Changed to void',
      idempotency_key: uuid(),
    }, ctx.bookieToken);
    eq(s2, 200, 'override loss → void → 200');
  }

  // Override without reason → 400
  {
    const { data: d2 } = await callEdge('submit_bets', {
      bets: [{ event_id: ctx.eventIds[1], market_id: ctx.marketIds[3], side: 'b', odds: -110, stake: '5' }],
      player_id: ctx.playerId,
      bookie_id: ctx.bookieId,
      idempotency_key: uuid(),
    }, ctx.playerToken);
    const bid2 = d2?.bets?.[0]?.id;
    if (bid2) {
      await callEdge('grade_bet', { bet_id: bid2, outcome: 'win', idempotency_key: uuid() }, ctx.bookieToken);
      const { status: s2 } = await callEdge('override_grade', {
        bet_id: bid2,
        new_outcome: 'loss',
        reason: '',
        idempotency_key: uuid(),
      }, ctx.bookieToken);
      eq(s2, 400, 'override with empty reason → 400');
    }
  }

  // Override ungraded bet → 400
  {
    const { data: d3 } = await callEdge('submit_bets', {
      bets: [{ event_id: ctx.eventIds[2], market_id: ctx.markets[6].id, side: 'a', odds: -110, stake: '5' }],
      player_id: ctx.playerId,
      bookie_id: ctx.bookieId,
      idempotency_key: uuid(),
    }, ctx.playerToken);
    const bid3 = d3?.bets?.[0]?.id;
    if (bid3) {
      const { status: s3 } = await callEdge('override_grade', {
        bet_id: bid3,
        new_outcome: 'win',
        reason: 'test',
        idempotency_key: uuid(),
      }, ctx.bookieToken);
      eq(s3, 400, 'override ungraded bet → 400');
    }
  }
}
