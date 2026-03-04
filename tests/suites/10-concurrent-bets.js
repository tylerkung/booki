import { callEdge, uuid, getServiceClient } from '../lib/client.js';
import { eq, ok, lte } from '../lib/assert.js';

export default async function concurrentBets(ctx) {
  const svc = getServiceClient();

  const COUNT = 10;

  // Get current bet count
  const { count: beforeCount } = await svc
    .from('bets')
    .select('id', { count: 'exact', head: true })
    .eq('player_id', ctx.playerId);

  // Fire 10 simultaneous bet submissions (each with unique idempotency key)
  const promises = Array.from({ length: COUNT }, (_, i) =>
    callEdge('submit_bets', {
      bets: [{ event_id: ctx.eventIds[i % 3], market_id: ctx.markets[(i % 3) * 3].id, side: 'a', odds: -110, stake: '5' }],
      player_id: ctx.playerId,
      bookie_id: ctx.bookieId,
      idempotency_key: uuid(),
    }, ctx.playerToken)
  );

  const results = await Promise.all(promises);

  // Count successes
  const successes = results.filter(r => r.status === 200 && r.data?.success).length;
  ok(successes >= 1, `${successes}/${COUNT} concurrent bets succeeded`);

  // Get current bet count
  const { count: afterCount } = await svc
    .from('bets')
    .select('id', { count: 'exact', head: true })
    .eq('player_id', ctx.playerId);

  const newBets = (afterCount || 0) - (beforeCount || 0);
  eq(newBets, successes, `exactly ${successes} new bets in DB (no duplicates, no lost writes)`);

  // Verify total stakes don't exceed credit limit
  const { data: openBets } = await svc
    .from('bets')
    .select('stake')
    .eq('player_id', ctx.playerId)
    .in('status', ['accepted', 'pending']);
  const totalStake = openBets?.reduce((sum, b) => sum + parseFloat(b.stake || 0), 0) || 0;
  lte(totalStake, 1000, `total open stakes ($${totalStake}) ≤ credit limit ($1000)`);
}
