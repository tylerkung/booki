# Games Sync & Storage Redesign

Status: planning · Created 2026-08-18

## Background

`sync_games` used an unbounded `.select()` to check which events already
existed. PostgREST silently caps such a query at 1000 rows, so once matching
rows exceeded the cap, every event past it looked new and was re-inserted —
every run, compounding. Result: 25,134 event rows for 5,986 real games, with
duplicates carrying no markets, so odds rendered as "—".

The pagination bug is fixed (`_shared/pagination.ts`, commit `0b61f3e`). This
document covers the cleanup and the storage model that prevents a recurrence.

## Decisions

| Question | Decision |
|---|---|
| How far ahead do members see odds? | **48 hours** |
| Do futures expire with that rule? | **No — outrights are exempt** |
| How often do futures refresh? | **Daily**, if the line moved |
| Retain finished games? | **Yes** — needed for grading and bet history |

## Measured baseline (2026-08-18)

Post-cleanup: 5,986 rows, 5,986 distinct external_ids, 0 duplicates.

```
event rows            25,134      →  5,986 real games (76% duplicates)
  past                            →  5,396
  future                          →    590
  3+ months old                   →  3,087
markets               20,531
  on games already played         → 17,195  (84%)
  on games >24h out               →  3,286
full client sync      21.6 MB per device
egress                ~200 MB/day, ~6 GB/mo against a 5 GB free allowance
```

## Identity model

**`external_id` is the sole identity key.** Verified against production data:

- 0 distinct games are split across more than one `external_id`
- 789 matchups recur on multiple dates (e.g. Marlins @ Mets on 7 dates) and are
  correctly kept as separate games, because team names never enter the key
- 129 `external_id`s show a drifting `start_time` (the Odds API adjusting UFC
  fight times, or correcting home/away). These are the *same* game and are
  handled by the update path, not by inserting a new row.

Never key on `(home_team, away_team)` or any team-derived tuple. A rematch is a
new game; only the provider's event id distinguishes them reliably.

## Phases

### Phase 1 — Dedupe ✅ COMPLETE (2026-08-18)

Per `external_id` group, canonical = the row with the most markets, tie-broken
by oldest `created_at`, so the surviving row keeps its odds.

1. Repoint markets that do not collide with one the canonical already holds (112)
2. Drop colliding duplicate markets — same `(event, type, side_a)` (718)
3. Delete the orphaned duplicate event rows (19,148)

Order matters: `markets.event_id` is a real FK to `events.id`, so an event
cannot be deleted while any market still references it. `bets.event_id` is
TEXT with **no** FK — deletes will not cascade, but nothing protects against
dangling references either, which is why bets are checked first.

Verified: **0 real bets are affected.** 44 bets already reference event ids
that exist nowhere in the table; all belong to `test_stress_Bookie` from
2026-07-31 and are unrelated to this cleanup.

Backup taken: `backups/events-2026-08-18.json`, `backups/markets-2026-08-18.json`.

### Phase 2 — Prevent recurrence (in progress)

- Unique index on `events.external_id` — migration `032`. Plain, not partial:
  PostgREST emits a bare `ON CONFLICT (external_id)` which cannot infer a
  partial index's predicate. NULLs stay permitted (Postgres treats them as
  distinct), so manually created events remain possible.
- `sync_games` insert becomes `upsert(..., { onConflict: 'external_id',
  ignoreDuplicates: true })`, so a stale existence check is silently skipped
  instead of failing the batch with a 23505. It logs a warning when that
  happens, which is the early-warning signal that pagination regressed.
- **Not** a blanket upsert of all fields: the update path preserves `status`
  and skips events already final. A full upsert would un-finalize graded games.
- **Ordering hazard**: migration 032 must be applied BEFORE deploying the
  function, or every sync fails with 42P10.
- Audited `refresh_live_scores` and `auto_refresh_games`: every event query
  there filters `.in('id', <ids derived from bets>)`, so results stay far below
  the 1000-row cap at current volume. No change needed. Revisit if distinct
  bet event ids ever approach 1000.

### Phase 3 — Odds lifecycle

- **Store** odds for games starting within 7 days
- **Display** odds 48 hours ahead
- **Refresh** odds only within 48h of start — this is what costs Odds API calls
- **Delete** markets once a game goes final (grading never reads them; each bet
  stores its own `market`, `side`, and `odds` at placement)
- **Exempt `type = 'outright'`** from every rule above; futures refresh daily

Storing wider than the display window is deliberate: storage is cheap, and a
game whose odds are missing renders as "—", the exact symptom being fixed.

Expected: markets 20,531 → ~3,000.

### Phase 4 — Client sync efficiency

`SyncService.swift:278` pages every shared event and every shared market with
no time filter, so each device sync pulls 21.6 MB — including March games.

- Filter to `start_time >= now - 7 days`
- Union with events referenced by that user's own bets, so history still renders
- Project only needed columns rather than `select()`

Expected: 21.6 MB → under 1 MB per sync; egress ~6 GB/mo → well under 2 GB.

## Open item: missing final scores

5,024 of 5,394 finished games have no `final_score`.

Not a grading defect. `sync_games:170` requests scores with `daysFrom: 3`, the
Odds API maximum, so games older than 3 days can never be backfilled — and
those games have no bets. Exactly **one** bet sits on a finished game without a
score, and it is an outright, which is manual-grade by design.

Forward risk: the backfill is capped at `.limit(20)` per run × 2 runs/day = 40
games/day against a 3-day window. ~17 games/day finish now, so it keeps up.
Adding sports or a busier season would let games age out unscored.

Suggested fix: prioritise events that have bets rather than all finals, and
raise the cap. Grading correctness should never depend on a cosmetic backfill.
