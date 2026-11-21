/**
 * Which games this auto_refresh run re-prices.
 *
 * The cron fires every 30 minutes and the function throws most of that away.
 * NFL/NBA/MLB inside 4 hours go on the near tier (every 2 hours, top of the
 * hour). Everything else inside 48 hours goes on the mid tier (every 4 hours).
 * Outrights go once a day. Past the 48-hour member window, sync_games is the
 * writer. A game that has already started is not re-priced here.
 *
 * last_auto_odds_refresh is null until this function has written the event
 * once. sync_games does not set the column, so a game can sit on its import
 * price forever if the tier clock keeps skipping it. Three UFC fights on
 * 21 Nov 2026 were still the 18 Nov write for that reason. A null stamp
 * bypasses the clock and is priced on this run. Started games and games
 * outside 48 hours are still skipped. Outrights stay on the daily futures
 * run: each futures key is its own Odds API call, and a null stamp there
 * would re-price every championship market every half hour.
 */

export const NEAR_WINDOW_MS = 4 * 60 * 60 * 1000;
export const MID_WINDOW_MS = 48 * 60 * 60 * 1000;
export const HIGH_FREQUENCY_LEAGUES = new Set(['NFL', 'NBA', 'MLB']);

export type OddsRefreshSkip =
  | 'started'
  | 'not_soon'
  | 'mid_tier'
  | 'low_frequency'
  | 'futures';

export function bypassesOddsTier(lastAutoOddsRefresh: string | null | undefined): boolean {
  return lastAutoOddsRefresh == null || String(lastAutoOddsRefresh).trim() === '';
}

export function oddsRefreshSkip(input: {
  startTime: string;
  now: number;
  isOutright: boolean;
  lastAutoOddsRefresh: string | null | undefined;
  league: string;
  includeNearTier: boolean;
  includeMidTier: boolean;
  includeFutures: boolean;
}): OddsRefreshSkip | null {
  if (input.isOutright) {
    return input.includeFutures ? null : 'futures';
  }
  const start = Date.parse(input.startTime);
  if (!Number.isFinite(start) || start <= input.now) return 'started';
  const until = start - input.now;
  if (until > MID_WINDOW_MS) return 'not_soon';
  // Never priced by this job. The tier clock is what left the UFC lines
  // sitting on the sync_games write. One pass stamps the column, and the
  // next run is back on the clock.
  if (bypassesOddsTier(input.lastAutoOddsRefresh)) return null;
  if (until > NEAR_WINDOW_MS) {
    return input.includeMidTier ? null : 'mid_tier';
  }
  if (HIGH_FREQUENCY_LEAGUES.has(input.league)) {
    return input.includeNearTier ? null : 'low_frequency';
  }
  return input.includeMidTier ? null : 'low_frequency';
}
