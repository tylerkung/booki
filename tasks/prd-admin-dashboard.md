# PRD: Platform Admin Dashboard

Status: **shipped** · Created 2026-08-18 · Implemented 2026-08-25

## What shipped

| Where | What |
|---|---|
| `supabase/functions/admin_query/index.ts` | Every read, behind one allowlist check |
| `supabase/migrations/038_admin_run_select.sql` | Parser-level SELECT-only for the SQL runner |
| `landing/admin/` | The SPA, at `/admin/` |

All seven user stories are implemented and their criteria met. Three decisions
differ from what this document assumed, and the reasons are worth keeping:

**The admin UI is its own page, not a route inside the dashboard.** The PRD
said "extends the existing Alpine.js SPA at `landing/dashboard/`". It reuses
that SPA's stylesheet wholesale, but lives at `landing/admin/` so no admin code
or markup ships to members and organizers at all. Nothing to hide means nothing
that can fail to be hidden.

**US-006's read-only guarantee is enforced on a connection, not in the RPC.**
The migration provides the parser-level control — the query runs inside a `FROM`
subquery, so DML, DDL and data-modifying CTEs are rejected before execution. The
read-only transaction could not go there: Postgres refuses
`transaction_read_only` inside a function, as `SET LOCAL` and as a function
`SET` clause alike. So `admin_query` opens its own connection and runs
`BEGIN READ ONLY`.

That second control is the one that matters, and this document's suggested
alternative would not have provided it. A read-only **role** does not help here:
17 of 20 public functions are `SECURITY DEFINER`, `delete_bookie_data` among
them, and those run as their owner rather than the caller. A read-only
**transaction** does, because the check is in the executor and role-independent.
Verified in production with `nextval()` on a writable sequence — a write reached
through a function call inside a legal subquery, which is exactly what the
parser control cannot see:

    25006  cannot execute nextval() in a read-only transaction

**Admin identity is a secret, not a table.** `ADMIN_EMAILS` on the edge
function. One operator today; a table is a migration away if that changes.

## Answers to the open questions

**Was it worth building?** Yes, and for the reason predicted: entity resolution
and cross-tenant search. A native Postgres client is a better generic browser,
but neither it nor Supabase Studio can tell you that `c76bb35b…` is a member of
Tyler K.'s book, or show 24 organizers with their member counts, exposure and
dormancy in one sorted list.

**How much of the data model?** Organizers, members, picks, events, invites and
ledger have pages. Audit events, settlement events, device tokens and
idempotency keys are left to the SQL runner, as proposed.

**Mobile?** Not attempted. The tables reuse `.table-responsive` and carry
`data-label` on every cell, so they degrade rather than break, but the layout was
not designed for a phone.

**Does read-only stay read-only?** v1 is a deliberate endpoint, not a stepping
stone. Any future action must call the existing edge functions — `adjust_balance`,
`settle_bet`, `override_grade`, `reverse_settlement` — because writing to tables
directly bypasses idempotency, the audit trail and the ledger hash chain.

## Follow-ups, none blocking

- The overview and its tables apply the test-account filter consistently; that
  had to be fixed once already, and any new aggregate needs the same care.
- `data_quality` runs its checks through the `admin_run_select` RPC rather than
  the read-only connection. Those queries are fixed and trusted, but the two
  paths should converge if any of them ever takes user input.
- No pagination on detail pages: organizer picks and ledger are capped at 50,
  member picks at 100. Fine at current volume, visibly wrong at 10x.

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
- [x] Allowlist of admin emails held server-side (env var or a small `admin_users` table — not hardcoded in `dashboard.js`)
- [x] Caller's JWT resolved to an email and checked against the allowlist
- [x] Non-admin callers get 403 with no data in the error body
- [x] SPA hides admin nav for non-admins as a convenience only, never as the control
- [x] Verified by calling the endpoint with a non-admin token

### US-002: Entity resolution — the core of the whole thing
**Description:** As the operator, I want to see names where the database stores UUIDs.

**Acceptance Criteria:**
- [x] Every foreign key renders as a human label with the UUID available on hover or click
- [x] `bookie_id` → organizer name and email
- [x] `player_id` → member name (preferring `display_name`, falling back to `name`)
- [x] `event_id` → "Away @ Home", start time, status
- [x] `bet_id` → market, side, odds, stake
- [x] Every resolved label is a link to that record's own view
- [x] **This is what Supabase Studio cannot do and the main reason to build anything**

### US-003: Organizer browser
**Description:** As the operator, I want to open an organizer and see their whole world.

**Acceptance Criteria:**
- [x] List: name, email, tier, member count, pick count, created — sortable, searchable
- [x] Detail: members, recent picks, ledger totals, invites, subscription state, all resolved per US-002
- [x] Test accounts (`test_stress_*`, personal) filterable out with one toggle — they distorted every count during the 2026-08-18 audit
- [x] Dormant organizers (0 invites, 0 members) visibly marked

### US-004: Member and pick browsers
**Description:** As the operator, I want to trace a member's activity without a join.

**Acceptance Criteria:**
- [x] Member detail: which organizer, credit and win limits, balance, picks, ledger entries
- [x] Pick detail: the event with names and score, the member, the organizer, stake, odds, grade, and any linked ledger entry
- [x] Parlays show their sibling legs (rows sharing a `ticket_id`)
- [x] Ledger entries shown chronologically with running balance

### US-005: Global search
**Description:** As the operator, I want one box that finds whatever I'm looking for.

**Acceptance Criteria:**
- [x] Single input searching across organizers, members, events and picks
- [x] Accepts a name, an email, or a raw UUID pasted from Supabase or a log line
- [x] Results grouped by type, each linking to its detail view
- [x] Pasting a UUID resolving to "this is a member of Andrew's book" is the single highest-value interaction here

### US-006: Read-only SQL runner
**Description:** As the operator, I want an escape hatch for anything the UI doesn't cover.

**Acceptance Criteria:**
- [x] Text area, results rendered as a table
- [x] **`SELECT` only** — rejected server-side by inspecting the parsed statement, not by string matching, and executed on a read-only connection or role so a bypass still cannot write
- [x] Row cap and statement timeout so a bad query cannot take the database down
- [x] Results exportable as CSV
- [x] Means the tool never blocks you when a question doesn't have a page

### US-007: Data quality views
**Description:** As the operator, I want the integrity checks that have already caught real problems to be one click away.

**Acceptance Criteria:**
- [x] Duplicate events by `external_id` (should be 0 since migration 032's unique index)
- [x] Bets referencing non-existent events (44 exist today, all `test_stress_Bookie`)
- [x] Markets attached to finished games (should stay near 0 given the prune sweep)
- [x] Events past start still marked `scheduled`
- [x] Ledger hash-chain validity — a validator already exists from migration 018
- [x] Each check shows a count and the offending rows, resolved per US-002

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
