import { getServiceClient } from './client.js';

const TEST_PREFIX = 'test_stress_';

async function safeDelete(query) {
  try { await query; } catch (e) { /* ignore */ }
}

export async function cleanup() {
  console.log('\n\x1b[36m▸ Cleaning up test data...\x1b[0m\n');
  const svc = getServiceClient();

  // Find test players
  const { data: testPlayers } = await svc.from('players').select('id').like('name', `${TEST_PREFIX}%`);
  const playerIds = testPlayers?.map(p => p.id) || [];

  // Find test bookies
  const { data: testBookies } = await svc.from('bookies').select('id, auth_user_id').like('name', `${TEST_PREFIX}%`);
  const bookieIds = testBookies?.map(b => b.id) || [];

  // Find test events
  const { data: testEvents } = await svc.from('events').select('id').like('external_id', `${TEST_PREFIX}%`);
  const eventIds = testEvents?.map(e => e.id) || [];

  // Delete transactional data in FK order
  for (const pid of playerIds) {
    await safeDelete(svc.from('settlement_events').delete().eq('bookie_id', pid));
    await safeDelete(svc.from('ledger_entries').delete().eq('player_id', pid));
    await safeDelete(svc.from('bets').delete().eq('player_id', pid));
  }

  // Idempotency keys + invites + policies
  for (const b of testBookies || []) {
    await safeDelete(svc.from('idempotency_keys').delete().eq('user_id', b.auth_user_id));
    await safeDelete(svc.from('invites').delete().eq('bookie_id', b.id));
    await safeDelete(svc.from('acceptance_policies').delete().eq('bookie_id', b.id));
    await safeDelete(svc.from('audit_events').delete().eq('actor_user_id', b.auth_user_id));
  }

  // Markets + events
  for (const eid of eventIds) {
    await safeDelete(svc.from('markets').delete().eq('event_id', eid));
  }
  if (eventIds.length) {
    await safeDelete(svc.from('events').delete().in('id', eventIds));
  }

  // Note: We intentionally DON'T delete auth users, bookies, or players
  // They get reused across test runs (auth user deletion has FK issues)

  console.log(`  Cleaned data for ${playerIds.length} players, ${eventIds.length} events`);
  console.log('');
}

if (process.argv[1]?.endsWith('cleanup.js')) {
  cleanup().then(() => process.exit(0)).catch(e => { console.error(e); process.exit(1); });
}
