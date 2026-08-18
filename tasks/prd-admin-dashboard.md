# PRD: Platform Admin Dashboard

Status: draft for discussion · Created 2026-08-18

## Introduction

There is currently no way to see Booki as a whole. Every existing view is
tenant-scoped: an organizer sees their own members, an organizer's dashboard
sums their own book. Answering "how many real organizers do I have", "is the
Odds API about to run out", or "did the cron run last night" means opening the
Supabase dashboard and writing SQL by hand.

This PRD covers a single-operator admin view — one account, not a role system —
that answers those questions in one place. It extends the existing Alpine.js
SPA at `landing/dashboard/` rather than introducing a new app.

**Scope note:** this is an internal tool. It should be plain and dense, not
designed. Reuse the existing dashboard CSS and card patterns.

## The constraint that shapes the design

Every table is protected by RLS scoped to `bookie_id` or `auth_user_id`, and
`get_user_bookie_id()` underpins most policies. An admin needs to read *across*
tenants, which RLS is specifically built to prevent — so the admin views cannot
be built from ordinary client queries the way the rest of the SPA is.

Two viable approaches, to decide before building:

1. **`SECURITY DEFINER` RPCs**, one per panel, each starting with an explicit
   email allowlist check. Reads stay in Postgres; the client calls RPCs.
2. **A single `admin_metrics` edge function** using the service client, gated by
   the same allowlist, returning one JSON payload.

Option 2 is likely simpler — one auth check, one deployment, and it matches how
every other privileged operation in this codebase already works. Option 1 spreads
the allowlist across many functions, and a missed check silently leaks
cross-tenant data.

**Whichever is chosen, the allowlist must be server-side.** Hiding a nav item in
the SPA is not access control.

## Goals

- One page answering "is the platform healthy right now"
- Cross-tenant visibility: organizers, members, picks, volume
- Third-party quota and credential status in one place, before something expires
- No new app, no new design system, no role/permission framework
- Read-only in v1 — no destructive actions from this surface

## Non-goals

- Multi-admin roles or granular permissions (one operator today)
- Impersonating an organizer
- Anything that writes to another tenant's data

## User Stories

### US-001: Server-side admin gate
**Description:** As the operator, I need admin data served only to me, enforced on the server.

**Acceptance Criteria:**
- [ ] Allowlist of admin emails held server-side (env var or a small `admin_users` table — not hardcoded in `dashboard.js`)
- [ ] Caller's JWT resolved to an email and checked against the allowlist
- [ ] Non-admin callers get 403 with no data leakage in the error body
- [ ] SPA hides admin nav for non-admins as a convenience only, never as the control
- [ ] Verified by calling the endpoint with a non-admin token

### US-002: Platform overview panel
**Description:** As the operator, I want the headline numbers without writing SQL.

**Acceptance Criteria:**
- [ ] Organizers: total, active (has ≥1 member), dormant (0 invites and 0 members)
- [ ] Members: total, claimed vs pending invite
- [ ] Picks: total, open, settled, last 7 days
- [ ] Handle: total staked, and net position across all books
- [ ] Signups over time (simple counts by week is enough)
- [ ] Test accounts excluded or clearly flagged — `test_stress_*` and personal accounts polluted every count during the 2026-08-18 audit

### US-003: Third-party status panel
**Description:** As the operator, I want to know a quota or credential is about to bite before it does.

**Acceptance Criteria:**
- [ ] **Odds API**: credits used / remaining this period, from the `quota` block now returned by `sync_games`, `auto_refresh_games` and `refresh_live_scores` (`_shared/odds_quota.ts`)
- [ ] Requires persisting quota somewhere — the values exist only in responses and logs today. A small `odds_api_usage` table written once per run is enough
- [ ] Trend, not just current: burn rate per day and projected end-of-period
- [ ] **Stripe**: active subscriptions, MRR, failed payments
- [ ] **Resend**: recent sends and any bounces (verify what the API exposes)
- [ ] **APNs**: `.p8` key age, device token count, recent delivery failures
- [ ] Anything approaching a limit is visually distinct, not just a number in a row

### US-004: Cron and job health panel
**Description:** As the operator, I want to see whether the scheduled jobs actually ran.

**Acceptance Criteria:**
- [ ] Last run time and outcome for each job: `sync_games`, `auto_refresh_games`, `refresh_live_scores`, `send_followup_email`
- [ ] Reads `cron.job_run_details` (needs a `SECURITY DEFINER` wrapper — not exposed to PostgREST)
- [ ] Flags a job that has not run in longer than its schedule allows
- [ ] Surfaces recent edge function errors if reachable
- [ ] **Motivating case:** `sync_games` silently exceeded the 150s edge limit for an unknown period in August. Nothing surfaced it; odds went stale and it read as a UI bug

### US-005: Organizer list and detail
**Description:** As the operator, I want to look up a specific organizer and see their state.

**Acceptance Criteria:**
- [ ] Searchable list: name, email, tier, member count, pick count, created date
- [ ] Detail view: members, recent picks, ledger totals, subscription state
- [ ] Read-only
- [ ] Reuses existing member-detail card patterns rather than new components

### US-006: Data quality panel
**Description:** As the operator, I want the integrity checks that have already caught real problems to run continuously.

**Acceptance Criteria:**
- [ ] Duplicate events by `external_id` (should be 0 since migration 032's unique index)
- [ ] Bets referencing non-existent events (44 exist today, all `test_stress_Bookie`)
- [ ] Markets attached to finished games (should stay near 0 given the prune sweep)
- [ ] Events past start still marked `scheduled`
- [ ] Ledger hash-chain validity — a validator already exists from migration 018
- [ ] Each check shows a count and a link to the offending rows

## Open questions

- **Alerting.** A dashboard only helps when opened. Is a daily digest email or a
  push on threshold breach worth it, given push infrastructure already exists?
- **Where does it live?** A `#/admin` route inside the member dashboard is
  cheapest. A separate page is better isolated. Preference?
- **Retention/history.** Most panels are "right now". Which of these need trend
  data stored over time, and therefore a table plus a writer?
- **Financial view.** Is the useful number platform handle, or Booki's own
  revenue (subscriptions), or both?

## Prior art in this codebase

- `landing/dashboard/dashboard.js` — Alpine SPA, hash routing, existing card patterns
- `_shared/odds_quota.ts` — quota data source
- `docs/games-sync-redesign.md` — the failure modes US-004 and US-006 exist to catch
