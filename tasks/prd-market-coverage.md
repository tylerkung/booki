# PRD: Market Coverage — More Lines, and Whether to Change Provider

Status: US-001 measured · Created 2026-08-18 · Measured 2026-08-25

## Introduction

Booki currently offers three markets per game. `sync_games` and
`auto_refresh_games` both request exactly `markets=h2h,spreads,totals` with
`regions=us`. That is moneyline, one spread, one total — nothing else.

The notable part: **the app already supports more than it fetches.**
`Booki/Models/Market.swift` defines `alternateSpread`, `alternateTotal` and
`teamTotal` alongside the three in use, and `CLAUDE.md` records an "Alternate
Lines" phase as complete. The models, the UI and the grading logic were built
for markets that the sync has never requested — originally because alternate
markets required a paid Odds API tier, which Booki has since moved to.

So the first question is not "should we change provider". It is "how much of
what we already built can we switch on, and what does it cost".

## Goals

- Establish what markets the current plan actually permits, empirically
- Turn on the markets the app already supports, if the cost is acceptable
- Decide on player props deliberately — they are the most requested and by far
  the most expensive shape
- Evaluate alternative providers only if the Odds API genuinely cannot serve the
  need at a sane price

## What we know about cost

Measured 2026-08-18, using the quota instrumentation in `_shared/odds_quota.ts`:

```
sync_games full run     30 credits / 27 calls
auto_refresh_games       9 credits /  9 calls
period                3,798 used · 16,202 remaining of 20,000
```

Two things follow. Credits are charged per request, and a request returns every
game for its sport — so cost scales with **sports and cadence, not games**. And
the earlier assumption that cost is `markets × regions` produced an estimate
~40% too high, so **it must be measured rather than reasoned about**.

The open question is whether adding markets to an existing request multiplies
its cost. If it does not, alternate lines are close to free. If it does, the
tiered refresh already built becomes the lever for affording them.

## US-001 RESULT — measured 2026-08-25

Probed against a real Week 1 NFL game (NE @ SEA, 10 Sep), `regions=us`, via the
`odds_probe` view in `admin_query`. Numbers are `x-requests-last` off each
response, not estimates.

### What the Odds API actually offers

**69 distinct market keys** on that single NFL game, discoverable for **1
credit** via `/events/{id}/markets`. Availability grows closer to kickoff, so 69
is a floor, not a ceiling.

| Group | Count | Examples (books quoting) |
|---|---|---|
| Core — already live | 3 | `h2h`(10) `spreads`(10) `totals`(10) |
| Alternate lines | 3 | `alternate_spreads`(4) `alternate_totals`(5) `alternate_team_totals`(2) |
| Quarters & halves | 36 | `spreads_h1`(4) `totals_h1`(4) `h2h_q1`(3) `totals_q4`(2) |
| Player props | 19 | `player_1st_td`(4) `player_pass_yds`(3) `player_anytime_td`(3) `player_rush_yds`(3) |
| Exotics | 8 | `odd_even`(3) `team_totals`(3) `first_team_to_score`(2) `overtime`(2) `halftime_fulltime`(1) |

**Not offered at all: coin toss, and winning margin.** Neither appears among the
69 keys. If those are wanted they need a different provider.

### Cost — the formula holds exactly

| Request | Scope | Markets | Credits | Bytes |
|---|---|---|---|---|
| `h2h,spreads,totals` | per-SPORT, all 272 games | 3 | **3** | 492 KB |
| `alternate_spreads,alternate_totals` | per-EVENT | 2 | **2** | 26 KB |
| Halves (6 keys) | per-EVENT | 6 | **6** | 3.7 KB |
| Quarters (9 keys) | per-EVENT | 9 | **9** | 3.7 KB |
| Player props (6 keys) | per-EVENT | 6 | **6** | 14 KB |
| Exotics (6 keys) | per-EVENT | 6 | **6** | 2.9 KB |

Cost is exactly `markets returned x regions`, per request. The open question in
this PRD — "does adding markets to a request multiply its cost" — is answered:
**yes, linearly.**

The economics turn entirely on scope, not on the multiplier. Only
`h2h/spreads/totals/outrights` are served per-SPORT, where 3 credits covers all
272 NFL games. **Everything else — including the alternate lines this app
already supports — is per-EVENT.** Cost therefore scales with the slate.

Per full 16-game NFL week, one refresh of every game:

| Bundle | Markets | Credits per slate refresh |
|---|---|---|
| Auto-gradeable extras (alt spreads, alt totals, team totals) | 3 | 48 |
| \+ halves | 9 | 144 |
| \+ quarters | 18 | 288 |
| \+ core props | 24 | 384 |
| \+ exotics | 29 | 464 |

At 6 refreshes per game per week (twice daily over a 3-day window), monthly:
3 markets ~1,240 · 8 markets ~3,300 · 15 markets ~6,200 · 29 markets ~12,000.

Current baseline is ~4,840 credits/month of 20,000. Headroom today is ~15,000,
but CLAUDE.md projects ~50% baseline at peak season overlap (NFL + NCAAF + NBA +
NHL), leaving ~10,000. **The full 29-market bundle does not fit at peak; a
curated 8–15 does.**

### The real constraint is settlement, not odds

`/scores` returns only aggregate team scores — no period splits, no player
statistics of any kind. So of the 69 markets on offer:

- **Auto-gradeable from the final score:** alternate spreads, alternate totals,
  team totals, `odd_even`. Grading in `_shared/grading.ts` already handles
  `alternate_spread`, `alternate_total` and `team_total`, and
  `Booki/Models/Market.swift` already defines all three.
- **Odds available, settlement impossible with current data:** every quarter and
  half market, every player prop, `total_tds`, `first_team_to_score`,
  `overtime`, `halftime_fulltime`.

Those second-category markets can only ship as **manually graded**, the way
futures already do, or behind a second data provider for statlines and period
scores. That is the decision this PRD actually turns on — not cost.

## User Stories

### US-001: Measure the real cost of additional markets
**Description:** As the operator, I need the actual credit cost before committing to any market expansion.

**Acceptance Criteria:**
- [x] One controlled request per variant, reading `x-requests-last` from the response
- [x] Variants: current three; plus `alternate_spreads`; plus `alternate_totals`; plus `team_totals`; a player-prop request for a single event
- [x] Result recorded as a table of market set → credits per request
- [x] Confirms which markets the current plan actually permits — the paid plan permits all 69, including props
- [x] **Blocks every other story here** — resolved; see US-001 RESULT above

### US-002: Enable the markets the app already supports
**Description:** As a member, I want alternate lines and team totals, which the app can already display and grade.

**Acceptance Criteria:**
- [ ] `sync_games` and `auto_refresh_games` request the additional markets, subject to US-001 cost
- [ ] Mapping extended so `alternate_spreads` / `alternate_totals` / `team_totals` land as the existing `MarketType` cases
- [ ] Storage impact assessed — markets currently sit at 1,333 rows after the Phase 3 cleanup; alternates could multiply this several-fold and partially undo it
- [ ] Storage window and prune rules apply to the new types exactly as to existing ones
- [ ] Client sync payload re-measured; egress is currently ~1.4 GB/mo against a 5 GB allowance
- [ ] Grading verified for each new type before exposure to members

### US-003: Decide on player props
**Description:** As a member, I want to bet player props, which are the most-asked-for market type.

**Acceptance Criteria:**
- [ ] Cost model established — props are fetched **per event**, not per sport, which inverts the economics: cost scales with the number of games, not the number of sports
- [ ] Projected monthly credits at a realistic slate size
- [ ] Grading feasibility assessed: props settle on player statlines, which the current pipeline does not ingest at all. This is materially more work than alternate lines
- [ ] New `MarketType` cases and UI treatment scoped
- [ ] Explicit go/no-go — this is the story most likely to be deferred

### US-004: Provider evaluation, only if warranted
**Description:** As the operator, I want to know whether another provider is a better fit before paying for more of this one.

**Acceptance Criteria:**
- [ ] Triggered only if US-001–003 show the Odds API cannot serve the need at acceptable cost
- [ ] Compare on: markets offered (especially props), pricing model, per-request cost, historical/closing-line data, reliability, migration effort
- [ ] Migration cost honestly estimated — `external_id` is the identity key for every event and a provider change means a new ID space and a remapping strategy for live bets
- [ ] Consider a hybrid: keep the Odds API for core markets, add a second provider for props only
- [ ] Recommendation with numbers, not vibes

### US-005: Closing-line capture (small, and worth doing anyway)
**Description:** As an organizer, I want to know whether my members beat the closing line.

**Acceptance Criteria:**
- [ ] Snapshot each game's final pre-kickoff line onto the event row before it locks
- [ ] One field per game, not a market history table
- [ ] Enables closing-line-value analytics later without retaining thousands of market rows
- [ ] **Context:** the Phase 3 cleanup deliberately deletes markets when a game finishes, which forecloses CLV analysis unless the closing line is captured first. This story is the cheap way to keep that door open

## Open questions

- **What do members actually ask for?** Alternate lines and props are different
  asks with an order-of-magnitude cost difference between them.
- **Does more choice help or hurt?** A dense odds board is table stakes for a
  sportsbook, but Booki's pitch is simplicity for a friend group.
- **Budget ceiling.** Is 20,000 credits/month a hard limit, or would a larger
  plan be justified by the feature?
- **Storage vs coverage.** Phase 3 cut markets by 93%. Alternates would give
  some of that back. Which matters more?

## Prior art in this codebase

- `Booki/Models/Market.swift` — market types already defined and unused
- `supabase/functions/sync_games/index.ts:255` — where markets are requested
- `_shared/odds_quota.ts` — the measurement tool US-001 depends on
- `docs/games-sync-redesign.md` — storage window and prune rules the new markets inherit
