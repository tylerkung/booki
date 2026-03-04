import { callEdge, uuid, getServiceClient } from '../lib/client.js';
import { eq, ok, gte } from '../lib/assert.js';

export default async function submitBets(ctx) {
  const svc = getServiceClient();

  // Submit 3 valid singles
  {
    const bets = ctx.events.map((evt, i) => ({
      event_id: evt.id,
      market_id: ctx.markets[i * 3].id, // moneyline for each event
      side: 'a',
      odds: -110,
      stake: '10',
    }));
    const { status, data } = await callEdge('submit_bets', {
      bets,
      player_id: ctx.playerId,
      bookie_id: ctx.bookieId,
      idempotency_key: uuid(),
    }, ctx.playerToken);

    eq(status, 200, 'submit 3 valid singles → 200');
    eq(data?.success, true, 'response success = true');
    eq(data?.bets?.length, 3, '3 bets returned');

    // Verify in database
    if (data?.bets?.length) {
      const betId = data.bets[0].id;
      const { data: dbBet } = await svc.from('bets').select('*').eq('id', betId).single();
      ok(dbBet, 'bet exists in database');
      eq(dbBet?.status, 'accepted', 'bet auto-accepted');
      eq(dbBet?.player_id, ctx.playerId, 'bet linked to correct player');
      eq(dbBet?.bookie_id, ctx.bookieId, 'bet linked to correct bookie');

      // Store for later test suites
      ctx._betIds = data.bets.map(b => b.id);
    }
  }

  // Invalid market ID → error
  {
    const { status, data } = await callEdge('submit_bets', {
      bets: [{ event_id: ctx.eventIds[0], market_id: uuid(), side: 'a', odds: -110, stake: '10' }],
      player_id: ctx.playerId,
      bookie_id: ctx.bookieId,
      idempotency_key: uuid(),
    }, ctx.playerToken);
    // Should fail — market doesn't exist
    ok(status === 200 || status === 400 || status === 404, `invalid market → ${status}`);
    if (status === 200) {
      // Partial failure model
      ok(data?.failed?.length > 0, 'invalid market in failed array');
    }
  }

  // Negative stake → error
  {
    const { status, data } = await callEdge('submit_bets', {
      bets: [{ event_id: ctx.eventIds[0], market_id: ctx.marketIds[0], side: 'a', odds: -110, stake: '-10' }],
      player_id: ctx.playerId,
      bookie_id: ctx.bookieId,
      idempotency_key: uuid(),
    }, ctx.playerToken);
    ok(status === 400 || (status === 200 && data?.failed?.length > 0), 'negative stake → rejected');
  }

  // Empty bets array → error
  {
    const { status } = await callEdge('submit_bets', {
      bets: [],
      player_id: ctx.playerId,
      bookie_id: ctx.bookieId,
      idempotency_key: uuid(),
    }, ctx.playerToken);
    eq(status, 400, 'empty bets array → 400');
  }

  // Wrong side value → error
  {
    const { status, data } = await callEdge('submit_bets', {
      bets: [{ event_id: ctx.eventIds[0], market_id: ctx.marketIds[0], side: 'x', odds: -110, stake: '10' }],
      player_id: ctx.playerId,
      bookie_id: ctx.bookieId,
      idempotency_key: uuid(),
    }, ctx.playerToken);
    ok(status === 400 || (status === 200 && data?.failed?.length > 0), 'invalid side "x" → rejected');
  }

  // Player2 (no bookie) can't bet under this bookie
  {
    const { status } = await callEdge('submit_bets', {
      bets: [{ event_id: ctx.eventIds[0], market_id: ctx.marketIds[0], side: 'a', odds: -110, stake: '10' }],
      player_id: ctx.player2Id,
      bookie_id: ctx.bookieId,
      idempotency_key: uuid(),
    }, ctx.player2Token);
    ok(status === 403 || status === 404, `unlinked player submit → ${status}`);
  }
}
