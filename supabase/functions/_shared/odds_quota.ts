/**
 * Odds API quota tracking.
 *
 * The Odds API bills per request as `markets x regions`, so a game-odds call
 * (h2h,spreads,totals against one region) costs 3 credits while an outrights
 * or scores call costs 1. That makes consumption a function of how many
 * SPORTS are fetched per run, not how many games — one call returns every
 * upcoming game for its sport.
 *
 * Every response carries the running totals in its headers, but nothing read
 * them, so actual burn rate against the monthly allowance was unknown and
 * could only be estimated. These helpers record the headers on each response
 * and expose a per-run summary, which each function returns in its stats so
 * usage is visible without digging through logs.
 */

export interface QuotaSnapshot {
  /** Credits consumed by this run, summed from each response's x-requests-last. */
  run_cost: number;
  /** API calls made in this run (including any that reported no headers). */
  calls: number;
  /** Credits used this billing period, as of the most recent response. */
  used: number | null;
  /** Credits left this billing period, as of the most recent response. */
  remaining: number | null;
  /** Bytes received from the Odds API this run, summed across responses. */
  bytes: number;
}

let runCost = 0;
let calls = 0;
let latestUsed: number | null = null;
let latestRemaining: number | null = null;
let bytes = 0;

/**
 * Reset the per-run counters.
 *
 * Edge function isolates are reused between invocations, so module state
 * survives across requests. Call this at the top of every handler or the
 * numbers accumulate across unrelated runs.
 */
export function resetQuota(): void {
  runCost = 0;
  calls = 0;
  latestUsed = null;
  latestRemaining = null;
  bytes = 0;
}

/**
 * Record the quota headers from one Odds API response.
 *
 * `size` is the byte length of the decoded body. Credits measure what the Odds
 * API bills; bytes measure what moves across Supabase's network, and the two
 * are unrelated — a one-credit scores call for a busy sport can return more
 * data than a three-credit odds call for a quiet one. Egress is billed on the
 * bytes, so the credit count alone cannot explain an egress figure.
 */
export function recordQuota(response: Response, label: string, size?: number): void {
  calls++;
  if (typeof size === 'number' && Number.isFinite(size)) bytes += size;

  const num = (name: string): number | null => {
    const raw = response.headers.get(name);
    if (raw === null) return null;
    const parsed = Number(raw);
    return Number.isFinite(parsed) ? parsed : null;
  };

  const last = num('x-requests-last');
  const used = num('x-requests-used');
  const remaining = num('x-requests-remaining');

  if (last !== null) runCost += last;
  if (used !== null) latestUsed = used;
  if (remaining !== null) latestRemaining = remaining;

  // Headers are absent on error responses (a 404 for an out-of-season sport
  // costs nothing), so a missing value is normal rather than a fault.
  if (last === null && used === null && remaining === null) return;

  console.log(
    `[odds-quota] ${label} cost=${last ?? '?'} used=${used ?? '?'} ` +
      `remaining=${remaining ?? '?'} bytes=${size ?? '?'}`,
  );
}

/** Per-run summary, for inclusion in a function's response stats. */
export function getQuotaSnapshot(): QuotaSnapshot {
  return {
    run_cost: runCost,
    calls,
    used: latestUsed,
    remaining: latestRemaining,
    bytes,
  };
}
