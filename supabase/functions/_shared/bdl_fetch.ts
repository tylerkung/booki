/**
 * balldontlie fetch with backoff on 429.
 *
 * The first MLB ingest asked for nine games back to back and every one came
 * back "Too many requests" — which the caller then reported as nine games with
 * no matching balldontlie game, since a failed lookup and an absent game are
 * the same outcome from its point of view. The whole run finished in under
 * three seconds and spent zero Odds API credits, which is the tell: it never
 * really looked anything up.
 *
 * Retrying is the fix, but so is saying WHY. A rate limit is transient and a
 * missing game is not, and treating them alike hides a fixable problem behind
 * a plausible-looking skip count.
 */
export async function bdlFetch(
  url: string,
  apiKey: string,
  attempts = 4,
): Promise<Response> {
  let last: Response | null = null;
  for (let i = 0; i < attempts; i++) {
    const res = await fetch(url, { headers: { Authorization: apiKey } });
    if (res.status !== 429) return res;
    last = res;
    // 1s, 2s, 4s. Bounded so a genuinely throttled run fails inside the
    // function's time budget rather than being killed by the 150s ceiling.
    if (i < attempts - 1) await new Promise((r) => setTimeout(r, 1000 * 2 ** i));
  }
  return last!;
}
