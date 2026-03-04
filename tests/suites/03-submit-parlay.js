import { callEdge, uuid, getServiceClient } from '../lib/client.js';
import { eq, ok } from '../lib/assert.js';

export default async function submitParlay(ctx) {
  const svc = getServiceClient();

  // Valid 2-leg parlay
  {
    const legs = [
      { event_id: ctx.events[0].id, market_id: ctx.markets[0].id, side: ctx.events[0].home_team, side_indicator: 'a', odds: -110 },
      { event_id: ctx.events[1].id, market_id: ctx.markets[3].id, side: ctx.events[1].home_team, side_indicator: 'a', odds: -110 },
    ];
    const { status, data } = await callEdge('submit_parlay', {
      legs,
      stake: '20',
      player_id: ctx.playerId,
      bookie_id: ctx.bookieId,
      combined_odds: 264,
      idempotency_key: uuid(),
    }, ctx.playerToken);

    eq(status, 200, 'valid 2-leg parlay → 200');
    eq(data?.success, true, 'parlay success = true');
    ok(data?.ticket_id, 'ticket_id returned');
    ok(data?.bets?.length >= 2, `${data?.bets?.length} legs created`);

    // Store for later suites
    ctx._parlayTicketId = data?.ticket_id;
    ctx._parlayBetIds = data?.bets?.map(b => b.id) || [];
  }

  // 1-leg parlay → error
  {
    const { status, data } = await callEdge('submit_parlay', {
      legs: [{ event_id: ctx.events[0].id, market_id: ctx.markets[0].id, side: ctx.events[0].home_team, side_indicator: 'a', odds: -110 }],
      stake: '10',
      player_id: ctx.playerId,
      bookie_id: ctx.bookieId,
      combined_odds: -110,
      idempotency_key: uuid(),
    }, ctx.playerToken);
    eq(status, 400, '1-leg parlay → 400');
  }

  // Missing stake → error
  {
    const legs = [
      { event_id: ctx.events[0].id, market_id: ctx.markets[0].id, side: ctx.events[0].home_team, side_indicator: 'a', odds: -110 },
      { event_id: ctx.events[1].id, market_id: ctx.markets[3].id, side: ctx.events[1].home_team, side_indicator: 'a', odds: -110 },
    ];
    const { status } = await callEdge('submit_parlay', {
      legs,
      player_id: ctx.playerId,
      bookie_id: ctx.bookieId,
      combined_odds: 264,
      idempotency_key: uuid(),
    }, ctx.playerToken);
    eq(status, 400, 'parlay missing stake → 400');
  }

  // No auth → 401
  {
    const { status } = await callEdge('submit_parlay', {
      legs: [
        { event_id: ctx.events[0].id, market_id: ctx.markets[0].id, side: 'a', side_indicator: 'a', odds: -110 },
        { event_id: ctx.events[1].id, market_id: ctx.markets[3].id, side: 'a', side_indicator: 'a', odds: -110 },
      ],
      stake: '10',
      player_id: ctx.playerId,
      bookie_id: ctx.bookieId,
      combined_odds: 264,
      idempotency_key: uuid(),
    });
    eq(status, 401, 'parlay no auth → 401');
  }
}
