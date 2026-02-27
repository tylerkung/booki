# Web Dashboard Parity PRD

## Overview

Bring the Booki web dashboard (`landing/dashboard/`) to full feature parity with the iOS organizer experience. The current dashboard covers ~40% of iOS functionality — it handles basic member listing, pick browsing, and subscription management but is missing grading/voiding operations, member detail views, pick detail views, settings, and account management.

**Tech stack**: Alpine.js + Supabase JS CDN (no build step), hash-based routing, dark theme CSS.

**Guiding principle**: Every organizer operation available in the iOS app should be possible from the web dashboard. The web dashboard is the primary management tool for organizers who subscribed via Stripe on desktop.

### iOS Feature Audit (Source of Truth)

Current iOS bookie capabilities verified against actual code:

| Feature | iOS Status | Tier | Location |
|---------|-----------|------|----------|
| Manual grading (Win/Loss/Push) | Exists | All | `BetsListView.swift` pick detail |
| Pick voiding | Exists | All | `BetsListView.swift` pick detail |
| Bulk grade + settle | Exists (orphaned) | All | `GradingView.swift` (not routed to any tab) |
| Grade override | Exists | **Pro** | `BetsListView.swift` pick detail |
| Reverse settlement | Exists | **Pro** | `BetsListView.swift` pick detail |
| Pick Management settings | **Missing** | Pro | `PickManagementSettingsView.swift` referenced but file doesn't exist |
| Settle Up / Adjust Balance | Exists | All | `PlayerAnalyticsDetailView.swift` |
| Member archive/remove | Exists | All | `PlayerAnalyticsDetailView.swift` |
| Edit display name / credit limit | Exists | All | `PlayerAnalyticsDetailView.swift` |

**Notes:**
- `GradingView.swift` is fully implemented but **not wired into any tab** — grading is done inline from pick detail in `BetsListView.swift`
- `PickManagementSettingsView.swift` doesn't exist — the Settings row references it but leads nowhere
- Grade override and reverse settlement are **Pro-only** features
- Auto-pilot mode (auto-accept, auto-grade, auto-settle) handles most grading — manual grading is for edge cases and corrections

---

## Part 1: Member Detail View

### US-1: Member Detail Page

**Route**: `#/members/:playerId`

**What exists**: Flat table with name, balance, credit, status, settle/adjust buttons. No drill-down.

**What's needed**: Clicking a member row navigates to a detail page matching iOS `PlayerAnalyticsDetailView`.

#### Sections

1. **Header Card**
   - Display name (editable inline — pencil icon, saves to `players.display_name` via Supabase update)
   - Balance with color coding (green = owes you, red = you owe)
   - Credit limit (editable inline — saves to `players.credit_limit`)
   - Credit utilization progress bar (balance / credit_limit)

2. **Action Buttons**
   - Settle Up (reuse existing modal)
   - Adjust Balance (reuse existing modal)
   - Overflow menu: Archive Member, Remove Member

3. **Performance Card**
   - Record: W-L-P (wins, losses, pushes from `bets` table)
   - Net PnL (sum of ledger entries excluding `paymentLogged`)
   - Win rate percentage

4. **Recent Activity**
   - Merged chronological list of bets + ledger entries (last 10)
   - "View All" expands to full list
   - Each row: date, type badge, description, amount

5. **Picks Section**
   - Filter chips: Open / Graded
   - List of picks for this member (reuse pick row component)
   - "See All" navigates to Picks view pre-filtered by member

#### Member Actions

- **Archive**: Soft delete — sets `players.status = 'archived'`, preserves history. Confirmation modal.
- **Remove**: Unlinks from bookie — NULLs `bookie_id` and `auth_user_id`. Confirmation modal with warning.
- **Edit display name**: Inline text input, saves on blur/enter. Supabase `players.update({ display_name })`.
- **Edit credit limit**: Inline number input, saves on blur/enter. Supabase `players.update({ credit_limit })`.

#### Data Queries
```
players.select('*').eq('id', playerId)
bets.select('*').eq('player_id', playerId).order('created_at', desc).limit(50)
ledger_entries.select('*').eq('player_id', playerId).order('created_at', desc).limit(50)
```

#### Acceptance Criteria
- [ ] Member name in members table is clickable, navigates to `#/members/:id`
- [ ] Header shows balance, credit limit, utilization bar
- [ ] Display name and credit limit are editable inline
- [ ] Performance card shows W-L-P record, PnL, win rate
- [ ] Recent activity merges bets + ledger chronologically
- [ ] Open/Graded filter works on picks section
- [ ] Archive and Remove actions work with confirmation modals
- [ ] Back button returns to members list

---

## Part 2: Pick Detail View

### US-2: Pick Detail Modal/Page

**Route**: `#/picks/:betId` (or modal overlay)

**What exists**: Flat table row with date, member, type, pick, odds, stake, status. No detail view.

**What's needed**: Clicking a pick row opens a detail view matching iOS `BetDetailView` / `TicketDetailView`.

#### Sections

1. **Hero Card**
   - Status badge (large, colored)
   - Team/selection name
   - Event name and date
   - Market type (Moneyline, Spread, Total, Outright)

2. **Financials Card**
   - Odds (American format)
   - Stake amount
   - Potential return (stake * decimal odds)
   - Actual P/L (if settled)

3. **Parlay Legs** (if `bet_type === 'parlay'`)
   - List all legs from `bet_legs` table
   - Each leg: team, market, odds, status badge
   - Combined odds display

4. **Activity Timeline**
   - Audit events from `settlement_events` table (if any)
   - Created, accepted, graded, settled timestamps
   - Settlement amounts

5. **Actions** (contextual based on status, matching iOS `BetsListView` behavior)
   - `accepted` → Grade buttons (Win / Loss / Push) + Void button
   - `graded` → Void button + Override Grade (Pro only)
   - `settled` → Reverse Settlement (Pro only) + Override Grade (Pro only)
   - `void` / `declined` → No actions

#### Data Queries
```
bets.select('*').eq('id', betId)
bet_legs.select('*').eq('bet_id', betId)  // or eq('ticket_id', bet.ticket_id)
settlement_events.select('*').eq('bet_id', betId).order('created_at')
```

#### Acceptance Criteria
- [ ] Pick rows in picks table are clickable
- [ ] Detail view shows hero, financials, legs (if parlay), activity
- [ ] Grading actions appear for `accepted` status picks
- [ ] Settlement actions appear for `graded` status picks
- [ ] Override/reverse actions appear for `settled` status picks
- [ ] Close/back returns to picks list

---

## Part 3: Pick Grading & Voiding

### US-3: Manual Pick Grading & Voiding from Pick Detail

**What exists on iOS**: Inline grading in `BetsListView.swift` pick detail — Win/Loss/Push buttons on `accepted` picks, Void button on `accepted`/`graded` picks. Auto-pilot handles most grading automatically; manual grading is for corrections and edge cases (futures, manual mode).

**What exists on web**: Nothing — no grading or voiding UI.

**What's needed**: Grading and voiding actions on the pick detail view (US-2). No separate grading queue page — matches iOS pattern of inline actions on pick detail.

#### Grading Actions (on Pick Detail, for `accepted` status picks)
- Grade buttons: Win / Loss / Push
- Each calls `grade_bet` edge function with the chosen outcome
- Confirmation modal before grading
- After grading, pick status updates to `graded`
- UI refreshes immediately

#### Void Action (on Pick Detail, for `accepted` or `graded` status picks)
- Void button (separate from grade buttons, styled as destructive)
- Calls `grade_bet` edge function with `outcome: 'void'`
- Confirmation modal: "Void this pick? This will cancel it with no balance impact."
- After voiding, pick status updates to `void`

#### Edge Functions Used
```
grade_bet — { bet_id, outcome: 'won'|'lost'|'push'|'void', idempotency_key }
```

#### Acceptance Criteria
- [ ] Win/Loss/Push buttons appear on `accepted` picks in detail view
- [ ] Void button appears on `accepted` and `graded` picks
- [ ] Grading calls `grade_bet` with confirmation modal
- [ ] Voiding calls `grade_bet` with outcome `void`
- [ ] Pick status updates immediately after action
- [ ] Idempotency keys prevent duplicate operations

### US-4: Override Grade & Reverse Settlement (Pro Only)

**What exists on iOS**: Both features exist in `BetsListView.swift` pick detail, gated to Pro tier. Override requires a reason. Reverse shows balance impact preview.

**What's needed**: Same actions on web pick detail, gated to Pro.

#### Override Grade (from Pick Detail)
- Available on `graded` or `settled` picks, **Pro tier only**
- Select new grade: Win / Loss / Push / Void
- Reason input (required)
- Calls `override_grade` edge function (atomically reverses old settlement if settled, applies new grade, re-settles)
- Free tier: button disabled with "Upgrade to Pro" tooltip

#### Reverse Settlement (from Pick Detail)
- Available on `settled` picks, **Pro tier only**
- Confirmation modal with warning about ledger impact
- Calls `reverse_settlement` edge function
- Pick reverts to `graded` status
- Free tier: button disabled with "Upgrade to Pro" tooltip

#### Edge Functions Used
```
override_grade       — { bet_id, new_outcome, reason, idempotency_key }
reverse_settlement   — { bet_id, idempotency_key }
```

#### Acceptance Criteria
- [ ] Override Grade button appears on graded/settled picks (Pro only)
- [ ] Reason field is required for overrides
- [ ] Reverse Settlement button appears on settled picks (Pro only)
- [ ] Free tier sees disabled buttons with upgrade prompt
- [ ] Both operations update UI immediately
- [ ] Activity timeline shows override/reversal events

---

## Part 4: Enhanced Dashboard

### US-5: Dashboard Parity with iOS AnalyticsDashboardView

**What exists**: 4 stat tiles (PnL, Active Members, Open Picks, Total Volume) + recent activity table.

**What's needed**: Match iOS dashboard with exposure metrics, risk indicators, and pro-gated analytics.

#### Additional Summary Cards (2x2 grid → 2x3 grid)
- **Net Exposure**: Sum of open bet potential payouts (liability). Clickable → scrolls to members section.
- **Top Risk**: Member with highest open exposure. Clickable → navigates to member detail.

#### Members Section (below stats)
- Compact member cards with:
  - Name, balance, utilization bar
  - Open picks count, open stake amount
  - Attention tags (if applicable — see US-6)
- Sorted by risk (highest exposure first)

#### Pro-Gated Analytics (blur overlay for free tier)
- **Sport Performance**: Per-sport breakdown — picks count, staked, net PnL, bookie win rate
- **Futures Activity**: Open futures count, total staked, top 3 popular selections

#### Acceptance Criteria
- [ ] Net Exposure and Top Risk cards added to stats grid
- [ ] Members section shows compact cards with risk metrics
- [ ] Sport Performance section shows per-sport breakdown (pro only)
- [ ] Futures Activity section shows open futures (pro only)
- [ ] Free tier sees blur overlay with "Upgrade to Pro" on gated sections

### US-6: Attention Tags

**What's needed**: Same attention/behavior tags as iOS `PlayerAnalyticsDetailView`.

Tags (computed client-side from bets + ledger data):
- **Picks Pending** — has `pending` status bets
- **Overdue** — negative balance older than threshold
- **On Heater** — 3+ consecutive wins
- **Cold Streak** — 3+ consecutive losses
- **Whale** — average stake > 2x group average
- **Degen** — 5+ bets in 24h window
- **Parlay Demon** — 60%+ of bets are parlays

Display as colored chips on member cards (dashboard + member detail).

#### Acceptance Criteria
- [ ] Tags computed from bet/ledger data
- [ ] Tags displayed on dashboard member cards
- [ ] Tags displayed on member detail page
- [ ] Tags are tappable with explainer tooltip/modal

---

## Part 5: Settings & Account Management

### US-7: Settings Page

**Route**: `#/settings`

Add **Settings** nav item in sidebar (below Subscription).

#### Sections

1. **Profile**
   - Edit organizer name (updates `bookies.name`)
   - Display email (read-only)
   - Change Password button → modal with current + new password fields (Supabase `auth.updateUser`)

2. **Member Settings**
   - Default credit limit for new invites (updates `bookies.default_credit_limit`)

3. **Pick Management** (Pro only, disabled for free)
   - Toggle: Allow futures multi-picks (`bookies.allow_futures_parlays`)
   - Note: iOS `PickManagementSettingsView` doesn't exist yet — the settings row references it but the file is missing. Manual acceptance/grading toggles (`manual_bet_acceptance`, `manual_bet_grading`) exist as DB columns but have no UI on either platform. Web should implement what iOS has columns for, even if iOS hasn't built the view yet.

4. **About**
   - Links: Website, Terms of Service, Privacy Policy
   - App version / copyright

5. **Danger Zone**
   - Step Down as Organizer (only if no active members/invites) → calls `step_down_organizer`
   - Delete Account → two-step confirmation → calls `delete_account`

#### Acceptance Criteria
- [ ] Settings nav item in sidebar
- [ ] Profile editing works (name, password)
- [ ] Member settings (default credit limit) saves
- [ ] Pick Management toggles work (pro-gated)
- [ ] Step Down works with validation
- [ ] Delete Account works with two-step confirmation
- [ ] About section shows links

---

## Part 6: Invites Management

### US-8: Invites List & Management

**What exists**: Create invite modal with email + credit limit. Copy code button.

**What's needed**: View and manage existing invites.

#### Pending Invites Section (Members page, above member table)
- List of unclaimed invites from `invites` table
- Each row: code, email (if set), credit limit, created date
- Actions: Copy Code, Copy Link, Delete Invite
- Delete calls Supabase `invites.delete().eq('id', inviteId)` (only if unclaimed)

#### Member Capacity Banner
- Shows `activeMemberCount / limit` (3 free, 50 pro)
- Warning state when at or near limit
- Blocks invite creation when at limit

#### Data Queries
```
invites.select('*').eq('bookie_id', bookie.id).is('claimed_at', null).order('created_at', desc)
```

#### Acceptance Criteria
- [ ] Pending invites section shown above members table
- [ ] Copy Code and Copy Link actions work
- [ ] Delete invite works with confirmation
- [ ] Capacity banner shows member count vs limit
- [ ] Invite creation blocked at capacity

---

## Part 7: UX Polish & Infrastructure

### US-9: Loading States

**What's needed**: Shimmer/skeleton placeholders matching iOS pattern.

- Dashboard stat tiles show shimmer while loading
- Members table shows skeleton rows
- Picks table shows skeleton rows
- Member detail shows skeleton sections

### US-10: Empty States

**What exists**: Basic "No X found" text.

**What's needed**: Illustrated empty states with CTAs.
- No members → "Invite your first member" with invite button
- No picks → "No picks yet. Members will appear here once they start placing picks."
- No activity → "Activity will show up as members place picks and balances change."

### US-11: Responsive Polish

- Sidebar collapses to hamburger on mobile (exists)
- Tables become card-based on mobile (< 768px)
- Modals are full-screen on mobile
- Stats grid: 2x2 on mobile, 3x2 on desktop

### US-12: Real-time Updates

**What's needed**: Supabase Realtime subscriptions for live data.

- Subscribe to `bets` changes (new picks appear instantly)
- Subscribe to `ledger_entries` changes (balances update live)
- Subscribe to `players` changes (new members appear instantly)
- Visual indicator when new data arrives (subtle flash/highlight)

#### Implementation
```javascript
supabase.channel('bookie-changes')
  .on('postgres_changes', { event: '*', schema: 'public', table: 'bets', filter: `bookie_id=eq.${bookie.id}` }, () => loadPicks())
  .on('postgres_changes', { event: '*', schema: 'public', table: 'players', filter: `bookie_id=eq.${bookie.id}` }, () => loadPlayers())
  .on('postgres_changes', { event: '*', schema: 'public', table: 'ledger_entries', filter: `bookie_id=eq.${bookie.id}` }, () => { loadPlayers(); loadDashboard(); })
  .subscribe()
```

### US-13: Pagination & Sorting

- Picks: Load 50 per page, "Load More" button
- Members: Client-side sort by name, balance, credit limit (clickable column headers)
- Activity: Load 20 per page with pagination

---

## Architecture Notes

### Routing
Current hash-based routing (`#/dashboard`, `#/members`, etc.) extended with parameterized routes:
- `#/members/:id` — member detail
- `#/picks/:id` — pick detail (or modal overlay)
- `#/settings` — settings page

No dedicated grading page — grading is done inline from pick detail (matching iOS pattern).

### File Structure
```
landing/dashboard/
  index.html          — Auth (login/signup)
  app.html            — SPA shell (sidebar, route container, modals)
  dashboard.js        — Alpine.js app logic (extend existing)
  dashboard.css       — Styles (extend existing)
```

Keep everything in `dashboard.js` — Alpine.js data store pattern handles the complexity without needing separate files. Split only if the file exceeds ~1500 lines.

### Edge Functions Already Available
| Function | Purpose | Status |
|----------|---------|--------|
| `create_invite` | Create invite code | Used |
| `adjust_balance` | Settle up / adjust | Used |
| `create_checkout_session` | Stripe checkout | Used |
| `create_customer_portal` | Stripe portal | Used |
| `grade_bet` | Grade single bet | **Not used** |
| `settle_bet` | Settle graded bet | **Not used** |
| `settle_parlay` | Settle parlay ticket | **Not used** |
| `override_grade` | Change grade + re-settle | **Not used** |
| `reverse_settlement` | Undo settlement | **Not used** |
| `step_down_organizer` | Remove bookie status | **Not used** |
| `delete_account` | Delete all bookie data | **Not used** |

No new edge functions needed — all operations are supported by existing backend.

### Pro Tier Gating
Web subscription is Stripe only ($49.99/mo). Pro-gated features (matching iOS):
- Override Grade (on graded/settled picks)
- Reverse Settlement (on settled picks)
- Pick Management settings (manual acceptance/grading toggles, futures multi-picks)
- Sport Performance analytics
- Futures Activity analytics
- Member limit: 3 (free) → 50 (pro)

Free tier features (no gate):
- Manual grading (Win/Loss/Push) on accepted picks
- Pick voiding on accepted/graded picks
- Settle Up / Adjust Balance
- Member management (archive, remove, edit name/credit)
- Invites

---

## Implementation Priority

| Priority | User Story | Effort | Impact |
|----------|-----------|--------|--------|
| P0 | US-2: Pick Detail View | Medium | Critical — context for all pick operations |
| P0 | US-3: Grading & Voiding (from Pick Detail) | Medium | Critical — core organizer corrections |
| P1 | US-1: Member Detail View | Medium | High — essential member management |
| P1 | US-4: Override Grade & Reverse (Pro) | Medium | High — error correction, Pro-gated |
| P1 | US-7: Settings Page | Medium | High — configuration + account mgmt |
| P2 | US-5: Enhanced Dashboard | Medium | Medium — better overview |
| P2 | US-8: Invites Management | Small | Medium — manage pending invites |
| P2 | US-6: Attention Tags | Small | Medium — behavioral insights |
| P3 | US-9: Loading States | Small | Low — polish |
| P3 | US-10: Empty States | Small | Low — polish |
| P3 | US-11: Responsive Polish | Medium | Low — mobile web UX |
| P3 | US-12: Real-time Updates | Medium | Low — live data |
| P3 | US-13: Pagination & Sorting | Small | Low — scale |

---

## Verification Checklist

- [ ] All edge functions callable from web with proper auth headers
- [ ] CORS headers allow requests from bookisports.com
- [ ] RLS policies allow organizer to read/write scoped data
- [ ] Pro tier gating matches iOS behavior
- [ ] Grading + settlement creates correct ledger entries
- [ ] Override + reversal maintains ledger integrity
- [ ] Delete account fully cleans up via edge function
- [ ] Responsive layout works on mobile Safari / Chrome
- [ ] All modals have proper error handling + loading states
