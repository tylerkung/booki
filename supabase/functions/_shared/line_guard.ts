import { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';

/**
 * Price guardrails, shared by submit_bet, submit_bets and submit_parlay.
 *
 * These three functions previously each carried their own copy of this logic.
 * The copies had already begun to drift (comment-only at the time this was
 * extracted, but drift nonetheless), and a single behavioural change had to be
 * made in three places to be correct in one — which is how a guard ends up
 * enforced on singles and not on parlays.
 */

/**
 * Which of these markets are superseded?
 *
 * A market row is keyed event + type + LINE VALUE, so a spread moving
 * -3 -> -3.5 INSERTS a new row and leaves the old one behind — still bettable,
 * frozen at a stale price, and passing a pure odds comparison because its odds
 * genuinely are what that row says. It gives itself away by trailing the last
 * write of its own kind.
 *
 * "Its own kind" is the part that took two goes to get right. The first version
 * compared against events.last_odds_update, which only the odds pipeline writes
 * — so once props and futures arrived, each on its own cadence, that one
 * timestamp no longer described them. In production it refused all 705 outright
 * markets, and would have refused every player prop as soon as a game came
 * within the auto-refresh window. Comparing against SIBLINGS (same event, same
 * type) asks the right question and hard-codes no cadence at all.
 *
 * The work happens in superseded_market_ids() (migration 048) so the window
 * function has one definition instead of a copy in each submit endpoint.
 *
 * Fails OPEN: any error resolves to "nothing superseded", because a monitoring
 * blip must not become a betting outage. The price guardrail below still bounds
 * what can be submitted.
 */
export async function supersededMarketIds(
  client: SupabaseClient,
  marketIds: string[],
): Promise<Set<string>> {
  const ids = [...new Set(marketIds.filter(Boolean))];
  if (ids.length === 0) return new Set();
  const { data, error } = await client.rpc('superseded_market_ids', { p_market_ids: ids });
  if (error) {
    console.error('superseded_market_ids failed, allowing through:', error);
    return new Set();
  }
  return new Set(
    ((data ?? []) as { market_id: string }[])
      .map((r) => r.market_id?.toLowerCase())
      .filter(Boolean),
  );
}

/**
 * American odds -> decimal payout multiplier, so two prices can be compared on
 * one scale. Higher is always better for the member.
 */
export function americanToDecimal(odds: number): number {
  return odds > 0 ? 1 + odds / 100 : 1 + 100 / Math.abs(odds);
}

/**
 * Is `submitted` a better price for the member than `current`?
 *
 * Phase 1 of the line-change guardrails is deliberately one-sided: a bet is
 * refused only when the member would get a BETTER price than the one currently
 * offered. Taking the same or a worse price is allowed through, so a line
 * moving against a member never turns into a failed submission on a client that
 * cannot yet explain why. See tasks/prd-line-change-guardrails.md.
 *
 * Without this the server stored whatever odds the request contained, so any
 * price at all could be submitted — a coin flip at +5000 would have been
 * accepted and paid.
 */
export function isBetterForMember(submitted: number, current: number): boolean {
  const EPSILON = 0.001; // absorbs float noise, not a real tolerance
  return americanToDecimal(submitted) > americanToDecimal(current) + EPSILON;
}
