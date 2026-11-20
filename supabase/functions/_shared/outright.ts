/**
 * Futures (outright) identity and the manual-settlement key.
 *
 * An outright event is stored with away_team 'Outright'. The pick's own
 * `side` is the selection name. market_id is not an identity: a refresh can
 * delete the market row and the bet's market_id becomes NULL.
 */

export function isOutrightEvent(awayTeam: string | null | undefined): boolean {
  return awayTeam === 'Outright';
}

export function isOutrightMarket(market: string | null | undefined): boolean {
  const name = (market ?? '').toLowerCase();
  return name === 'outright' || name === 'futures';
}

/**
 * Stable across retries of grade_bet. A new click sends a new request
 * idempotency key; the settlement key does not, so the second click finds
 * the settlement settle_bet_tx already posted.
 */
export function manualSingleSettlementKey(betId: string): string {
  return `manual_settle_${betId}_v1`;
}
