import { callEdge, uuid, getServiceClient } from '../lib/client.js';
import { eq, ok } from '../lib/assert.js';

export default async function acceptDecline(ctx) {
  const svc = getServiceClient();

  // Submit a bet (will auto-accept since manual_bet_acceptance column doesn't exist)
  const { data: d1 } = await callEdge('submit_bets', {
    bets: [{ event_id: ctx.eventIds[0], market_id: ctx.marketIds[0], side: 'a', odds: -110, stake: '10' }],
    player_id: ctx.playerId,
    bookie_id: ctx.bookieId,
    idempotency_key: uuid(),
  }, ctx.playerToken);
  const betId1 = d1?.bets?.[0]?.id;
  ok(betId1, 'bet created');

  // Verify it was auto-accepted
  {
    const { data: bet } = await svc.from('bets').select('status').eq('id', betId1).single();
    eq(bet?.status, 'accepted', 'bet auto-accepted (no manual mode)');
  }

  // Create a bet via submit_bets, then manually set it to pending for accept test
  const { data: d2 } = await callEdge('submit_bets', {
    bets: [{ event_id: ctx.eventIds[1], market_id: ctx.marketIds[3], side: 'a', odds: -110, stake: '10' }],
    player_id: ctx.playerId,
    bookie_id: ctx.bookieId,
    idempotency_key: uuid(),
  }, ctx.playerToken);
  const pendingBetId = d2?.bets?.[0]?.id;
  ok(pendingBetId, 'bet created for accept test');

  // Force to pending via service client
  await svc.from('bets').update({ status: 'pending' }).eq('id', pendingBetId);

  // Accept the pending bet
  {
    const { status, data } = await callEdge('accept_bet', {
      bet_id: pendingBetId,
      idempotency_key: uuid(),
    }, ctx.bookieToken);

    eq(status, 200, 'accept_bet → 200');
    eq(data?.success, true, 'accept_bet success');

    const { data: bet } = await svc.from('bets').select('status').eq('id', pendingBetId).single();
    eq(bet?.status, 'accepted', 'bet status = accepted after accept_bet');
  }

  // Accept already-accepted → error
  {
    const { status } = await callEdge('accept_bet', {
      bet_id: pendingBetId,
      idempotency_key: uuid(),
    }, ctx.bookieToken);
    eq(status, 400, 'accept already-accepted → 400');
  }

  // Create another bet, set to pending, then decline
  const { data: d3 } = await callEdge('submit_bets', {
    bets: [{ event_id: ctx.eventIds[2], market_id: ctx.markets[6].id, side: 'b', odds: -110, stake: '10' }],
    player_id: ctx.playerId,
    bookie_id: ctx.bookieId,
    idempotency_key: uuid(),
  }, ctx.playerToken);
  const declineBetId = d3?.bets?.[0]?.id;
  ok(declineBetId, 'bet created for decline test');

  if (declineBetId) {
    await svc.from('bets').update({ status: 'pending' }).eq('id', declineBetId);

    const { status, data } = await callEdge('decline_bet', {
      bet_id: declineBetId,
      idempotency_key: uuid(),
    }, ctx.bookieToken);

    eq(status, 200, 'decline_bet → 200');
    eq(data?.success, true, 'decline_bet success');

    const { data: bet } = await svc.from('bets').select('status').eq('id', declineBetId).single();
    eq(bet?.status, 'declined', 'bet status = declined');
  }

  // Decline already-declined → error
  if (declineBetId) {
    const { status } = await callEdge('decline_bet', {
      bet_id: declineBetId,
      idempotency_key: uuid(),
    }, ctx.bookieToken);
    eq(status, 400, 'decline already-declined → 400');
  }
}
