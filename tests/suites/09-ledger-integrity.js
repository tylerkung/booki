import { callEdge, uuid, getServiceClient } from '../lib/client.js';
import { eq, ok, gte } from '../lib/assert.js';

export default async function ledgerIntegrity(ctx) {
  const svc = getServiceClient();

  // Fetch all ledger entries for our test player
  const { data: entries, error } = await svc
    .from('ledger_entries')
    .select('*')
    .eq('player_id', ctx.playerId)
    .order('created_at', { ascending: true });

  ok(!error, 'fetched ledger entries without error');
  gte(entries?.length || 0, 1, `found ${entries?.length} ledger entries`);

  // Verify hash chain integrity
  if (entries?.length >= 2) {
    let chainValid = true;
    for (let i = 1; i < entries.length; i++) {
      const prev = entries[i - 1];
      const curr = entries[i];
      if (curr.prev_hash && curr.prev_hash !== prev.entry_hash) {
        chainValid = false;
        console.log(`    Chain break at entry ${i}: prev_hash=${curr.prev_hash}, expected=${prev.entry_hash}`);
      }
    }
    ok(chainValid, 'hash chain is intact');

    // First entry should have null prev_hash
    eq(entries[0].prev_hash, null, 'first entry prev_hash is null');

    // All entries should have a hash
    const allHashed = entries.every(e => e.entry_hash);
    ok(allHashed, 'all entries have hash values');
  }

  // Attempt direct UPDATE on ledger_entries → should be blocked by trigger
  if (entries?.length >= 1) {
    const targetId = entries[0].id;
    const { error: updateErr } = await svc
      .from('ledger_entries')
      .update({ amount: 9999 })
      .eq('id', targetId);

    ok(updateErr, 'direct UPDATE on ledger_entries blocked by immutability trigger');
    if (updateErr) {
      ok(
        updateErr.message?.toLowerCase().includes('immut') || updateErr.code === 'P0001' || updateErr.message?.includes('cannot'),
        `immutability error message: ${updateErr.message?.substring(0, 80)}`
      );
    }
  }

  // Attempt direct DELETE on ledger_entries → should also be blocked
  if (entries?.length >= 1) {
    const targetId = entries[entries.length - 1].id;
    const { error: deleteErr } = await svc
      .from('ledger_entries')
      .delete()
      .eq('id', targetId);

    ok(deleteErr, 'direct DELETE on ledger_entries blocked by immutability trigger');
  }

  // Verify all entries have consistent bookie_id
  const allSameBookie = entries?.every(e => e.bookie_id === ctx.bookieId);
  ok(allSameBookie, 'all ledger entries belong to correct bookie');
}
