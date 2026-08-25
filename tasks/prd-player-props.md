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

## US-002: Identity — teams, players, games## US-002: Identity — teams, players, games

**Acceptance Criteria:**
- [ ] `bdl_teams` map: Odds API team name → balldontlie team id. 32 rows, seeded
      once, asserted complete by a migration check rather than assumed
- [ ] `bdl_players` cache: id, first, last, `normalized_name`, team id, position.
      Refreshed weekly — rosters churn, and a stale cache silently stops
      resolving new signings
- [ ] Normalisation shared by both sides: case, accents, punctuation
      (`Ja'Marr`→`jamarr`, `D.K.`→`dk`), Jr/Sr/II/III suffixes
- [ ] Event → balldontlie game resolved by date + both team ids, cached on the
      event row. A game that cannot be resolved blocks prop ingest for that game
- [ ] Resolution scoped to the two rosters of the game, never league-wide
- [ ] Ambiguity → the market is not written, and the reason is logged

## US-003: Ingest — prices from The Odds API

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
