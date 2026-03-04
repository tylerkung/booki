import { callEdge, uuid, getServiceClient } from '../lib/client.js';
import { eq, ok } from '../lib/assert.js';

export default async function idempotency(ctx) {
  const svc = getServiceClient();
  const idemKey = uuid();

  // First submission
  const body = {
    bets: [{ event_id: ctx.eventIds[0], market_id: ctx.marketIds[0], side: 'a', odds: -110, stake: '15' }],
    player_id: ctx.playerId,
    bookie_id: ctx.bookieId,
    idempotency_key: idemKey,
  };

  const { status: s1, data: d1 } = await callEdge('submit_bets', body, ctx.playerToken);
  eq(s1, 200, 'first submission → 200');
  eq(d1?.success, true, 'first submission success');
  const firstBetId = d1?.bets?.[0]?.id;
  ok(firstBetId, 'first bet ID returned');

  // Same idempotency key → cached response
  const { status: s2, data: d2 } = await callEdge('submit_bets', body, ctx.playerToken);
  eq(s2, 200, 'duplicate submission → 200');
  eq(d2?.success, true, 'duplicate returns success');

  // Verify only 1 bet created (not 2)
  const { data: bets } = await svc
    .from('bets')
    .select('id')
    .eq('player_id', ctx.playerId)
    .eq('stake', 15);
  // Filter to bets with stake=15 to isolate this test
  const matchingBets = bets?.filter(b => true) || [];
  eq(matchingBets.length, 1, 'only 1 bet created despite 2 calls');

  // Different body, same key → still cached first response
  const { status: s3, data: d3 } = await callEdge('submit_bets', {
    ...body,
    bets: [{ event_id: ctx.eventIds[1], market_id: ctx.marketIds[3], side: 'b', odds: 100, stake: '25' }],
  }, ctx.playerToken);
  eq(s3, 200, 'different body same key → 200 (cached)');

  // Idempotency on adjust_balance
  const adjKey = uuid();
  const uniqueReason = `idempotency_test_${adjKey.substring(0, 8)}`;
  const adjBody = {
    player_id: ctx.playerId,
    amount: '0.01',
    reason: uniqueReason,
    type: 'adjustment',
    idempotency_key: adjKey,
  };
  const { status: a1 } = await callEdge('adjust_balance', adjBody, ctx.bookieToken);
  eq(a1, 200, 'adjust_balance first call → 200');

  const { status: a2 } = await callEdge('adjust_balance', adjBody, ctx.bookieToken);
  eq(a2, 200, 'adjust_balance duplicate → 200 (cached)');

  // Verify only 1 ledger entry for this specific description (avoids matching stale entries)
  const { data: entries } = await svc
    .from('ledger_entries')
    .select('id')
    .eq('player_id', ctx.playerId)
    .eq('description', uniqueReason);
  eq(entries?.length, 1, 'only 1 ledger entry despite 2 adjust_balance calls');
}
