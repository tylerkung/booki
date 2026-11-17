import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { emitAuditEvent } from './audit.ts';
import { settleTicketOnce, type TicketLeg } from './parlay_claim.ts';

/**
 * The one parlay ledger write.
 *
 * refresh_live_scores and auto_refresh_games each used to insert their own
 * row, with an idempotency key that included Date.now(). This is that same
 * insert — one settlement ledger entry for the ticket, via the ledger table
 * the 015 settlement path already uses — keyed so a retry finds the first
 * one. There is no settle_parlay_tx RPC; settle_bet_tx prices a single bet's
 * own odds and would pay every leg separately, so a parlay must not go
 * through it.
 *
 * The claim is a conditional update to status `settling`. Only the run that
 * gets the rows back writes the ledger. Migration 063 is the unique guard;
 * this is the claim that exists until that migration is applied.
 *
 * A future double-payout guard should key this on the ticket id. A guard
 * that only looks at one leg, or that also allows settle_bet_tx on a parlay
 * leg, would pay the ticket twice.
 */

interface LegRow {
  id: string;
  ticket_id: string;
  bookie_id: string;
  player_id: string;
  stake: number | string;
  odds: number | string;
  status: string;
  grade_result: string | null;
}

export async function settleReadyParlays(client: SupabaseClient): Promise<number> {
  const { data: hooks, error } = await client
    .from('bets')
    .select('ticket_id')
    .eq('is_parlay', true)
    .in('status', ['graded', 'void']);

  if (error || !hooks || hooks.length === 0) return 0;

  const ticketIds = [...new Set(
    hooks.map((h: { ticket_id: string | null }) => h.ticket_id).filter((id): id is string => !!id),
  )];

  let settled = 0;

  for (const ticketId of ticketIds) {
    try {
      const { data: legs, error: legsError } = await client
        .from('bets')
        .select('id, ticket_id, bookie_id, player_id, stake, odds, status, grade_result')
        .eq('ticket_id', ticketId)
        .eq('is_parlay', true);

      if (legsError || !legs || legs.length === 0) continue;

      const rows = legs as LegRow[];
      const ticketLegs: TicketLeg[] = rows.map((leg) => ({
        id: leg.id,
        status: leg.status,
        grade_result: leg.grade_result,
        odds: Number(leg.odds),
        stake: Number(leg.stake),
        bookie_id: leg.bookie_id,
        player_id: leg.player_id,
      }));

      const attempt = await settleTicketOnce(ticketId, ticketLegs, {
        claim: async (ids, fromStatuses) => {
          const { data, error: claimError } = await client
            .from('bets')
            .update({ status: 'settling', updated_at: new Date().toISOString() })
            .in('id', ids)
            .in('status', fromStatuses)
            .select('id');
          if (claimError) {
            console.error(`Parlay ${ticketId}: claim failed`, claimError);
            return [];
          }
          return (data ?? []).map((row: { id: string }) => row.id);
        },
        revert: async (id, toStatus) => {
          const { error: revertError } = await client
            .from('bets')
            .update({ status: toStatus, updated_at: new Date().toISOString() })
            .eq('id', id)
            .eq('status', 'settling');
          if (revertError) console.error(`Parlay ${ticketId}: revert ${id} failed`, revertError);
        },
        writeLedger: async (entry) => {
          const { data: ledgerEntry, error: ledgerError } = await client
            .from('ledger_entries')
            .insert({
              bookie_id: entry.bookie_id,
              player_id: entry.player_id,
              bet_id: entry.bet_id,
              amount: entry.amount,
              type: 'settlement',
              description: entry.description,
            })
            .select('id')
            .single();
          if (ledgerError || !ledgerEntry) {
            console.error(`Parlay ${ticketId}: ledger insert failed`, ledgerError);
            return null;
          }

          const { data: bookie } = await client
            .from('bookies')
            .select('auth_user_id')
            .eq('id', entry.bookie_id)
            .maybeSingle();

          const { error: eventError } = await client.from('settlement_events').insert({
            bookie_id: entry.bookie_id,
            bet_id: entry.bet_id,
            mode: 'auto',
            actor_user_id: bookie?.auth_user_id ?? null,
            idempotency_key: entry.idempotency_key,
            ledger_entry_ids: [ledgerEntry.id],
          });
          if (eventError) console.error(`Parlay ${ticketId}: settlement_event failed`, eventError);

          if (bookie?.auth_user_id) {
            await emitAuditEvent(client, {
              bookieId: entry.bookie_id,
              actorUserId: bookie.auth_user_id,
              entityType: 'bet',
              entityId: entry.bet_id,
              actionType: 'settle',
              previousState: { ticket_id: ticketId, leg_count: rows.length },
              newState: {
                ticket_id: ticketId,
                payout: entry.amount,
                idempotency_key: entry.idempotency_key,
                ledger_entry_id: ledgerEntry.id,
              },
            });
          }
          return { id: ledgerEntry.id };
        },
        close: async (ids) => {
          const { error: updateError } = await client
            .from('bets')
            .update({ status: 'settled', updated_at: new Date().toISOString() })
            .in('id', ids)
            .eq('status', 'settling');
          if (updateError) {
            console.error(`Parlay ${ticketId}: failed to close legs`, updateError);
            return false;
          }
          return true;
        },
      });

      if (attempt === 'settled') {
        settled++;
        console.log(`Settled parlay ${ticketId}`);
      }
    } catch (err) {
      console.error(`Parlay ${ticketId}:`, err);
    }
  }

  return settled;
}
