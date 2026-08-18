# PRD: Platform Admin Dashboard

Status: draft for discussion · Created 2026-08-18

## Introduction

Supabase Studio works, but it shows the database as the database sees it, not as
Booki sees it. A bet row reads `bookie_id: 5b85eb3c…`, `player_id: 9a1f…`,
`event_id: 2df3…` — three UUIDs and no names. Answering "what did Andrew bet on
Sunday" means writing a join by hand. That friction is the entire problem this
solves.

This is a **read-only, domain-aware browser** for a single operator. It resolves
identifiers to names, shows related records together, and makes the common
lookups one click instead of one query. It extends the existing Alpine.js SPA at
`landing/dashboard/`.

**Explicitly out of scope for v1: writes of any kind.** No row editing, no
actions, no calling edge functions. That decision is deliberate — see below.

## Two constraints that shape the design

### 1. RLS blocks cross-tenant reads

Every table is protected by RLS scoped to `bookie_id` or `auth_user_id`, and
`get_user_bookie_id()` underpins most policies. An admin needs to read *across*
tenants, which RLS exists to prevent — so these views cannot be built from
ordinary client queries the way the rest of the SPA is.

Two viable approaches:

1. **`SECURITY DEFINER` RPCs**, one per view, each starting with an explicit
   email allowlist check.
2. **A single `admin_query` edge function** using the service client, gated by
   the same allowlist, returning shaped JSON per view.

Option 2 is likely simpler — one auth check, one deployment, matching how every
other privileged operation in this codebase already works. Option 1 spreads the
allowlist across many functions, and one missed check silently leaks
cross-tenant data.

**The allowlist must be server-side.** Hiding a nav item in the SPA is not
access control.

### 2. Read-only, on purpose

Bets and ledger entries are written only through edge functions that enforce
idempotency, business rules, audit trails and a tamper-evident hash chain on
`ledger_entries`. A generic row editor bypasses all of it: editing a bet's
status directly skips the balance recalculation and the audit event, leaving the
ledger disagreeing with the bets table — corruption that surfaces weeks later and
cannot be untangled. Editing a ledger row either breaks the hash chain or is
rejected outright by the immutability trigger.

So v1 reads and does not write. If actions are added later they must call the
existing edge functions (`adjust_balance`, `settle_bet`, `override_grade`,
`reverse_settlement`), never touch tables directly.

## Goals

- Browse Booki's data with names instead of UUIDs
- Follow relationships without writing joins — organizer to members to picks to ledger
- One search box that finds a person or a pick across all tenants
- Reuse the existing dashboard CSS; this is an internal tool, plain and dense
- Escape hatch for anything the UI doesn't cover

## Non-goals

- **Any write path** — no editing, no actions, no edge function calls (v1)
- Replacing Supabase Studio for schema work, migrations or policy editing
- Multi-admin roles or permissions (one operator today)
- Charts and metrics dashboards — this is a browser, not analytics

## User Stories

### US-001: Server-side admin gate
**Description:** As the operator, I need admin data served only to me, enforced on the server.

**Acceptance Criteria:**
- [ ] Allowlist of admin emails held server-side (env var or a small `admin_users` table — not hardcoded in `dashboard.js`)
- [ ] Caller's JWT resolved to an email and checked against the allowlist
- [ ] Non-admin callers get 403 with no data in the error body
- [ ] SPA hides admin nav for non-admins as a convenience only, never as the control
- [ ] Verified by calling the endpoint with a non-admin token

### US-002: Entity resolution — the core of the whole thing
**Description:** As the operator, I want to see names where the database stores UUIDs.

**Acceptance Criteria:**
- [ ] Every foreign key renders as a human label with the UUID available on hover or click
- [ ] `bookie_id` → organizer name and email
- [ ] `player_id` → member name (preferring `display_name`, falling back to `name`)
- [ ] `event_id` → "Away @ Home", start time, status
- [ ] `bet_id` → market, side, odds, stake
- [ ] Every resolved label is a link to that record's own view
- [ ] **This is what Supabase Studio cannot do and the main reason to build anything**

### US-003: Organizer browser
**Description:** As the operator, I want to open an organizer and see their whole world.

**Acceptance Criteria:**
- [ ] List: name, email, tier, member count, pick count, created — sortable, searchable
- [ ] Detail: members, recent picks, ledger totals, invites, subscription state, all resolved per US-002
- [ ] Test accounts (`test_stress_*`, personal) filterable out with one toggle — they distorted every count during the 2026-08-18 audit
- [ ] Dormant organizers (0 invites, 0 members) visibly marked

### US-004: Member and pick browsers
**Description:** As the operator, I want to trace a member's activity without a join.

**Acceptance Criteria:**
- [ ] Member detail: which organizer, credit and win limits, balance, picks, ledger entries
- [ ] Pick detail: the event with names and score, the member, the organizer, stake, odds, grade, and any linked ledger entry
- [ ] Parlays show their sibling legs (rows sharing a `ticket_id`)
- [ ] Ledger entries shown chronologically with running balance

### US-005: Global search
**Description:** As the operator, I want one box that finds whatever I'm looking for.

**Acceptance Criteria:**
- [ ] Single input searching across organizers, members, events and picks
- [ ] Accepts a name, an email, or a raw UUID pasted from Supabase or a log line
- [ ] Results grouped by type, each linking to its detail view
- [ ] Pasting a UUID resolving to "this is a member of Andrew's book" is the single highest-value interaction here

### US-006: Read-only SQL runner
**Description:** As the operator, I want an escape hatch for anything the UI doesn't cover.

**Acceptance Criteria:**
- [ ] Text area, results rendered as a table
- [ ] **`SELECT` only** — rejected server-side by inspecting the parsed statement, not by string matching, and executed on a read-only connection or role so a bypass still cannot write
- [ ] Row cap and statement timeout so a bad query cannot take the database down
- [ ] Results exportable as CSV
- [ ] Means the tool never blocks you when a question doesn't have a page

### US-007: Data quality views
**Description:** As the operator, I want the integrity checks that have already caught real problems to be one click away.

**Acceptance Criteria:**
- [ ] Duplicate events by `external_id` (should be 0 since migration 032's unique index)
- [ ] Bets referencing non-existent events (44 exist today, all `test_stress_Bookie`)
- [ ] Markets attached to finished games (should stay near 0 given the prune sweep)
- [ ] Events past start still marked `scheduled`
- [ ] Ledger hash-chain validity — a validator already exists from migration 018
- [ ] Each check shows a count and the offending rows, resolved per US-002

## Open questions

- **Is this worth building at all?** A native Postgres client (TablePlus,
  Postico, Beekeeper) connected to Supabase gives a far better *generic*
  browsing experience than a custom SPA — keyboard-driven, fast, real FK
  navigation. The custom build only wins on US-002 and US-005: Booki-specific
  entity resolution and cross-tenant search. Worth trying a native client first
  to see whether the remaining gap justifies the work.
- **How much of the data model needs covering?** Organizers, members, picks,
  events and ledger cover most questions. Audit events, settlement events,
  device tokens and idempotency keys are rarely browsed and could be left to the
  SQL runner.
- **Mobile?** Debugging from a phone is occasionally useful but doubles the
  layout work.
- **Does read-only stay read-only?** The obvious next want is "fix this stuck
  bet from here". That's a real need but a different product with a much higher
  bar — worth deciding now whether v1 is a stepping stone or a deliberate
  endpoint.

## Prior art in this codebase

- `landing/dashboard/dashboard.js` — Alpine SPA, hash routing, existing card patterns
- `_shared/odds_quota.ts` — quota data source
- `docs/games-sync-redesign.md` — the failure modes US-004 and US-006 exist to catch
