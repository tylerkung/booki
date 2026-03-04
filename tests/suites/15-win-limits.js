import { callEdge, uuid, getServiceClient, signInFresh } from '../lib/client.js';
import { eq, ok } from '../lib/assert.js';

export default async function winLimits(ctx) {
  const svc = getServiceClient();

  // Note: win_limit / win_limit_action columns may or may not exist on the players table.
  // The edge function reads them but they'll be null if columns are absent.
  // This suite verifies that submission works normally without win limits,
  // and that the edge function doesn't crash when the columns are absent.

  // Submit bet normally with ctx player — should succeed without win limit enforcement
  {
    const { status, data } = await callEdge('submit_bets', {
      bets: [{ event_id: ctx.eventIds[0], market_id: ctx.marketIds[0], side: 'a', odds: -110, stake: '10' }],
      player_id: ctx.playerId,
      bookie_id: ctx.bookieId,
      idempotency_key: uuid(),
    }, ctx.playerToken);

    eq(status, 200, 'submit without win limit → 200');
    eq(data?.success, true, 'submit without win limit → success');
  }

  // Create a fresh isolated player to test credit-only limits
  const freshPlayerId = uuid();
  const freshEmail = `test_stress_winlimit@test.local`;

  // Find or create auth user (never delete — FK constraints prevent it)
  const { data: existingUsers } = await svc.auth.admin.listUsers({ perPage: 1000 });
  let freshUserId;
  const existing = existingUsers?.users?.find(u => u.email === freshEmail);
  if (existing) {
    freshUserId = existing.id;
    await svc.auth.admin.updateUserById(freshUserId, { password: 'TestPass123!' });
  } else {
    const { data: authUser, error: authErr } = await svc.auth.admin.createUser({
      email: freshEmail, password: 'TestPass123!', email_confirm: true,
    });
    if (authErr) { ok(false, `auth user creation failed: ${authErr.message}`); return; }
    freshUserId = authUser?.user?.id;
  }
  ok(freshUserId, `win limit test auth user: ${freshUserId?.substring(0, 8)}`);

  // Clean up any existing player for this auth user (with FK deps)
  const { data: existingPlayers } = await svc.from('players').select('id').eq('auth_user_id', freshUserId);
  for (const ep of existingPlayers || []) {
    try { await svc.from('bets').delete().eq('player_id', ep.id); } catch (e) {}
    try { await svc.from('ledger_entries').delete().eq('player_id', ep.id); } catch (e) {}
    try { await svc.from('players').delete().eq('id', ep.id); } catch (e) {}
  }

  // Insert fresh player
  const { error: insertErr } = await svc.from('players').insert({
    id: freshPlayerId,
    bookie_id: ctx.bookieId,
    auth_user_id: freshUserId,
    name: 'test_stress_WinLimitPlayer',
    status: 'active',
    credit_limit: 200,
  });
  if (insertErr) { ok(false, `player insert failed: ${insertErr.message}`); return; }

  const token = await signInFresh(freshEmail, 'TestPass123!');
  ok(token, 'win limit test player authenticated');

  // Multiple bets within credit limit
  {
    const { status, data } = await callEdge('submit_bets', {
      bets: [{ event_id: ctx.eventIds[0], market_id: ctx.marketIds[0], side: 'a', odds: -110, stake: '50' }],
      player_id: freshPlayerId,
      bookie_id: ctx.bookieId,
      idempotency_key: uuid(),
    }, token);

    if (status !== 200) console.log(`    debug: ${JSON.stringify(data)}`);
    eq(status, 200, '$50 bet with $200 credit → 200');
    eq(data?.success, true, '$50 bet accepted');
  }

  {
    const { status, data } = await callEdge('submit_bets', {
      bets: [{ event_id: ctx.eventIds[1], market_id: ctx.markets[3].id, side: 'a', odds: -110, stake: '50' }],
      player_id: freshPlayerId,
      bookie_id: ctx.bookieId,
      idempotency_key: uuid(),
    }, token);

    if (status !== 200) console.log(`    debug: ${JSON.stringify(data)}`);
    eq(status, 200, 'second $50 bet → 200');
    eq(data?.success, true, 'second $50 bet accepted');
  }

  // Cleanup
  try { await svc.from('bets').delete().eq('player_id', freshPlayerId); } catch (e) {}
  try { await svc.from('ledger_entries').delete().eq('player_id', freshPlayerId); } catch (e) {}
  try { await svc.from('players').delete().eq('id', freshPlayerId); } catch (e) {}
}
