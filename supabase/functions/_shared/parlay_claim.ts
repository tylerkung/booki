import { decideParlay, legStanding, parlaySettlementKey } from './parlay_settle.ts';

/**
 * One attempt to pay a parlay ticket.
 *
 * The claim is a conditional update: a leg moves to `settling` only while it
 * is still `graded` or `void`. Two jobs can call this at once; only the
 * update that gets every claimed row back writes the ledger. If that write
 * fails, the claim is put back. A later run finds the legs settled and
 * does nothing. The unique ledger constraint is migration 063, not this.
 */

export interface TicketLeg {
  id: string;
  status: string;
  grade_result: string | null;
  odds: number;
  stake: number;
  bookie_id: string;
  player_id: string;
}

export interface LedgerWrite {
  bookie_id: string;
  player_id: string;
  bet_id: string;
  amount: number;
  description: string;
  idempotency_key: string;
}

export interface SettlementClaim {
  /** Returns the ids whose status was still one of `fromStatuses`. */
  claim(ids: string[], fromStatuses: string[]): Promise<string[]>;
  revert(id: string, toStatus: string): Promise<void>;
  /** Null when the ledger row was not written. */
  writeLedger(entry: LedgerWrite): Promise<{ id: string } | null>;
  close(ids: string[]): Promise<boolean>;
}

export type SettleAttempt = 'settled' | 'noop' | 'reverted';

function description(outcome: 'win' | 'loss' | 'void', activeLegs: number, legCount: number): string {
  if (outcome === 'win') return `Multi-Pick won (${activeLegs} of ${legCount} legs)`;
  if (outcome === 'loss') return `Multi-Pick lost (${legCount} legs)`;
  return `Multi-Pick voided (${legCount} legs, stake refunded)`;
}

export async function settleTicketOnce(
  ticketId: string,
  legs: TicketLeg[],
  store: SettlementClaim,
): Promise<SettleAttempt> {
  if (legs.length === 0) return 'noop';

  const decision = decideParlay(
    Number(legs[0].stake),
    legs.map((leg) => ({
      status: leg.status,
      grade_result: leg.grade_result,
      odds: Number(leg.odds),
    })),
  );
  if (decision.action !== 'settle' || decision.outcome == null || decision.amount == null) {
    return 'noop';
  }

  const claimable = legs.filter((leg) => {
    const standing = legStanding(leg);
    return standing !== 'open' && leg.status !== 'settled' && leg.status !== 'settling';
  });
  if (claimable.length === 0) return 'noop';

  const previous = new Map(claimable.map((leg) => [leg.id, leg.status]));
  const claimed = await store.claim([...previous.keys()], ['graded', 'void']);
  if (claimed.length !== previous.size) {
    for (const id of claimed) {
      const prior = previous.get(id);
      if (prior) await store.revert(id, prior);
    }
    return 'noop';
  }

  const ledger = await store.writeLedger({
    bookie_id: legs[0].bookie_id,
    player_id: legs[0].player_id,
    bet_id: claimed[0],
    amount: decision.amount,
    description: description(decision.outcome, decision.activeLegs ?? 0, legs.length),
    idempotency_key: parlaySettlementKey(ticketId, 1),
  });
  if (!ledger) {
    for (const [id, prior] of previous) await store.revert(id, prior);
    return 'reverted';
  }

  await store.close(claimed);
  return 'settled';
}
