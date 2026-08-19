# PRD: Line Change Guardrails

Status: draft · Created 2026-08-19

## Introduction

The server does not check the price a member bets at. `submit_bets` loads the
market row but selects only `id, type, side_a, side_b` — never `odds_a`/`odds_b`
— and stores `odds: bet.odds`, taken verbatim from the request body. The same
pattern is in `submit_bet` and `submit_parlay`.

Two consequences:

**A member can submit any price they like.** Not a timing exploit — anyone able
to send an HTTP request can post a bet at +5000 on a coin flip, and the server
will accept it and later pay it.

**Stale displayed prices are exploitable.** Odds for a game nobody has bet are
refreshed twice a day, so a line can be ~12h old. A member who follows the real
market — one injury tweet away — can take a price the market has already moved
off. That is ordinary sharp betting against a slow book, and the organizer pays
the difference.

This PRD adds the guardrail every sportsbook has: the server prices the bet, and
a moved line becomes a confirmation prompt rather than a silent accept.

## Goals

- The server, not the client, decides what price a bet is accepted at
- A member cannot obtain a price better than the one currently offered
- When a line has moved, the member is told and asked to confirm the new price
- No legitimate bet starts failing the moment this ships

## The sequencing trap

Deploying strict two-way validation before the clients understand it would make
legitimate bets fail whenever a line moved, with an error the app cannot explain.
That is a worse experience than the hole being fixed.

So this ships in two phases, and **phase 1 is asymmetric on purpose**:

- **Phase 1 (server only, safe to deploy alone).** Reject only when the
  submitted price is *better for the member* than the current stored price,
  beyond a small tolerance. That closes the exploit completely — nobody can get
  a better-than-offered price — while never rejecting a member who is taking the
  same or a worse price. Existing clients keep working untouched.
- **Phase 2 (server + clients).** Full symmetric validation with a structured
  `line_changed` response and a confirm-the-new-price flow in both clients.

## User Stories

### US-001: Server-side price validation (phase 1)
**Description:** As an organizer, I want the server to refuse a price better than the one being offered.

**Acceptance Criteria:**
- [ ] `submit_bets`, `submit_bet` and `submit_parlay` select `odds_a, odds_b` alongside the existing market columns
- [ ] Resolve which side the pick is on, and compare the submitted odds to that side's stored price
- [ ] Reject when the submitted price is better for the member than stored, beyond a tolerance (proposal: any improvement at all on American odds, since a legitimate client never sends a better price than it was shown)
- [ ] Accept when submitted is equal to, or worse for the member than, stored
- [ ] Rejections return a structured body: `{ error: 'price_mismatch', market_id, submitted, current }`
- [ ] Rejection is per bet in the batch endpoints, consistent with the existing partial-success model
- [ ] Emits an audit event — a member repeatedly hitting this is a signal worth seeing
- [ ] Bets with no matching market row are rejected rather than trusted

### US-002: Line-change confirmation (phase 2)
**Description:** As a member, I want to be told when the price moved and choose whether to take the new one.

**Acceptance Criteria:**
- [ ] Validation becomes symmetric — any difference beyond tolerance is reported
- [ ] Response distinguishes *better for the member* (auto-accept at the stored price, no prompt) from *worse* (prompt)
- [ ] Response carries enough to render the prompt: market, side, old price, new price, and the new potential return
- [ ] Web bet slip shows a "the line has changed" state with old and new side by side, and a single confirm action that resubmits at the new price
- [ ] iOS bet slip does the same
- [ ] Confirming resubmits with a fresh idempotency key, so a confirmation cannot double-submit
- [ ] Declining leaves the pick in the slip, unplaced

### US-003: Refresh before pricing a submission
**Description:** As an organizer, I want the price checked against something current, not something from this morning.

**Acceptance Criteria:**
- [ ] Before validating, if the game's stored odds are older than a threshold (proposal: 5 minutes), refresh that sport first, then validate
- [ ] Refresh is bounded — one sport, one call, and skipped entirely when inside the threshold
- [ ] Adds latency only on the stale path; measured cost of a single sport refresh is ~1 call, 3 credits, ~1–2s
- [ ] Falls back to validating against the stored price if the refresh fails, rather than blocking the bet
- [ ] **Depends on nothing else here** — US-001 is worth shipping without it

### US-004: Line movement telemetry
**Description:** As the operator, I want to know how often this fires before tightening it.

**Acceptance Criteria:**
- [ ] Count rejections and confirmations, by market type and by how far the line moved
- [ ] Surfaces whether the tolerance is right, and whether any member is systematically hitting it
- [ ] Cheap: a counter and a log line, not a new table, until the numbers justify one

## Open questions

- **Tolerance.** Exact match is simplest and safest but will prompt often on
  volatile markets. A cent-level tolerance on American odds reduces noise but
  needs a number picked deliberately.
- **Does a moved *line* count, or only moved odds?** A spread going 3 → 3.5 is a
  materially different bet even at the same price. It probably must count, which
  means comparing `side_a`/`side_b` text as well as the number.
- **Parlays.** One leg moving invalidates the ticket price. Prompt per leg, or
  re-price the whole ticket and confirm once?
- **How long is a confirmed price honoured?** If a member sits on the prompt for
  two minutes, is the confirmation still valid, or does it re-check?

## Prior art in this codebase

- `supabase/functions/submit_bets/index.ts:257` — where the market is loaded today
- `_shared/odds_quota.ts` — measured costs behind US-003
- The partial-success model in `submit_bets` — the shape US-001's rejections follow
