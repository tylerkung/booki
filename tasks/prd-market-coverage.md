# PRD: Market Coverage — More Lines, and Whether to Change Provider

Status: draft for discussion · Created 2026-08-18

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

## User Stories

### US-001: Measure the real cost of additional markets
**Description:** As the operator, I need the actual credit cost before committing to any market expansion.

**Acceptance Criteria:**
- [ ] One controlled request per variant, reading `x-requests-last` from the response
- [ ] Variants: current three; plus `alternate_spreads`; plus `alternate_totals`; plus `team_totals`; a player-prop request for a single event
- [ ] Result recorded as a table of market set → credits per request
- [ ] Confirms which markets the current plan actually permits (a 401/422 is itself an answer)
- [ ] **Blocks every other story here** — no expansion decision without this

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
