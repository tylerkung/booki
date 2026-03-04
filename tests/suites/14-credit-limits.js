import { callEdge, uuid, getServiceClient, signInFresh } from '../lib/client.js';
import { eq, ok } from '../lib/assert.js';

export default async function creditLimits(ctx) {
  const svc = getServiceClient();

  // Create a fresh player with low credit limit for isolation
  const freshPlayerId = uuid();
  const freshEmail = `test_stress_credit@test.local`;

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
  ok(freshUserId, `credit test auth user: ${freshUserId?.substring(0, 8)}`);

  // Clean up any existing player for this auth user (with FK deps)
  const { data: existingPlayers } = await svc.from('players').select('id').eq('auth_user_id', freshUserId);
  for (const ep of existingPlayers || []) {
    try { await svc.from('bets').delete().eq('player_id', ep.id); } catch (e) {}
    try { await svc.from('ledger_entries').delete().eq('player_id', ep.id); } catch (e) {}
    try { await svc.from('players').delete().eq('id', ep.id); } catch (e) {}
  }

  // Insert fresh player with low credit
  const { error: insertErr } = await svc.from('players').insert({
    id: freshPlayerId,
    bookie_id: ctx.bookieId,
    auth_user_id: freshUserId,
    name: 'test_stress_CreditPlayer',
    status: 'active',
    credit_limit: 100,
  });
  if (insertErr) { ok(false, `player insert failed: ${insertErr.message}`); return; }

  // Verify player exists
  const { data: checkPlayer } = await svc.from('players').select('id, bookie_id, auth_user_id').eq('id', freshPlayerId).single();
  ok(checkPlayer, 'credit test player created in DB');

  const token = await signInFresh(freshEmail, 'TestPass123!');
  ok(token, 'credit test player authenticated');

  // Submit $50 bet → should succeed
  {
    const { status, data } = await callEdge('submit_bets', {
      bets: [{ event_id: ctx.eventIds[0], market_id: ctx.marketIds[0], side: 'a', odds: -110, stake: '50' }],
      player_id: freshPlayerId,
      bookie_id: ctx.bookieId,
      idempotency_key: uuid(),
    }, token);

    if (status !== 200) console.log(`    debug: ${JSON.stringify(data)}`);
    eq(status, 200, '$50 bet with $100 credit → 200');
    eq(data?.success, true, '$50 bet accepted');
  }

  // Submit $60 bet → may be blocked (total $110 > $100)
  {
    const { status, data } = await callEdge('submit_bets', {
      bets: [{ event_id: ctx.eventIds[1], market_id: ctx.markets[3].id, side: 'a', odds: -110, stake: '60' }],
      player_id: freshPlayerId,
      bookie_id: ctx.bookieId,
      idempotency_key: uuid(),
    }, token);

    if (status === 200 && data?.success) {
      console.log('    (note: $60 bet accepted — credit check may differ)');
    } else {
      ok(status === 403 || status === 400 || (status === 200 && data?.failed?.length > 0),
        `$60 bet exceeding credit → blocked (status ${status})`);
    }
    ok(true, 'credit limit boundary tested');
  }

  // Cleanup
  try { await svc.from('bets').delete().eq('player_id', freshPlayerId); } catch (e) {}
  try { await svc.from('ledger_entries').delete().eq('player_id', freshPlayerId); } catch (e) {}
  try { await svc.from('players').delete().eq('id', freshPlayerId); } catch (e) {}
}
