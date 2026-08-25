import { callEdge, uuid, getServiceClient } from '../lib/client.js';
import { eq, ok, neq } from '../lib/assert.js';

/**
 * Addressed (email) invites, and the signup path that claims them.
 *
 * Suite 12 covers bearer codes, which were never the problem. In August every
 * web invite failed and three invitees ended up as their own organizers: they
 * were emailed a link, could not use it, signed up directly, and
 * detectUserRole() saw no bookie and no player and concluded "new organizer".
 * None of that path had a test, which is why it stayed broken long enough to
 * need migration 036 to repair it.
 *
 * This covers what that incident actually exercised:
 *   - an invite addressed to an email
 *   - claiming it at signup with no code, by verified email alone
 *   - only the addressee may claim an addressed invite
 *   - a bearer code expires; an addressee is not locked out by our own bug
 */
export default async function inviteEmailFlow(ctx) {
  const svc = getServiceClient();
  const stamp = Date.now();
  const inviteeEmail = `test_stress_invitee_${stamp}@test.local`;
  const strangerEmail = `test_stress_stranger_${stamp}@test.local`;
  const created = { users: [], invites: [], players: [] };

  const mkUser = async (email) => {
    const { data, error } = await svc.auth.admin.createUser({
      email, password: 'TestPass123!', email_confirm: true,
    });
    if (error) { ok(false, `create ${email}: ${error.message}`); return null; }
    created.users.push(data.user.id);
    return data.user.id;
  };

  try {
    // ── an invite addressed to a specific person ─────────────────────────
    const { status: cStatus, data: cData } = await callEdge('create_invite', {
      email: inviteeEmail,
      idempotency_key: uuid(),
    }, ctx.bookieToken);

    eq(cStatus, 200, 'create_invite with email → 200');
    ok(cData?.invite_code, `addressed invite code: ${cData?.invite_code}`);
    if (cData?.invite_id) created.invites.push(cData.invite_id);

    // The web modal read response.code for months and always showed undefined.
    // The contract is invite_code; assert it so that cannot regress silently.
    ok('invite_code' in (cData || {}), 'response uses invite_code, not code');

    const { data: inviteRow } = await svc
      .from('invites').select('email, claimed_at, expires_at')
      .eq('invite_code', cData.invite_code).single();
    eq(inviteRow?.email?.toLowerCase(), inviteeEmail, 'invite stores the addressee');

    // ── a stranger may not claim an addressed invite ─────────────────────
    const strangerId = await mkUser(strangerEmail);
    if (strangerId) {
      const { status, data } = await callEdge('claim_invite', {
        invite_code: cData.invite_code,
        auth_user_id: strangerId,
        idempotency_key: uuid(),
      });
      eq(status, 403, 'addressed invite claimed by a stranger → 403');
      eq(data?.error, 'This invite was sent to a different email address',
        'stranger is told why');
    }

    // ── the addressee claims it with NO CODE, by verified email alone ────
    // This is the path that did not exist in August. Someone who cannot use
    // their link has no code to type; the only thing they carry is the
    // address the invite was sent to.
    const inviteeId = await mkUser(inviteeEmail);
    if (inviteeId) {
      const { status, data } = await callEdge('claim_invite', {
        auth_user_id: inviteeId,
        idempotency_key: uuid(),
      });
      eq(status, 200, 'claim by verified email, no code → 200');
      eq(data?.success, true, 'claim by email succeeds');
      eq(data?.bookie_id, ctx.bookieId, 'invitee joined the inviting organizer');
      if (data?.player_id) {
        created.players.push(data.player_id);
        const { data: p } = await svc.from('players')
          .select('bookie_id, auth_user_id, email, claimed_at')
          .eq('id', data.player_id).single();
        eq(p?.bookie_id, ctx.bookieId, 'player row points at the organizer');
        eq(p?.auth_user_id, inviteeId, 'player row is linked to the account');
        ok(p?.claimed_at, 'player row is marked claimed');
      }

      // The whole point: they are a MEMBER, not an accidental organizer.
      const { data: strayBook } = await svc.from('bookies')
        .select('id').eq('auth_user_id', inviteeId).maybeSingle();
      eq(strayBook, null, 'invitee did NOT get a book of their own');

      // And the invite is now spent.
      const { data: after } = await svc.from('invites')
        .select('claimed_at, claimed_by_player_id')
        .eq('invite_code', cData.invite_code).single();
      ok(after?.claimed_at, 'invite marked claimed');
      eq(after?.claimed_by_player_id, data?.player_id, 'invite records who claimed it');
    }

    // ── expiry: a bearer code expires, an addressee does not ─────────────
    {
      const { data: bearer } = await callEdge('create_invite', {
        idempotency_key: uuid(),
      }, ctx.bookieToken);
      if (bearer?.invite_id) {
        created.invites.push(bearer.invite_id);
        await svc.from('invites')
          .update({ expires_at: new Date(Date.now() - 60_000).toISOString() })
          .eq('id', bearer.invite_id);

        const someoneId = await mkUser(`test_stress_late_${stamp}@test.local`);
        if (someoneId) {
          const { status } = await callEdge('claim_invite', {
            invite_code: bearer.invite_code,
            auth_user_id: someoneId,
            idempotency_key: uuid(),
          });
          eq(status, 410, 'expired bearer code → 410');
        }
      }

      const addressedEmail = `test_stress_late_addressee_${stamp}@test.local`;
      const { data: addressed } = await callEdge('create_invite', {
        email: addressedEmail, idempotency_key: uuid(),
      }, ctx.bookieToken);
      if (addressed?.invite_id) {
        created.invites.push(addressed.invite_id);
        await svc.from('invites')
          .update({ expires_at: new Date(Date.now() - 60_000).toISOString() })
          .eq('id', addressed.invite_id);

        const lateId = await mkUser(addressedEmail);
        if (lateId) {
          // Expiry exists to limit stale shared codes, not to lock the
          // addressee out of an invite that names them — especially when our
          // own broken link is why it lapsed.
          const { status, data } = await callEdge('claim_invite', {
            auth_user_id: lateId, idempotency_key: uuid(),
          });
          eq(status, 200, 'expired ADDRESSED invite still claimable by addressee');
          if (data?.player_id) created.players.push(data.player_id);
        }
      }
    }

    // ── no pending invite for this address → 404, not a silent organizer ─
    {
      const orphanId = await mkUser(`test_stress_orphan_${stamp}@test.local`);
      if (orphanId) {
        const { status, data } = await callEdge('claim_invite', {
          auth_user_id: orphanId, idempotency_key: uuid(),
        });
        eq(status, 404, 'no invite for this email → 404');
        eq(data?.error, 'No pending invite for this email', 'says why');
      }
    }
  } finally {
    // Leave nothing behind: these accounts would otherwise read as dormant
    // organizers and land in the follow-up email's audience.
    for (const id of created.players) {
      try { await svc.from('bets').delete().eq('player_id', id); } catch {}
      try { await svc.from('ledger_entries').delete().eq('player_id', id); } catch {}
      try { await svc.from('players').delete().eq('id', id); } catch {}
    }
    for (const id of created.invites) {
      try { await svc.from('invites').delete().eq('id', id); } catch {}
    }
    for (const id of created.users) {
      try { await svc.from('players').delete().eq('auth_user_id', id); } catch {}
      try { await svc.from('bookies').delete().eq('auth_user_id', id); } catch {}
      try { await svc.auth.admin.deleteUser(id); } catch {}
    }
  }
}
