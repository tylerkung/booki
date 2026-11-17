import { callEdge, uuid, getServiceClient, signInFresh } from '../lib/client.js';
import { eq, ok, neq } from '../lib/assert.js';

export default async function inviteFlow(ctx) {
  const svc = getServiceClient();

  // Create invite
  const { status: createStatus, data: createData } = await callEdge('create_invite', {
    idempotency_key: uuid(),
  }, ctx.bookieToken);

  eq(createStatus, 200, 'create_invite → 200');
  eq(createData?.success, true, 'create_invite success');
  ok(createData?.invite_code, `invite code: ${createData?.invite_code}`);
  ok(createData?.invite_id, 'invite_id returned');

  const inviteCode = createData?.invite_code;

  // Find or create a claimer auth user
  const claimEmail = `test_stress_claimer@test.local`;
  const { data: existingUsers } = await svc.auth.admin.listUsers({ perPage: 1000 });
  let claimerUserId;
  const existingClaimer = existingUsers?.users?.find(u => u.email === claimEmail);
  if (existingClaimer) {
    claimerUserId = existingClaimer.id;
    await svc.auth.admin.updateUserById(claimerUserId, { password: 'TestPass123!' });
  } else {
    const { data: newUser, error: createErr } = await svc.auth.admin.createUser({
      email: claimEmail, password: 'TestPass123!', email_confirm: true,
    });
    if (createErr) {
      ok(false, `claimer creation failed: ${createErr.message}`);
      return;
    }
    claimerUserId = newUser?.user?.id;
  }
  ok(claimerUserId, `claimer auth user: ${claimerUserId?.substring(0, 8)}`);

  // IMPORTANT: Clean up all existing player records for this auth user
  // claim_invite returns 409 "already_in_group" if user has any existing player record
  const { data: existingPlayers } = await svc.from('players').select('id').eq('auth_user_id', claimerUserId);
  for (const ep of existingPlayers || []) {
    try { await svc.from('bets').delete().eq('player_id', ep.id); } catch (e) {}
    try { await svc.from('ledger_entries').delete().eq('player_id', ep.id); } catch (e) {}
    try { await svc.from('players').delete().eq('id', ep.id); } catch (e) {}
  }
  // Also clean up any bookie record for this user (would also block claiming)
  try { await svc.from('bookies').delete().eq('auth_user_id', claimerUserId); } catch (e) {}

  // Confirmed accounts must present their own user JWT. The anon key is not one.
  const claimerToken = await signInFresh(claimEmail, 'TestPass123!');

  // Claim invite
  const { status: claimStatus, data: claimData } = await callEdge('claim_invite', {
    invite_code: inviteCode,
    auth_user_id: claimerUserId,
    idempotency_key: uuid(),
  }, claimerToken);

  if (claimStatus !== 200) console.log(`    debug claim: ${JSON.stringify(claimData)}`);
  eq(claimStatus, 200, 'claim_invite → 200');
  eq(claimData?.success, true, 'claim_invite success');
  ok(claimData?.player_id, 'player_id returned');
  eq(claimData?.bookie_id, ctx.bookieId, 'linked to correct bookie');

  // Verify player record
  if (claimData?.player_id) {
    const { data: player } = await svc.from('players').select('*').eq('id', claimData.player_id).single();
    ok(player, 'player record created');
    eq(player?.bookie_id, ctx.bookieId, 'player bookie_id correct');
    eq(player?.auth_user_id, claimerUserId, 'player auth_user_id correct');
    eq(player?.credit_limit, 1000, 'default credit limit applied (1000)');
  }

  // Claim same invite again with different user → 409
  {
    const claimEmail2 = `test_stress_claimer2@test.local`;
    let claimer2Id;
    const existing2 = existingUsers?.users?.find(u => u.email === claimEmail2);
    if (existing2) {
      claimer2Id = existing2.id;
      await svc.auth.admin.updateUserById(claimer2Id, { password: 'TestPass123!' });
    } else {
      const { data: nu2, error: nu2Err } = await svc.auth.admin.createUser({
        email: claimEmail2, password: 'TestPass123!', email_confirm: true,
      });
      if (nu2Err) { console.log(`    (skip re-claim test: ${nu2Err.message})`); }
      claimer2Id = nu2?.user?.id;
    }

    if (claimer2Id) {
      // Clean up claimer2's player records too
      const { data: c2Players } = await svc.from('players').select('id').eq('auth_user_id', claimer2Id);
      for (const ep of c2Players || []) {
        try { await svc.from('bets').delete().eq('player_id', ep.id); } catch (e) {}
        try { await svc.from('ledger_entries').delete().eq('player_id', ep.id); } catch (e) {}
        try { await svc.from('players').delete().eq('id', ep.id); } catch (e) {}
      }
      try { await svc.from('bookies').delete().eq('auth_user_id', claimer2Id); } catch (e) {}

      const claimer2Token = await signInFresh(claimEmail2, 'TestPass123!');
      const { status: forged } = await callEdge('claim_invite', {
        invite_code: inviteCode,
        auth_user_id: claimerUserId,
        idempotency_key: uuid(),
      }, claimer2Token);
      eq(forged, 403, 'claim_invite JWT differing from auth_user_id → 403');

      const { status: forgedPlayer } = await callEdge('claim_player', {
        invite_code: 'ZZZZZZZZ',
        auth_user_id: claimerUserId,
      }, claimer2Token);
      eq(forgedPlayer, 403, 'claim_player JWT differing from auth_user_id → 403');

      const { status: reClaimStatus } = await callEdge('claim_invite', {
        invite_code: inviteCode,
        auth_user_id: claimer2Id,
        idempotency_key: uuid(),
      }, claimer2Token);
      eq(reClaimStatus, 409, 're-claim same invite → 409');
    }
  }

  // Invalid invite code → 404
  {
    const { status } = await callEdge('claim_invite', {
      invite_code: 'ZZZZZZZZ',
      auth_user_id: claimerUserId,
    }, claimerToken);
    eq(status, 404, 'invalid invite code → 404');
  }

  // A confirmed account with no user JWT is not the iOS interim path.
  {
    const { status } = await callEdge('claim_invite', {
      invite_code: 'ZZZZZZZZ',
      auth_user_id: claimerUserId,
    });
    eq(status, 401, 'claim_invite confirmed account, no user JWT → 401');

    const { status: playerStatus } = await callEdge('claim_player', {
      invite_code: 'ZZZZZZZZ',
      auth_user_id: claimerUserId,
    });
    eq(playerStatus, 401, 'claim_player confirmed account, no user JWT → 401');
  }

  // Interim: unconfirmed, not an organizer, no user JWT. The lookup runs and
  // the email stays unconfirmed. An organizer is refused even if unconfirmed.
  {
    const freshEmail = `test_stress_claimauth_${Date.now()}@test.local`;
    const { data: fresh, error: freshErr } = await svc.auth.admin.createUser({
      email: freshEmail, password: 'TestPass123!', email_confirm: false,
    });
    if (freshErr || !fresh?.user?.id) {
      ok(false, `unconfirmed user: ${freshErr?.message || 'no id'}`);
    } else {
      const freshId = fresh.user.id;
      try {
        const { status, data } = await callEdge('claim_player', {
          invite_code: 'ZZZZZZZZ',
          auth_user_id: freshId,
        });
        eq(status, 404, 'interim claim_player with a bad code reaches the lookup');
        eq(data?.error, 'Invalid invite code', 'bad code is not an auth failure');
        const { data: still } = await svc.auth.admin.getUserById(freshId);
        ok(!still?.user?.email_confirmed_at, 'interim path does not confirm email');

        const { error: bookErr } = await svc.from('bookies').insert({
          id: uuid(), auth_user_id: freshId, name: 'test_stress_claimauth_org', tier: 'free',
        });
        if (bookErr) {
          ok(false, `organizer row: ${bookErr.message}`);
        } else {
          const { data: orgInvite } = await callEdge('create_invite', {
            idempotency_key: uuid(),
          }, ctx.bookieToken);
          const { status: orgStatus } = await callEdge('claim_invite', {
            invite_code: orgInvite?.invite_code,
            auth_user_id: freshId,
            idempotency_key: uuid(),
          });
          eq(orgStatus, 401, 'unconfirmed organizer, no user JWT → 401');
          if (orgInvite?.invite_id) {
            const { data: inv } = await svc.from('invites')
              .select('claimed_at').eq('id', orgInvite.invite_id).maybeSingle();
            ok(!inv?.claimed_at, 'rejected organizer claim did not consume the invite');
            try { await svc.from('invites').delete().eq('id', orgInvite.invite_id); } catch (e) {}
          }
        }
      } finally {
        try { await svc.from('bookies').delete().eq('auth_user_id', freshId); } catch (e) {}
        try { await svc.auth.admin.deleteUser(freshId); } catch (e) {}
      }
    }
  }

  // Create invite with no auth → 401
  {
    const { status } = await callEdge('create_invite', { idempotency_key: uuid() });
    eq(status, 401, 'create_invite no auth → 401');
  }

  // Cleanup: remove claimed player (keep auth user for reuse)
  if (claimData?.player_id) {
    try { await svc.from('bets').delete().eq('player_id', claimData.player_id); } catch (e) {}
    try { await svc.from('ledger_entries').delete().eq('player_id', claimData.player_id); } catch (e) {}
    try { await svc.from('players').delete().eq('id', claimData.player_id); } catch (e) {}
  }
}
