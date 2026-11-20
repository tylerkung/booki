import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';

/**
 * Callers of the settlement RPCs. Grading decides the result and, for a
 * parlay, the amount. These functions only post it. settle_bet_tx prices a
 * single from its own odds and refuses a parlay leg. settle_parlay_tx posts
 * one ledger row for the ticket.
 */

export interface SettleTxResult {
  success: boolean;
  error?: string;
  idempotent?: boolean;
  already_settled?: boolean;
  action?: 'settled' | 'wait';
  outcome?: string;
  detail?: string;
  settlement_version?: number;
  legs_settled?: number;
  ledger_entry?: {
    id: string;
    amount: number;
    description?: string;
    bet_id?: string;
  };
}

export async function settleBetTx(
  client: SupabaseClient,
  args: {
    betId: string;
    actorUserId: string | null;
    idempotencyKey: string;
    mode: 'auto' | 'manual';
  },
): Promise<{ error: string | null; result: SettleTxResult | null }> {
  const { data, error } = await client.rpc('settle_bet_tx', {
    p_bet_id: args.betId,
    p_actor_user_id: args.actorUserId,
    p_idempotency_key: args.idempotencyKey,
    p_mode: args.mode,
  });
  if (error) return { error: error.message, result: null };
  const result = data as SettleTxResult | null;
  if (!result?.success) return { error: result?.error || 'settle_bet_tx failed', result };
  return { error: null, result };
}

export async function settleParlayTx(
  client: SupabaseClient,
  args: {
    ticketId: string;
    actorUserId: string | null;
    idempotencyKey: string;
    mode: 'auto' | 'manual';
    auditDetails?: Record<string, unknown>;
  },
): Promise<{ error: string | null; result: SettleTxResult | null }> {
  const { data, error } = await client.rpc('settle_parlay_tx', {
    p_ticket_id: args.ticketId,
    p_actor_user_id: args.actorUserId,
    p_idempotency_key: args.idempotencyKey,
    p_mode: args.mode,
    p_amount: null,
    p_description: null,
    p_audit_details: args.auditDetails ?? null,
  });
  if (error) return { error: error.message, result: null };
  const result = data as SettleTxResult | null;
  if (!result?.success) return { error: result?.error || 'settle_parlay_tx failed', result };
  return { error: null, result };
}
