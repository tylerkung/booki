/**
 * Shared moneyline, spread and total: one row per event.
 *
 * Those three are the main line. The number moving (+11.5 to +12.5) is the
 * same market at a new price, not a second market. Keying the row on the
 * line value — which is what `marketDiscriminator` does, because alternate
 * lines and team totals really are different markets — inserted a new spread
 * on every move and left the old one bettable. The board then rendered
 * whichever row happened to sort last, and submit_bets refused it: the row
 * trailed a newer sibling, so `superseded_market_ids` called it
 * `line_no_longer_offered`.
 *
 * Alternate lines, team totals, props and outrights are NOT main lines.
 * They keep a key that includes the line (or the full side, for team totals).
 * Collapsing those would delete a price the book is still offering.
 */

export const MAIN_LINE_TYPES = ['moneyline', 'spread', 'total'] as const;

export type MainLineType = (typeof MAIN_LINE_TYPES)[number];

export function isMainLine(type: string): type is MainLineType {
  return type === 'moneyline' || type === 'spread' || type === 'total';
}

/**
 * A stored shared main-line row. `bookie_id` is null for the board's line;
 * a row owned by one organizer is not ours to retire.
 */
export interface SharedMainLineRow {
  id: string;
  bookie_id: string | null;
  updated_at: string | null;
  bettable: boolean | null;
  main_line: boolean | null;
}

export interface MainLinePlan {
  /**
   * The row to overwrite with the price just fetched. Null when this event
   * has no shared row of this type yet and the caller should insert one.
   * The id is stable across line moves: the next number lands on this row
   * instead of a new one.
   */
  canonicalId: string | null;
  /**
   * Other shared rows of this same type that must be marked not bettable
   * (`bettable = false`, `main_line = false`). Never a delete list. A pick
   * stores `market_id`, and deleting the row nulls that reference
   * (migration 042). PR #9's finished-game prune makes the same choice for
   * markets that still have a pick; retiring here stays compatible with it
   * because this list is not deleted at all.
   */
  retireIds: string[];
}

function newestFirst(a: SharedMainLineRow, b: SharedMainLineRow): number {
  const at = Date.parse(a.updated_at || '') || 0;
  const bt = Date.parse(b.updated_at || '') || 0;
  if (at !== bt) return bt - at;
  // Same write time: a deterministic pick, so two runs agree on the id.
  if (a.id === b.id) return 0;
  return a.id < b.id ? -1 : 1;
}

/**
 * Decide which existing shared row absorbs the new main line.
 *
 * Prefer the row already flagged `main_line`, so the id does not hop once
 * one has been chosen. Otherwise the newest row that is still bettable —
 * the one the board shows and the one `superseded_market_ids` will accept.
 * A retired row's updated_at is newer than the live row's, because retiring
 * it is an UPDATE, and that must not make it the row we keep.
 *
 * Every other shared row that is still bettable is retired. Rows with
 * `bookie_id` set are ignored: they are not the shared line.
 */
export function planSharedMainLine(rows: SharedMainLineRow[]): MainLinePlan {
  const shared = rows.filter((r) => r.bookie_id == null);
  if (shared.length === 0) return { canonicalId: null, retireIds: [] };

  const flagged = shared.filter((r) => r.main_line === true);
  const bettable = shared.filter((r) => r.bettable !== false);
  const pool = flagged.length > 0 ? flagged : (bettable.length > 0 ? bettable : shared);
  const canonical = [...pool].sort(newestFirst)[0];
  const retireIds = shared
    .filter((r) => r.id !== canonical.id && r.bettable !== false)
    .map((r) => r.id);
  return { canonicalId: canonical.id, retireIds };
}

/**
 * Unique-index conflict on `markets_one_shared_main_line` (migration 064).
 *
 * Two writers (sync_games and auto_refresh_games) can both observe "no main
 * line yet" and both insert. The second hits this. It is not a reason to
 * keep going with a second row: the caller adopts the row that won.
 */
export function isSharedMainLineConflict(
  error: { code?: string; message?: string } | null | undefined,
): boolean {
  if (!error) return false;
  if (error.code === '23505') return true;
  return /markets_one_shared_main_line/i.test(error.message || '');
}
