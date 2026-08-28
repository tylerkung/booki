import { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { normalizeName, type BdlPlayer } from './player_identity.ts';

/**
 * Resolve a prop's subject to one balldontlie player, ON DEMAND.
 *
 * Replaces an earlier design that bulk-cached ~100 players per team and
 * resolved against that. Two things killed it:
 *
 *   - It was INCOMPLETE. balldontlie returns every player who ever played for a
 *     franchise, current roster first, so a page cap silently truncates the
 *     tail. It missed a second currently-rostered Josh Allen (C/ARI) entirely,
 *     which meant the cache reported that name as unique when it is not. A
 *     cache-first lookup is only safe if the cache is COMPLETE; an incomplete
 *     one turns a genuine ambiguity into a confident wrong answer, which is the
 *     single failure this whole design exists to prevent.
 *
 *   - It was wasteful. Props are written on a few dozen players per game, not
 *     3,200 league-wide.
 *
 * So: query balldontlie for the specific name, cache what comes back, and treat
 * the cache as a record of resolutions we have actually verified rather than a
 * mirror of the league.
 */

const BDL_BASE = 'https://api.balldontlie.io/nfl/v1';

export type SubjectResolution =
  | { ok: true; player: BdlPlayer; fromCache: boolean }
  | { ok: false; reason: string };

/** "Amon-Ra St. Brown" -> { first: "Amon-Ra", last: "St. Brown" } */
function splitName(full: string): { first: string; last: string } {
  const parts = full.trim().split(/\s+/);
  if (parts.length === 1) return { first: parts[0], last: parts[0] };
  return { first: parts[0], last: parts.slice(1).join(' ') };
}

/**
 * Candidate spellings to try against the API.
 *
 * balldontlie matches these params LITERALLY on punctuation: `A.J.` finds
 * A.J. Brown and `AJ` finds nobody. The two feeds do not agree on that
 * punctuation, so the variants are tried rather than assumed.
 */
function queryVariants(name: string): Array<{ first: string; last: string }> {
  const raw = splitName(name);
  const stripped = splitName(name.replace(/[.'’`]/g, ''));
  const noSuffix = splitName(name.replace(/\s+(Jr\.?|Sr\.?|III?|IV|V)\s*$/i, ''));
  const seen = new Set<string>();
  return [raw, stripped, noSuffix].filter((v) => {
    const k = `${v.first}|${v.last}`;
    if (seen.has(k)) return false;
    seen.add(k);
    return true;
  });
}

interface ApiPlayer {
  id: number;
  first_name: string;
  last_name: string;
  position?: string | null;
  position_abbreviation?: string | null;
  team?: { id: number } | null;
}

/**
 * Does this API row refer to the person the prop names?
 *
 * The API's name filters behave as "contains" — `last_name=Allen` also returns
 * Josh Hines-Allen — so every hit is re-checked here against our own exact
 * normalisation instead of being trusted.
 *
 * Suffixes are compared BOTH ways. Stripping them is usually right (one feed
 * carries `Jr.` and the other does not) but it manufactures a collision between
 * a father and son: `Marvin Harrison` and `Marvin Harrison Jr.` are two real,
 * distinct players. An exact match including the suffix therefore wins outright
 * before the suffix-insensitive comparison is tried at all.
 */
function matchesExactly(target: string, p: ApiPlayer): boolean {
  return normalizeName(`${p.first_name} ${p.last_name}`) === normalizeName(target);
}
function matchesIgnoringSuffix(target: string, p: ApiPlayer): boolean {
  const drop = (s: string) => normalizeName(s).replace(/\s+(jr|sr|ii|iii|iv|v)$/, '');
  return drop(`${p.first_name} ${p.last_name}`) === drop(target);
}

export async function resolveSubject(
  client: SupabaseClient,
  apiKey: string,
  rawName: string,
  teamIds: number[],
  positionHint?: string[],
  sport = 'NFL',
  bdlBase = BDL_BASE,
): Promise<SubjectResolution> {
  const normalized = normalizeName(rawName);

  // Cache holds only previously VERIFIED resolutions, so a hit is trustworthy.
  const { data: cached } = await client
    .from('bdl_players')
    .select('bdl_player_id, first_name, last_name, normalized_name, position, bdl_team_id')
    .eq('normalized_name', normalized)
    // Without the sport filter this cache read can match a player from another
    // league: bdl_player_id and bdl_team_id are both per-sport sequences, so the
    // same numbers exist in each.
    .eq('sport', sport)
    .in('bdl_team_id', teamIds);

  if (cached && cached.length === 1) {
    return { ok: true, player: cached[0] as BdlPlayer, fromCache: true };
  }
  if (cached && cached.length > 1) {
    const narrowed = positionHint?.length
      ? cached.filter((c) => c.position && positionHint.includes(c.position))
      : [];
    if (narrowed.length === 1) return { ok: true, player: narrowed[0] as BdlPlayer, fromCache: true };
    return { ok: false, reason: `"${rawName}" is ambiguous among cached players for this game` };
  }

  // Miss: ask the API for this specific name.
  let hits: ApiPlayer[] = [];
  for (const variant of queryVariants(rawName)) {
    const url = `${bdlBase}/players?first_name=${encodeURIComponent(variant.first)}` +
      `&last_name=${encodeURIComponent(variant.last)}&per_page=100`;
    const res = await fetch(url, { headers: { Authorization: apiKey } });
    if (!res.ok) continue;
    const body = await res.json();
    hits = (body.data ?? []) as ApiPlayer[];
    if (hits.length) break;
  }
  if (!hits.length) return { ok: false, reason: `balldontlie has no player named "${rawName}"` };

  // Scope to the two rosters. This is the safety property: the league has more
  // than one Josh Allen, a single game does not.
  const inGame = hits.filter((p) => p.team && teamIds.includes(p.team.id));
  if (!inGame.length) {
    return { ok: false, reason: `"${rawName}" is not on either roster for this game` };
  }

  // Exact first — a father/son pair differs only by the suffix.
  let candidates = inGame.filter((p) => matchesExactly(rawName, p));
  if (!candidates.length) candidates = inGame.filter((p) => matchesIgnoringSuffix(rawName, p));

  if (candidates.length > 1 && positionHint?.length) {
    const byPos = candidates.filter((p) =>
      positionHint.includes(p.position_abbreviation ?? p.position ?? ''));
    if (byPos.length === 1) candidates = byPos;
  }

  if (candidates.length !== 1) {
    // Never guess. The caller's contract is to not write the market.
    return {
      ok: false,
      reason: candidates.length === 0
        ? `no exact match for "${rawName}" on either roster`
        : `"${rawName}" matches ${candidates.length} players in this game`,
    };
  }

  const p = candidates[0];
  const row: BdlPlayer = {
    bdl_player_id: p.id,
    first_name: p.first_name,
    last_name: p.last_name,
    normalized_name: normalizeName(`${p.first_name} ${p.last_name}`),
    position: p.position_abbreviation ?? p.position ?? null,
    bdl_team_id: p.team?.id ?? null,
  };
  // Cache the verified resolution. A trade makes the cached team stale, which
  // produces a miss rather than a wrong answer, and the next lookup re-resolves
  // and corrects it.
  await client.from('bdl_players').upsert(
    { ...row, sport, last_synced_at: new Date().toISOString() },
    { onConflict: 'bdl_player_id' },
  );

  return { ok: true, player: row, fromCache: false };
}
