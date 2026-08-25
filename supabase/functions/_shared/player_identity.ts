/**
 * Cross-provider player identity.
 *
 * The Odds API names a prop's subject with a display string; balldontlie has
 * numeric ids. There is no shared key, so this is name matching — and name
 * matching is where a props feature silently settles a bet against the wrong
 * person. Everything here exists to make that impossible rather than unlikely.
 *
 * Two rules, both load-bearing:
 *
 *   1. Normalisation lives HERE and nowhere else. Two copies of these rules
 *      drift, and when they drift the two sides of a comparison stop agreeing
 *      while both still look correct.
 *
 *   2. Resolution is scoped to the two rosters of a specific game, never the
 *      league. Across all 32 NFL rosters there are zero name collisions within
 *      a single team, and 24 names that span two teams — of which 5 cannot be
 *      separated by position. Scoping to a game removes the first 19 outright
 *      and leaves the rest to the position check.
 *
 * See tasks/prd-player-props.md and docs/spikes/prop-grading-spike.ts.
 */

export interface BdlPlayer {
  bdl_player_id: number;
  first_name: string;
  last_name: string;
  normalized_name: string;
  position: string | null;
  bdl_team_id: number | null;
}

/**
 * Fold a name to its comparable form.
 *
 * Handles what actually differs between the two feeds: case, accents,
 * punctuation (`Ja'Marr` / `JaMarr`, `D.K.` / `DK`) and generational suffixes,
 * which one provider carries and the other frequently does not.
 */
export function normalizeName(name: string): string {
  return name
    .toLowerCase()
    .trim()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[.'`’-]/g, '')
    .replace(/\s+(jr|sr|ii|iii|iv|v)$/, '')
    .replace(/\s+/g, ' ');
}

export type Resolution =
  | { ok: true; player: BdlPlayer }
  | { ok: false; reason: string; candidates: number };

/**
 * Resolve a prop's subject to exactly one player.
 *
 * `roster` MUST already be limited to the two teams playing. `positionHint`
 * narrows what a market implies about its subject — a passing prop belongs to a
 * quarterback — and is the last line of defence for the handful of names that
 * appear on two teams at the same position.
 *
 * Returns a failure rather than a best guess. The caller's contract is to NOT
 * create the market: a prop that was never offered is a non-event, while a prop
 * settled against the wrong player is a corrupted ledger and a lost member.
 */
export function resolvePlayer(
  rawName: string,
  roster: BdlPlayer[],
  positionHint?: string[],
): Resolution {
  const target = normalizeName(rawName);
  let hits = roster.filter((p) => p.normalized_name === target);

  if (hits.length > 1 && positionHint?.length) {
    const byPosition = hits.filter((p) => p.position && positionHint.includes(p.position));
    // Only narrow if it actually resolves. A position filter that leaves zero
    // candidates means the hint was wrong, not that the player does not exist.
    if (byPosition.length === 1) hits = byPosition;
  }

  if (hits.length === 1) return { ok: true, player: hits[0] };
  if (hits.length === 0) {
    return { ok: false, reason: `no player matching "${rawName}" in this game`, candidates: 0 };
  }
  return {
    ok: false,
    reason: `"${rawName}" matches ${hits.length} players in this game`,
    candidates: hits.length,
  };
}

/**
 * Which positions a market's subject can plausibly be.
 *
 * Deliberately permissive: a running back throws a pass often enough that
 * excluding one would turn a resolvable prop into an unoffered one. This exists
 * to break ties, not to validate.
 */
export const POSITION_HINTS: Record<string, string[]> = {
  passing_yards: ['QB'],
  passing_touchdowns: ['QB'],
  rushing_yards: ['RB', 'QB', 'WR', 'FB'],
  receiving_yards: ['WR', 'TE', 'RB', 'FB'],
  receptions: ['WR', 'TE', 'RB', 'FB'],
};
