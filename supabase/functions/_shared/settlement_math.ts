/**
 * The ledger amount a settled bet produces.
 *
 * Extracted so there is ONE definition. auto_refresh_games already carries this
 * arithmetic inline in two places, and adding a third copy for props is how a
 * ledger quietly stops agreeing with itself — the kind of divergence that
 * surfaces weeks later as a balance nobody can explain.
 *
 * SIGN CONVENTION, which is the part that is easy to get backwards:
 * positive means the MEMBER OWES the organizer, negative means the organizer
 * owes the member. So a losing bet is +stake (the member owes what they staked)
 * and a winning bet is -profit (the organizer owes the winnings). A push or a
 * void is 0: the stake was never at risk in the ledger, so nothing moves.
 *
 * Matches the existing behaviour in auto_refresh_games exactly. Those call
 * sites should adopt this rather than keep their copies.
 */
export type GradeResult = 'win' | 'loss' | 'push' | 'void';

export function settlementAmount(
  result: GradeResult,
  stake: number,
  americanOdds: number,
): number {
  if (result === 'win') {
    const profit = americanOdds > 0
      ? stake * (americanOdds / 100)
      : stake * (100 / Math.abs(americanOdds));
    return -profit;
  }
  if (result === 'loss') return stake;
  return 0;   // push and void move nothing
}

export const SETTLEMENT_DESCRIPTION: Record<GradeResult, string> = {
  win: 'Bet won',
  loss: 'Bet lost',
  push: 'Bet pushed',
  void: 'Bet voided',
};
