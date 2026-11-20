import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { parlaySettlementKey } from './parlay_settle.ts';
import { settleParlayTx } from './settle_tx.ts';

/**
 * The one parlay settlement entry point.
 *
 * refresh_live_scores, auto_refresh_games, and grade_player_props all call
 * this. The decision, the ledger row, the settlement event, and the leg
 * status change happen inside settle_parlay_tx, one transaction. There is
 * no intermediate status and no claim to roll back by hand: a failed call
 * leaves the ticket as it was, and a retry finds the active settlement.
 */

export async function settleReadyParlays(client: SupabaseClient): Promise<number> {
  const { data: hooks, error } = await client
    .from('bets')
    .select('ticket_id, bookie_id')
    .eq('is_parlay', true)
    .in('status', ['graded', 'void', 'accepted', 'pending']);

  if (error || !hooks || hooks.length === 0) return 0;

  const tickets = new Map<string, string>();
  for (const hook of hooks as { ticket_id: string | null; bookie_id: string }[]) {
    if (hook.ticket_id && !tickets.has(hook.ticket_id)) {
      tickets.set(hook.ticket_id, hook.bookie_id);
    }
  }

  let settled = 0;

  for (const [ticketId, bookieId] of tickets) {
    try {
      const { data: bookie } = await client
        .from('bookies')
        .select('auth_user_id')
        .eq('id', bookieId)
        .maybeSingle();

      const posted = await settleParlayTx(client, {
        ticketId,
        actorUserId: bookie?.auth_user_id ?? null,
        idempotencyKey: parlaySettlementKey(ticketId, 1),
        mode: 'auto',
      });

      if (posted.error) {
        console.error(`Parlay ${ticketId}: ${posted.error}`);
        continue;
      }
      if (posted.result?.action === 'wait' || posted.result?.idempotent) {
        continue;
      }
      if (posted.result?.ledger_entry) {
        settled++;
        console.log(
          `Settled parlay ${ticketId}: ${posted.result.outcome} amount=${posted.result.ledger_entry.amount}`,
        );
      }
    } catch (err) {
      console.error(`Parlay ${ticketId}:`, err);
    }
  }

  return settled;
}
