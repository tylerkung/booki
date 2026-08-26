# How odds, props and games actually flow

Written 2026-08-25, from the deployed functions and the migrations that
schedule them. This is the orchestration view — what runs, how often, and why
each boundary is where it is.

## The shape in one paragraph

Two external providers. **The Odds API** supplies games and prices; **balldontlie**
supplies the box scores that settle player props. Everything else is ours:
a set of scheduled edge functions that pull, filter, store and grade, with the
database as the only shared state between them. No function calls another —
they coordinate purely through rows.

## The four jobs

| Function | Cadence | Buys | Writes |
|---|---|---|---|
| `sync_games` | twice daily | games + core markets, per SPORT | `events`, `markets` |
| `auto_refresh_games` | every 30 min | re-priced odds + final scores | `markets`, `events.status`, grades bets |
| `refresh_live_scores` | every 5 min | scores, only when a game is ending | `events` scores/status |
| `sync_player_props` | not yet scheduled | prop prices, per EVENT | `markets` (type `player_prop`) |

### `sync_games` — the wide, cheap pass

Fetches every upcoming game for each sport in one request per sport. That is the
key economic fact of the whole pipeline: **the featured endpoint bills per
SPORT, so 3 credits covers all 272 NFL games.** It also carries the deep-market
bundle (alternate spreads, alternate totals, team totals, odd/even) for NFL and
NBA games inside 3 days, which is billed per EVENT.

Two filters keep it affordable and the database small:

- **Odds storage window (7 days).** Games further out are stored without
  markets. Nobody bets a line 10 days early, and storing them multiplied the
  markets table.
- **Prune on final.** Markets for finished non-outright games are deleted every
  run. This is a sweep over the markets table rather than a hook on the
  finalisation path, because three separate code paths mark a game final and
  hooking one missed the games people actually bet on.

### `auto_refresh_games` — the narrow, frequent pass

Fires every 30 minutes and then decides per game whether that game is due:
within 4h it re-prices every run for NFL/NBA/MLB and hourly for other leagues,
4–48h every two hours, outrights once a day, beyond 48h never. **The cron fires
at the fastest tier and the function filters down**, so changing the schedule
silently changes the near-game cadence.

It also grades and settles: when a game reaches `final`, bets on it are graded
from the final score and ledger entries written in the same step.

### `refresh_live_scores` — cheap because it usually does nothing

Runs every 5 minutes but estimates each sport's game duration and only calls the
API when a game is inside its finishing window. Most runs cost zero credits.

### `sync_player_props` — the expensive, narrow one

Props are billed per event and are by far the largest market type by row count,
so this is gated hardest: NFL only, games within 2 days, and a curated six
markets. It is also the only ingest that can REFUSE to write:

> A prop we cannot grade is never offered.

Before a prop market is written, the game must map to a balldontlie game and the
subject must resolve to exactly one player on one of that game's two rosters.
Anything ambiguous is skipped and counted. Migration 039 backs this with a CHECK
constraint, so the rule holds even against a code path that forgets it.

## Where the two providers meet

The seam is deliberately small and lives in three places:

- `bdl_teams` — 32 rows mapping an Odds API team name to a balldontlie team id.
  Verified identical today; stored anyway so a rename is a one-row update.
- `events.bdl_game_id` — resolved once per game by date plus both team ids,
  searching a ±1 day window because kickoff crosses midnight UTC.
- `bdl_players` — resolutions we have VERIFIED, filled one player at a time.
  Explicitly **not** a mirror of the league: an incomplete mirror reports an
  ambiguous name as unique, which is the one failure this design exists to
  prevent.

## Why the split between odds and props

They have opposite economics and opposite failure modes.

Odds are cheap per game, safe to publish early, and settle from a final score
the same provider gives us. Props are expensive per game, only worth publishing
near kickoff, and settle from a second provider that has no shared key with the
first. Putting them in one function would force the cheap path to carry the
expensive one's constraints — and `sync_games` already runs ~80s against a 150s
ceiling, with no room to absorb a resolution call per unseen player.

## Measured cost of the props pipeline

Taken 2026-08-25 against NFL week 1, sixteen days out, via
`sync_player_props` with `{"dry_run": true, "window_days": 20}`. A dry run
still calls the Odds API — it skips only the database write — so the credit
figures are real.

| | |
|---|---|
| Games considered | 16 |
| Games mapped to balldontlie | 16 (0 skipped) |
| Markets that would be written | 35 |
| Subjects resolved | 18, **0 unresolved** |
| Odds API cost | **26 credits over 16 calls** |

Two things to take from this, and one not to.

**The 26 is a floor.** Books had barely posted prop menus that far out — 35
markets across 16 games is about two per game, against an expected couple of
hundred per game once a slate is live. The credit figure will rise with it.

**The ceiling is what makes the pipeline schedulable.** The Odds API charges
markets × regions per call, so six prop markets over one region caps a single
call at 6 credits regardless of how many props come back. A full 16-game slate
therefore cannot exceed 96 credits, however busy the board gets. Migration 049
sets the cadence off that bound rather than off the 26.

**Do not read 0 unresolved as a solved identity problem.** Eighteen subjects is
a small sample drawn from the handful of star players who get props posted two
weeks out — exactly the names most likely to match cleanly. The interesting
cases are the ones that appear on game day: rookies, practice-squad call-ups,
suffixes and hyphenates. `subjects_unresolved` is still only a log line, so
right now a drift in name matching would show up as props quietly missing
rather than as an alert.

## Known gaps

- **Not every schedule lives in the repo.** `sync_games` and
  `refresh_live_scores` have no cron migration; per CLAUDE.md they run twice
  daily and every 5 minutes, so they were scheduled through the dashboard. That
  means the migrations are not a complete description of what runs, and a fresh
  environment would not reproduce them. Worth moving into a migration.
- ~~**BLOCKER — the superseded-line guard rejects every prop.**~~ Fixed by
  migration 048; the original writeup is kept below because the root cause was
  broader than props and worth remembering. In production it was also refusing
  all 705 outright markets — every futures bet — which nobody had noticed.

  ORIGINAL: **the superseded-line guard rejects every prop.** This one stops
  props working at all, and it does so silently: the props ingest, render, and
  price correctly, then refuse every bet with `line_no_longer_offered`.

  All three submit endpoints call `isSupersededLine(market.updated_at,
  event.last_odds_update)`, which exists to catch a market row that is still
  bettable but no longer offered — a spread moving -3 → -3.5 INSERTS a new row
  and leaves the old one behind, frozen at a stale price. Trailing the event's
  refresh by more than 15 minutes is how such a row identifies itself.

  That inference holds only while ONE job refreshes every market on an event.
  It does not hold for props: `sync_player_props` writes prop `updated_at` but
  never touches `events.last_odds_update`, which only `sync_games` and
  `auto_refresh_games` write. So the moment auto-refresh re-prices the core
  markets — every 30 minutes — every prop on that event is more than 15 minutes
  behind and reads as superseded. The guard is not misfiring; it is being asked
  a question about a timestamp that does not describe props.

  The fix is to give props their own reference point rather than exempting them
  (an exemption would leave stale props bettable, which is the exact hole the
  guard was added to close). Add `events.last_props_update`, write it from
  `sync_player_props`, and have the guard pick the reference by market type.
  Needs a migration, so it has not been done.

- ~~`sync_player_props` / `grade_player_props` are unscheduled.~~ Scheduled by
  migration 049: sync every 6 hours at :15, grading every 30 minutes at :05/:35,
  both offset from the :00/:30 odds refresh.
- **`subjects_unresolved` is not persisted.** The count and ten examples go to
  the run log and nowhere else, so there is no way to notice name matching
  degrading over a season except by reading logs. This is the monitoring the
  fail-open design in 048 assumes exists.
- **The game-week measurement is still outstanding.** Everything above was
  measured sixteen days before kickoff. Re-run the dry run during a live slate
  and compare against the 96-credit ceiling before trusting the 23% projection
  in migration 049.
