import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { emitAuditEvent } from './audit.ts';
import { decideParlay, legStanding, parlaySettlementKey } from './parlay_settle.ts';

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
      const decision = decideParlay(
        Number(rows[0].stake),
        rows.map((leg) => ({
          status: leg.status,
          grade_result: leg.grade_result,
          odds: Number(leg.odds),
        })),
      );

      if (decision.action !== 'settle' || decision.outcome == null || decision.amount == null) {
        continue;
      }

      const legIds = rows.map((leg) => leg.id);
      const key = parlaySettlementKey(ticketId, 1);

      const { data: existingEvent } = await client
        .from('settlement_events')
        .select('id')
        .eq('idempotency_key', key)
        .limit(1);

      const { data: existingLedger } = await client
        .from('ledger_entries')
        .select('id')
        .in('bet_id', legIds)
        .eq('type', 'settlement')
        .limit(1);

      const alreadyPosted = (existingEvent?.length ?? 0) > 0 || (existingLedger?.length ?? 0) > 0;
      let ledgerId: string | null = existingLedger?.[0]?.id ?? null;

      if (!alreadyPosted) {
        const description = decision.outcome === 'win'
          ? `Multi-Pick won (${decision.activeLegs} of ${rows.length} legs)`
          : decision.outcome === 'loss'
            ? `Multi-Pick lost (${rows.length} legs)`
            : `Multi-Pick voided (${rows.length} legs, stake refunded)`;

        const { data: ledgerEntry, error: ledgerError } = await client
          .from('ledger_entries')
          .insert({
            bookie_id: rows[0].bookie_id,
            player_id: rows[0].player_id,
            bet_id: rows[0].id,
            amount: decision.amount,
            type: 'settlement',
            description,
          })
          .select('id')
          .single();

        if (ledgerError || !ledgerEntry) {
          console.error(`Parlay ${ticketId}: ledger insert failed`, ledgerError);
          continue;
        }
        ledgerId = ledgerEntry.id;

        const { data: bookie } = await client
          .from('bookies')
          .select('auth_user_id')
          .eq('id', rows[0].bookie_id)
          .maybeSingle();

        const { error: eventError } = await client.from('settlement_events').insert({
          bookie_id: rows[0].bookie_id,
          bet_id: rows[0].id,
          mode: 'auto',
          actor_user_id: bookie?.auth_user_id ?? null,
          idempotency_key: key,
          ledger_entry_ids: [ledgerId],
        });
        if (eventError) console.error(`Parlay ${ticketId}: settlement_event failed`, eventError);

        if (bookie?.auth_user_id) {
          await emitAuditEvent(client, {
            bookieId: rows[0].bookie_id,
            actorUserId: bookie.auth_user_id,
            entityType: 'bet',
            entityId: rows[0].id,
            actionType: 'settle',
            previousState: { ticket_id: ticketId, leg_count: rows.length },
            newState: {
              ticket_id: ticketId,
              outcome: decision.outcome,
              payout: decision.amount,
              decimal_odds: decision.decimalOdds ?? null,
              active_legs: decision.activeLegs ?? 0,
              idempotency_key: key,
              ledger_entry_id: ledgerId,
            },
          });
        }
      }

      const closable = rows.filter((leg) => {
        const standing = legStanding(leg);
        return standing !== 'open' && leg.status !== 'settled';
      });
      if (closable.length > 0) {
        const { error: updateError } = await client
          .from('bets')
          .update({ status: 'settled', updated_at: new Date().toISOString() })
          .in('id', closable.map((leg) => leg.id));
        if (updateError) {
          console.error(`Parlay ${ticketId}: failed to close legs`, updateError);
          continue;
        }
      }

      if (!alreadyPosted) {
        settled++;
        console.log(`Settled parlay ${ticketId}: ${decision.outcome} amount=${decision.amount} key=${key} — ${decision.detail}`);
      }
    } catch (err) {
      console.error(`Parlay ${ticketId}:`, err);
    }
  }

  return settled;
}
