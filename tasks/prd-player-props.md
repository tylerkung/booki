# PRD: Player Props — Odds API for prices, balldontlie for settlement

Status: draft for build · Created 2026-08-25

## Introduction

Props are the most-requested market type and the only one Booki cannot currently
settle. `tasks/prd-market-coverage.md` US-003 deferred them for exactly that
reason, and the 2026-08-25 spike lifted it: balldontlie's NFL tier returns
per-player per-game statlines, and grading against a real box score works —
including the failure modes, which matter more than the happy path.

This is the build. Two providers, each doing the thing it is good at: The Odds
API prices the props, balldontlie settles them. Everything hard lives in the
seam between them.

## The one principle everything else follows from

**A prop we cannot grade is never offered.**

Identity is resolved at INGEST, not at settlement. If a prop's subject cannot be
matched to exactly one player on one of the two rosters, the market is not
written and no member can bet it. That converts the entire class of
"we settled against the wrong Josh Allen" risk into "that prop quietly wasn't
on the board", which is a non-event.

The alternative — store now, resolve at grading — means discovering an
unresolvable name *after* someone has money on it, when the only options are a
manual grade or a void. Every additional prop market carries that risk again, so
the check belongs at the door.

## What the spike established

- Grading a statline is straightforward; the edge cases are void (rostered, did
  not play), pending (unknown subject), and push (exact line). All verified
  against a real 32-player box score in `docs/spikes/prop-grading-spike.ts`.
- Name collisions within a single team: **0** across all 32 rosters.
- Names spanning two teams where position cannot disambiguate: **5**, all
  positions props are rarely written on.
- Cost is ~1 credit per prop market per game, and ~200 stored rows per game for
  a curated set.

## Goals

- Offer the prop markets that can be settled automatically, and only those
- Resolve player and team identity once, at ingest, and cache it
- Grade from a statline on a cadence that accounts for stats arriving late
- Keep a snapshot of what was graded against, so a later stat correction is
  detectable rather than invisible

## Non-goals

- Props that need play-by-play (`player_1st_td`, `player_last_td`) — GOAT tier
- Longest-reception/rush props — not in the ALL-STAR field set
- Any sport but NFL in v1. NBA is the obvious second and shares every mechanism
- Automatic reversal on a stat correction. Detect and surface; a human decides

---

## US-001: Verify the NFL statline shape — DONE 2026-08-25

Verified against a real completed game: balldontlie NFL game 423945, Cowboys at
Eagles, 2025-09-05, 60 statlines. All criteria answered.

- [x] Field names recorded (56 stat fields — considerably more than documented)
- [x] Every mapping below resolves to a real field
- [x] **DNP is an ABSENT ROW.** 60 statlines across a game where the two gameday
      rosters total ~96. Only players with recorded involvement appear, so a
      player who did not play simply has no row → void, as intended
- [x] Kicking and defensive stats ARE present at ALL-STAR
- [x] `player_anytime_td` **is settleable** — see below

### Two findings that would each have mis-settled bets

**1. An all-zero row is NOT a DNP.** Dante Fowler Jr. (LB, DAL) appears with
every stat field at zero. He dressed and recorded nothing. So:

| Shape | Meaning | Verdict |
|---|---|---|
| No row at all | did not play | **void** |
| Row, all zeroes | played, recorded nothing | **grade normally** (an Over loses) |

Collapsing these would void props that should have lost — refunding stakes on
bets the book won. The presence of the row is the signal, never the values in
it. `~30 statlines per team against a ~48 gameday roster` is the corroborating
evidence that rows track involvement rather than activation.

**2. `passing_touchdowns` must never count toward an anytime TD.** The
quarterback throws it; the receiver scores it. Including it would credit every
QB with anytime touchdowns they did not score — on one of the most popular prop
markets. Verified against this game: Jalen Hurts shows `anytime_td=2` from
rushing alone, and passing TDs are correctly excluded from the sum.

Anytime TD is therefore:

    rushing_touchdowns + receiving_touchdowns + kick_return_touchdowns
      + punt_return_touchdowns + interception_touchdowns + fumbles_touchdowns

All six exist, which resolves the concern that return and fumble-recovery scores
would be missed. `player_anytime_td` moves from EXCLUDED to shippable.

### Also: `total_points` is not populated

Present in the schema, zero non-null values across all 60 statlines. Kicking
points must be derived from `field_goals_made` and `extra_points_made` rather
than read from it.

## US-002: Identity — teams, players, games## US-002: Identity — teams, players, games — BUILT 2026-08-25

- [x] `bdl_teams` map — migration 040. All 32 Odds API NFL team names match
      balldontlie's `full_name` EXACTLY, so `odds_api_name` is identical today.
      The column is stored anyway: that agreement is a fact about current data,
      not a guarantee, and a rename should be a one-row UPDATE rather than a
      hunt through matching logic. The migration asserts 32 rows and unique
      names, because a short map does not fail loudly — it reads as "that game
      has no props" and could go unnoticed for a season
- [x] `bdl_players` — **on-demand, not bulk.** Filled one verified resolution at
      a time by `_shared/bdl_resolve.ts`. The first design bulk-cached ~100
      players per team and was replaced because it was **incomplete**:
      balldontlie returns every player who ever played for a franchise, current
      roster first, so a page cap truncates the tail. It missed a second
      currently-rostered Josh Allen (C, Arizona), which meant the cache reported
      that name as UNIQUE when it is not.
      That is the dangerous shape — resolution trusts a single cache hit, so an
      incomplete cache turns a genuine ambiguity into a confident wrong answer,
      the exact failure this design exists to prevent. **An incomplete cache is
      worse than an empty one.** Migration 041 empties it and the table's
      meaning changes from "mirror of the league" to "resolutions we have
      actually verified".
      No weekly refresh is needed either: a traded player's cached team goes
      stale, which produces a cache MISS rather than a wrong answer, and the
      next lookup re-resolves and corrects it. It self-heals in the only
      direction that is safe.
- [x] Normalisation shared — `_shared/player_identity.ts`, computed once at
      write time so both sides of a comparison fold identically
- [x] Event → balldontlie game — `_shared/bdl_games.ts`, matched on date plus
      BOTH team ids and cached on the event row. A ±1 day window is searched
      because kickoff crosses midnight UTC and the providers need not agree
      which calendar day a Sunday-night game belongs to; requiring both teams
      is what keeps the window unambiguous. Verified against the real
      2025-09-05 Cowboys/Eagles game, which is exactly that midnight case
- [x] Resolution scoped to the two rosters, never league-wide
- [ ] Ambiguity → market not written — the RULE is enforced by migration 039's
      CHECK constraint, but the ingest that would honour it is US-003

**Verified against the live API**, including the case that motivated the
redesign: "Josh Allen" on a Buffalo/Arizona game REFUSES with two candidates,
and resolves to the QB only when the market supplies a position hint. Also
verified: `Amon-Ra St. Brown`, `Ja'Marr Chase`, `A.J. Brown`, and a player who
is simply not in the game.

Two API behaviours the resolver has to work around, both found by testing:
`search=Josh Allen` returns ZERO — search matches a single token, not a full
name — so `first_name` + `last_name` are used instead; and those filters match
punctuation LITERALLY, where `A.J.` finds A.J. Brown and `AJ` finds nobody, so
spelling variants are tried rather than assumed.

Suffixes are compared BOTH ways, exact first. Stripping `Jr.` is usually right
because one feed carries it and the other does not — but it manufactures a
collision between `Marvin Harrison` and `Marvin Harrison Jr.`, who are two real
and distinct players.

## US-003: Ingest — prices from The Odds API — BUILT 2026-08-25

`sync_player_props`, deliberately its own function rather than part of
`sync_games`: that one already runs ~80s against a 150s ceiling and a slate's
first ingest needs a resolution call per unseen player.

**Verified against real week 1 data** (20-day preview window):

| | |
|---|---|
| Games considered | 16 |
| Games mapped to a balldontlie game | **16 / 16** |
| Subjects resolved | **18 / 18, zero unresolved** |
| Markets written | 35 |
| Odds API cost | 26 credits for the slate |

Run twice back to back: the second wrote 0 and updated 35, confirming re-runs
do not duplicate. The first version used a plain `insert` and would have
duplicated every prop on every run; matching happens in application code on
`(stat_key, subject, side)` the way `sync_games` matches its markets, because
delete-and-reinsert would churn market ids that placed bets already reference.

**The rule is enforced by the database, not just by the code.** Posting a prop
with no `subject_player_id` is rejected:

    23514 — new row for relation "markets" violates check constraint
            "markets_prop_requires_subject"

**35 markets across 16 games is NOT the in-week number.** Prop coverage is thin
16 days out; the Odds API adds markets as kickoff approaches. The ~200 rows per
game estimate is still unmeasured and should be re-measured during game week
before the ingest window is widened or more markets are added.

The on-demand cache filled itself exactly as designed: 0 players before the run,
18 after — only the players who actually had props.

## US-003 (original)

Markets to carry, all verified settleable against real statline fields:

| Odds API market | Stat expression |
|---|---|
| `player_pass_yds` | `passing_yards` |
| `player_pass_tds` | `passing_touchdowns` |
| `player_pass_completions` | `passing_completions` |
| `player_pass_attempts` | `passing_attempts` |
| `player_pass_interceptions` | `passing_interceptions` |
| `player_rush_yds` | `rushing_yards` |
| `player_rush_attempts` | `rushing_attempts` |
| `player_receptions` | `receptions` |
| `player_reception_yds` | `receiving_yards` |
| `player_rush_reception_yds` | `rushing_yards + receiving_yards` |
| `player_anytime_td` | sum of the six SCORING td fields, **excluding passing** |
| `player_tds_over` | same sum |
| `player_reception_longest` | `long_reception` |
| `player_rush_longest` | `long_rushing` |
| `player_field_goals` | `field_goals_made` |
| `player_pats` | `extra_points_made` |
| `player_kicking_points` | `field_goals_made * 3 + extra_points_made` |
| `player_sacks` | `defensive_sacks` |
| `player_solo_tackles` | `solo_tackles` |
| `player_tackles_assists` | `total_tackles` |
| `player_defensive_interceptions` | `defensive_interceptions` |

Still out of reach at ALL-STAR: `player_1st_td` and `player_last_td`, which
need play-by-play (GOAT tier).

**Ship a subset first.** Every market above is gradeable, but ~200 rows a game
was the estimate for six markets, not twenty. Start with the six skill-position
yardage and reception markets plus `player_anytime_td`, measure the real row
count, and widen from there.

**Acceptance Criteria:**
- [ ] Fetched per event from `/events/{id}/odds`, alongside the existing deep
      market bundle, for NFL games inside `DEEP_MARKET_WINDOW_MS`
- [ ] ~6 extra credits per game. At 16 games and the current cadence that is
      ~1,850 credits/month, inside the existing plan
- [ ] Each outcome becomes a two-sided market row: `Player Over X` /
      `Player Under X`, matching how team totals already store
- [ ] Row volume measured and recorded before enabling — the estimate is ~200 a
      game and it needs to be a measurement, since the board's egress budget has
      been exceeded once already
- [ ] Prop markets are excluded from the board query, exactly as the deep
      markets are. They belong to the game detail view only

## US-004: Storage

**Acceptance Criteria:**
- [ ] `markets` gains `subject_player_id` (balldontlie id), `subject_name` (raw,
      for display and debugging) and `stat_key`
- [ ] `subject_player_id NOT NULL` for any prop row — enforced by a CHECK, so
      the "never offer what we cannot grade" rule is a database constraint and
      not a convention someone can forget
- [ ] The market dedup key extends to include the subject: two players commonly
      share a line on the same stat, and keying on type + line alone would
      collide exactly as team totals did
- [ ] Prop rows obey the existing storage window and the final-game prune

## US-005: Grading cadence

Statlines are not final when the whistle blows. The cadence has to tolerate a
box score that is late, partial, or briefly wrong.

**Acceptance Criteria:**
- [ ] `grade_player_props` runs every 15 minutes
- [ ] Considers events marked `final` in the last 24 hours with ungraded props
- [ ] **A settling delay after `final` before the first attempt** — grading the
      instant a game ends is how you settle on a box score that is still being
      written. 30 minutes is the starting value; US-001's observations should
      set it
- [ ] A partial box score does not grade. All-or-nothing per game, because a
      half-written statline produces confident wrong answers, not obvious ones
- [ ] Retries while incomplete, up to 24h, then flags for manual grading rather
      than guessing
- [ ] Grades through the existing settlement path so the ledger, audit trail and
      hash chain all behave exactly as they do for every other market

## US-006: Corrections

**Acceptance Criteria:**
- [ ] The statline used to grade is snapshotted onto the bet or a side table
- [ ] A re-check 24h after grading compares the snapshot to the current statline
- [ ] A divergence raises an operator alert with the affected bets — it does NOT
      auto-reverse. `override_grade` and `reverse_settlement` exist and are
      deliberate, human actions
- [ ] Surfaced in the admin dashboard as a data-quality check, next to the
      others

## US-007: UI

**Acceptance Criteria:**
- [ ] Props group by PLAYER, then by stat — the subject of a prop is a person,
      which is the one market type where the ladder model does not fit
- [ ] The existing ladder handles the Over/Under pair per line
- [ ] Search within a game's props: a 200-row prop board is not scannable
- [ ] iOS: a `playerProp` MarketType, and the same eight exhaustive switches
      noted in `tasks/ios-pending.md`

---

## Open questions

- ~~Does `player_anytime_td` ship at all?~~ **Resolved: yes.** All six scoring
  touchdown fields exist, and passing touchdowns are excluded from the sum.
- **How many props is too many?** 200 rows a game is a real board, but Booki's
  pitch is a friend group, not a sportsbook. Six markets may already be more
  than anyone wants.
- **Void policy on a late scratch.** A player ruled out pre-kickoff has a market
  people already bet. Void is right; the question is whether we detect it from
  the injury endpoint at ingest or only from the absent statline afterwards.
- **NBA next?** Every mechanism here is sport-agnostic and the NBA tier is
  already on the key. The mapping table is the only new work.

## Prior art

- `docs/spikes/prop-grading-spike.ts` — the verified grading logic
- `supabase/functions/_shared/grading.ts` — where the grader belongs
- `supabase/functions/sync_games/index.ts` — `fetchEventMarketsFromApi`,
  `mergeDeepMarkets`, `marketDiscriminator`
- `tasks/prd-market-coverage.md` — the measurements this rests on

## BLOCKER — RESOLVED 2026-08-26 by migration 045

Solved server-side, which is the only kind of fix that reaches builds already
installed. The read policy on `markets` now hides any type listed in
`legacy_client_hidden_market_types()` — currently `player_prop` and `odd_even` —
from direct client reads. The service role bypasses RLS, so ingest and grading
are untouched, and the web opts in explicitly through
`get_event_player_props(event_id)`.

Three things fall out of it:

- **iOS needs no release.** Shipped builds stop seeing these types rather than
  mislabelling them, and pull less data rather than more.
- **`odd_even` is back in `DEEP_MARKETS`.** It was pulled only because the sole
  defence looked like an iOS release.
- **Removing an entry from that list is how a future iOS version ships support**
  for the type — one line, tracked in `tasks/ios-pending.md`.

The original analysis is kept below, because the reasoning is what makes the
fix legible.

## ORIGINAL BLOCKER — props cannot go live until the iOS sync excludes them

Found 2026-08-26 while checking quotas. `SyncService.swift:757` downloads
markets with a bare `.select()` and **no type filter**, so every prop row syncs
to every iOS client. Two consequences, and the second is worse than the cost:

**Egress.** A game week at the estimated ~200 rows per game is ~3,200 prop rows
against a markets table that currently holds ~1,450. That roughly triples the
markets payload in every iOS sync, on an account that has already exceeded its
egress quota once.

**A visible bug.** `MarketType` has no `player_prop` case, so
`MarketType(rawValue:) ?? .moneyline` coerces it. An existing App Store build
would render "Patrick Mahomes Over 245.5" as a MONEYLINE market on the game
detail screen. Members would not see it today only because the 48-hour display
window hides week 1 — that protection disappears on 8 September.

The 35 prop rows written during the US-003 verification were deleted for exactly
this reason.

**The web side is already safe:** `BOARD_MARKET_TYPES` restricts the board query
to the three types it renders, and props load per game in the detail view.

### Options, in order of preference

1. **Filter the iOS sync** — one line, but it needs an App Store build, so the
   lead time is weeks and old builds stay broken indefinitely.
2. **Move props to their own table.** iOS never learns they exist and no build is
   required. Costs a second table and complicates `bets.market_id`, which
   currently references `markets(id)`.
3. **Keep props out of production** until iOS ships the change. Cheapest, and
   fine if the promo does not depend on them.

Option 2 is the only one that works on old builds, which is the constraint that
actually matters. Decide before scheduling `sync_player_props`.

## What is and is not persisted

**Stored:** prop markets (`markets`), the grade (`bets.grade_result`), the money
(`ledger_entries`), and the box score each grade was computed from
(`prop_grading_runs.statline_snapshot`) — roughly 40 KB per game, about 11 MB
across a full season, which is what makes US-006 possible.

**NOT stored — a gap worth closing:** every operational number is returned in
the function response and written to the log, then lost. That includes the Odds
API quota per run, and `subjects_unresolved`, which this PRD calls "the monitor
for identity drift". A monitor nobody can query is not a monitor: there is no
way to see that resolution failures went from 0 to 14 last Sunday. Persisting
these runs into a small table is a prerequisite for trusting the ingest
unattended.
