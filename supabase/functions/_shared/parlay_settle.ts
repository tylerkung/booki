/**
 * One decision for a parlay ticket.
 *
 * Void and push legs are removed and the ticket is repriced on whatever is
 * left. A loss settles immediately. Every leg void or push refunds the stake.
 * The auto-settler used to require every leg's status to be 'graded', and a
 * voided leg is stored as 'void', so this branch never ran.
 *
 * Ledger sign matches settlement_math: positive means the member owes the
 * organizer, negative means the organizer owes the member, zero is a refund.
 */

export const DEFAULT_MAX_PARLAY_LEGS = 4;

export function parlayTooManyLegs(legCount: number, maxLegs: number = DEFAULT_MAX_PARLAY_LEGS): string | null {
  if (!Number.isFinite(maxLegs) || maxLegs < 2) {
    return 'Multi-pick leg limit is not configured';
  }
  if (legCount > maxLegs) {
    return `A multi-pick can have at most ${maxLegs} legs`;
  }
  return null;
}

/**
 * Stable across retries. The previous key appended Date.now(), so two runs
 * of the same ticket were two different keys and both could insert a ledger
 * row. Version 1 is the first auto settlement; a later reversal would use
 * the next version rather than a new timestamp.
 */
export function parlaySettlementKey(ticketId: string, version: number = 1): string {
  return `auto_settle_parlay_${ticketId}_v${version}`;
}

export type LegStanding = 'win' | 'loss' | 'push' | 'void' | 'open';

export interface ParlayLegState {
  status: string;
  grade_result: string | null;
  odds: number;
}

export interface ParlayDecision {
  action: 'settle' | 'wait';
  outcome?: 'win' | 'loss' | 'void';
  /** Ledger amount. Loss is +stake, win is -profit, refund is 0. */
  amount?: number;
  /** Profit paid to the member, in dollars, already rounded to cents. 0 otherwise. */
  profit?: number;
  /** Combined decimal odds of the legs that were not voided or pushed. */
  decimalOdds?: number | null;
  activeLegs?: number;
  detail: string;
}

export function legStanding(leg: ParlayLegState): LegStanding {
  if (leg.status === 'void' || leg.grade_result === 'void') return 'void';
  if (leg.grade_result === 'push' || leg.status === 'push') return 'push';
  if (leg.grade_result === 'loss') return 'loss';
  if (leg.grade_result === 'win') return 'win';
  return 'open';
}

function americanToDecimal(odds: number): number {
  if (odds > 0) return 1 + odds / 100;
  if (odds < 0) return 1 + 100 / Math.abs(odds);
  return 1;
}

function roundCents(amount: number): number {
  return Math.round(amount * 100) / 100;
}

export function decideParlay(stake: number, legs: ParlayLegState[]): ParlayDecision {
  if (legs.length === 0) return { action: 'wait', detail: 'no legs' };

  const standings = legs.map(legStanding);

  if (standings.some((s) => s === 'loss')) {
    return {
      action: 'settle',
      outcome: 'loss',
      amount: roundCents(stake),
      profit: 0,
      decimalOdds: null,
      activeLegs: 0,
      detail: 'a leg lost; the multi-pick loses without waiting for the other legs',
    };
  }

  if (standings.some((s) => s === 'open')) {
    return { action: 'wait', detail: 'legs still open and none have lost' };
  }

  const active = legs.filter((_, i) => standings[i] === 'win');
  if (active.length === 0) {
    return {
      action: 'settle',
      outcome: 'void',
      amount: 0,
      profit: 0,
      decimalOdds: null,
      activeLegs: 0,
      detail: 'every leg was void or push; stake refunded',
    };
  }

  const decimalOdds = active.reduce((acc, leg) => acc * americanToDecimal(Number(leg.odds)), 1);
  const profit = roundCents(stake * decimalOdds - stake);
  return {
    action: 'settle',
    outcome: 'win',
    amount: roundCents(-profit),
    profit,
    decimalOdds,
    activeLegs: active.length,
    detail: `repriced over ${active.length} leg${active.length === 1 ? '' : 's'} after dropping void and push legs`,
  };
}
