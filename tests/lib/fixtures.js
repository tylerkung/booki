import { getServiceClient, uuid } from './client.js';

const TEST_PREFIX = 'test_stress_';
const TEST_BOOKIE_EMAIL = `${TEST_PREFIX}bookie@test.local`;
const TEST_PLAYER_EMAIL = `${TEST_PREFIX}player@test.local`;
const TEST_PLAYER2_EMAIL = `${TEST_PREFIX}player2@test.local`;
const TEST_PASSWORD = 'TestPass123!';

export const ctx = {
  bookieUserId: null,
  bookieToken: null,
  playerUserId: null,
  playerToken: null,
  player2UserId: null,
  player2Token: null,
  bookieId: null,
  bookie2Id: null,
  playerId: null,
  player2Id: null,
  eventIds: [],
  marketIds: [],
  events: [],
  markets: [],
};

export async function setup() {
  console.log('\n\x1b[36m▸ Setting up test fixtures...\x1b[0m\n');
  const svc = getServiceClient();

  // Clean stale test bets/ledger/markets/events (but keep auth users + bookies + players for reuse)
  await cleanStaleData(svc);

  // 1. Find-or-create auth users
  ctx.bookieUserId = await findOrCreateAuthUser(svc, TEST_BOOKIE_EMAIL);
  ctx.playerUserId = await findOrCreateAuthUser(svc, TEST_PLAYER_EMAIL);
  ctx.player2UserId = await findOrCreateAuthUser(svc, TEST_PLAYER2_EMAIL);

  // 2. Sign in to get tokens
  ctx.bookieToken = await signIn(TEST_BOOKIE_EMAIL);
  ctx.playerToken = await signIn(TEST_PLAYER_EMAIL);
  ctx.player2Token = await signIn(TEST_PLAYER2_EMAIL);

  // 3. Find-or-create bookie
  {
    const { data: existing } = await svc.from('bookies').select('id').eq('auth_user_id', ctx.bookieUserId).single();
    if (existing) {
      ctx.bookieId = existing.id;
      await svc.from('bookies').update({ tier: 'pro', subscription_status: 'active', default_credit_limit: 1000 }).eq('id', existing.id);
    } else {
      const id = uuid();
      const { error } = await svc.from('bookies').insert({
        id, auth_user_id: ctx.bookieUserId, name: `${TEST_PREFIX}Bookie`, tier: 'pro', subscription_status: 'active', default_credit_limit: 1000,
      });
      if (error) throw new Error(`Create bookie: ${error.message}`);
      ctx.bookieId = id;
    }
  }

  // 4. Find-or-create bookie2 (for cross-bookie isolation)
  {
    const { data: existing } = await svc.from('bookies').select('id').eq('auth_user_id', ctx.player2UserId).single();
    if (existing) {
      ctx.bookie2Id = existing.id;
    } else {
      const id = uuid();
      const { error } = await svc.from('bookies').insert({
        id, auth_user_id: ctx.player2UserId, name: `${TEST_PREFIX}Bookie2`, tier: 'free',
      });
      if (error) throw new Error(`Create bookie2: ${error.message}`);
      ctx.bookie2Id = id;
    }
  }

  // 5. Find-or-create player (linked to bookie)
  {
    const { data: existing } = await svc.from('players').select('id').eq('auth_user_id', ctx.playerUserId).single();
    if (existing) {
      ctx.playerId = existing.id;
      await svc.from('players').update({ bookie_id: ctx.bookieId, status: 'active', credit_limit: 1000 }).eq('id', existing.id);
    } else {
      const id = uuid();
      const { error } = await svc.from('players').insert({
        id, bookie_id: ctx.bookieId, auth_user_id: ctx.playerUserId, name: `${TEST_PREFIX}Player`, status: 'active', credit_limit: 1000,
      });
      if (error) throw new Error(`Create player: ${error.message}`);
      ctx.playerId = id;
    }
  }

  // 6. Find-or-create player2 (linked to bookie2)
  {
    const { data: existing } = await svc.from('players').select('id').eq('auth_user_id', ctx.player2UserId).single();
    if (existing) {
      ctx.player2Id = existing.id;
      await svc.from('players').update({ bookie_id: ctx.bookie2Id, status: 'active', credit_limit: 1000 }).eq('id', existing.id);
    } else {
      const id = uuid();
      const { error } = await svc.from('players').insert({
        id, bookie_id: ctx.bookie2Id, auth_user_id: ctx.player2UserId, name: `${TEST_PREFIX}Player2`, status: 'active', credit_limit: 1000,
      });
      if (error) throw new Error(`Create player2: ${error.message}`);
      ctx.player2Id = id;
    }
  }

  // 7. Create fresh events + markets (always new)
  const now = new Date();
  const tomorrow = new Date(now.getTime() + 24 * 60 * 60 * 1000);
  const eventData = [
    { id: uuid(), sport: 'basketball_nba', league: 'NBA', name: `${TEST_PREFIX}Lakers vs Celtics`, home_team: `${TEST_PREFIX}Lakers`, away_team: `${TEST_PREFIX}Celtics`, start_time: tomorrow.toISOString(), status: 'upcoming', external_id: `${TEST_PREFIX}evt1_${Date.now()}` },
    { id: uuid(), sport: 'football_nfl', league: 'NFL', name: `${TEST_PREFIX}Chiefs vs Eagles`, home_team: `${TEST_PREFIX}Chiefs`, away_team: `${TEST_PREFIX}Eagles`, start_time: tomorrow.toISOString(), status: 'upcoming', external_id: `${TEST_PREFIX}evt2_${Date.now()}` },
    { id: uuid(), sport: 'basketball_nba', league: 'NBA', name: `${TEST_PREFIX}Warriors vs Nets`, home_team: `${TEST_PREFIX}Warriors`, away_team: `${TEST_PREFIX}Nets`, start_time: tomorrow.toISOString(), status: 'upcoming', external_id: `${TEST_PREFIX}evt3_${Date.now()}` },
  ];
  const { error: eErr } = await svc.from('events').insert(eventData);
  if (eErr) throw new Error(`Create events: ${eErr.message}`);
  ctx.eventIds = eventData.map(e => e.id);
  ctx.events = eventData;

  const marketData = [];
  for (const evt of eventData) {
    marketData.push(
      { id: uuid(), event_id: evt.id, type: 'h2h', side_a: evt.home_team, side_b: evt.away_team, odds_a: -110, odds_b: 100 },
      { id: uuid(), event_id: evt.id, type: 'spreads', side_a: evt.home_team, side_b: evt.away_team, odds_a: -110, odds_b: -110 },
      { id: uuid(), event_id: evt.id, type: 'totals', side_a: 'Over', side_b: 'Under', odds_a: -110, odds_b: -110 },
    );
  }
  const { error: mErr } = await svc.from('markets').insert(marketData);
  if (mErr) throw new Error(`Create markets: ${mErr.message}`);
  ctx.marketIds = marketData.map(m => m.id);
  ctx.markets = marketData;

  // 8. Acceptance policy (upsert)
  const { error: apErr } = await svc.from('acceptance_policies').upsert({
    bookie_id: ctx.bookieId, max_stake: 500, auto_accept_enabled: true, auto_accept_new_players: true,
  }, { onConflict: 'bookie_id' });
  if (apErr) console.log(`  (acceptance_policies: ${apErr.message})`);

  console.log(`  Bookie: ${ctx.bookieId}`);
  console.log(`  Player: ${ctx.playerId}`);
  console.log(`  Player2: ${ctx.player2Id}`);
  console.log(`  Events: ${ctx.eventIds.length}, Markets: ${ctx.marketIds.length}`);
  console.log('');
}

async function findOrCreateAuthUser(svc, email) {
  const { data: existingUsers } = await svc.auth.admin.listUsers({ perPage: 1000 });
  const existing = existingUsers?.users?.find(u => u.email === email);
  if (existing) {
    await svc.auth.admin.updateUserById(existing.id, { password: TEST_PASSWORD, email_confirm: true });
    return existing.id;
  }
  const { data, error } = await svc.auth.admin.createUser({ email, password: TEST_PASSWORD, email_confirm: true });
  if (error) throw new Error(`Create user ${email}: ${error.message}`);
  return data.user.id;
}

async function signIn(email) {
  const { createClient } = await import('@supabase/supabase-js');
  const anonClient = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_ANON_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data, error } = await anonClient.auth.signInWithPassword({ email, password: TEST_PASSWORD });
  if (error) throw new Error(`Sign in ${email}: ${error.message}`);
  return data.session.access_token;
}

async function cleanStaleData(svc) {
  // Clean bets, ledger entries, markets, events from previous runs
  // Keep auth users, bookies, players (reused across runs)
  const { data: testPlayers } = await svc.from('players').select('id').like('name', `${TEST_PREFIX}%`);
  for (const p of testPlayers || []) {
    try { await svc.from('settlement_events').delete().eq('bookie_id', p.bookie_id || 'x'); } catch (e) {}
    try { await svc.from('ledger_entries').delete().eq('player_id', p.id); } catch (e) {}
    try { await svc.from('bets').delete().eq('player_id', p.id); } catch (e) {}
  }
  // Clean test events/markets
  const { data: testEvents } = await svc.from('events').select('id').like('external_id', `${TEST_PREFIX}%`);
  for (const e of testEvents || []) {
    try { await svc.from('markets').delete().eq('event_id', e.id); } catch (e2) {}
  }
  if (testEvents?.length) {
    const ids = testEvents.map(e => e.id);
    try { await svc.from('events').delete().in('id', ids); } catch (e) {}
  }
  // Clean idempotency keys for test users
  const { data: testBookies } = await svc.from('bookies').select('id, auth_user_id').like('name', `${TEST_PREFIX}%`);
  for (const b of testBookies || []) {
    try { await svc.from('idempotency_keys').delete().eq('user_id', b.auth_user_id); } catch (e) {}
    try { await svc.from('invites').delete().eq('bookie_id', b.id); } catch (e) {}
    try { await svc.from('acceptance_policies').delete().eq('bookie_id', b.id); } catch (e) {}
  }
}

export { TEST_PREFIX, TEST_PASSWORD, TEST_BOOKIE_EMAIL, TEST_PLAYER_EMAIL, TEST_PLAYER2_EMAIL };
