# PRD: Bookie Attention Dashboard & Risk Tracking

## Introduction

Transform the bookie dashboard from passive stats into an active command center that answers: **"What do I need to pay attention to right now?"**

Bookies don't open the app to browse statistics. They open it to:
- Collect money
- Manage risk
- Make decisions
- Avoid problems

The dashboard must become a prioritized action feed that surfaces who owes money, who is risky, where exposure is dangerous, and what needs attention today.

## Target User

**Primary:** Small/mid-scale bookie running 10–200 players

**Behavior:** Checks app multiple times per day during sports season

**Core anxieties:**
- "Who owes me?"
- "Am I overexposed tonight?"
- "Who is becoming a problem?"

## Goals

### User Goals
- Instantly understand money risk, player risk, and game risk
- See prioritized tasks that need attention today
- Take action directly from the dashboard

### Business Goals
- Increase daily active usage
- Create weekly ritual usage around settlements
- Increase retention after week 4
- Establish Booki as mission-critical daily tool

## Success Metrics

**Primary:**
- Dashboard opens per day/bookie ↑
- Weekly active bookies ↑
- Retention after week 4 ↑

**Secondary:**
- Settlement actions per week ↑
- Exposure checks per day ↑

## Core UX Principle

**Action-driven, not data-driven.**

Every section answers:
1. What needs attention?
2. Why?
3. What should I do?

## New Dashboard Structure

Top-to-bottom priority order:
1. Attention Required (alerts feed)
2. Weekly Settlements
3. Player Risk Watchlist
4. Tonight's Exposure
5. Existing metrics (moved lower)

---

## User Stories

### US-001: Attention Feed Component
**Description:** As a bookie, I want to see urgent items aggregated at the top of my dashboard so I know what needs immediate attention.

**Acceptance Criteria:**
- [ ] Add `AttentionFeedView` component at top of DashboardView
- [ ] Show alert rows for: overdue settlements, players at credit limit, high exposure games, large bets placed
- [ ] Each row has icon, description text, and is tappable
- [ ] Tap navigates to relevant detail screen (PlayerDetailView, EventDetailView, etc.)
- [ ] Empty state shows subtle "All clear" message
- [ ] Use Theme.danger for urgent items, Theme.warning for warnings
- [ ] Typecheck passes

### US-002: Settlement Snapshot Card
**Description:** As a bookie, I want to see my weekly settlement status at a glance so I can track collections.

**Acceptance Criteria:**
- [ ] Add `SettlementSnapshotCard` component to dashboard below attention feed
- [ ] Display: total owed to bookie, total owed to players, # unpaid players, # overdue players
- [ ] Show current settlement period date range
- [ ] "View Settlements" button navigates to WeeklySettlementView
- [ ] If no active settlement period, show "Next settlement in X days" or setup prompt
- [ ] Use existing SettlementService/BalanceService for calculations
- [ ] Typecheck passes

### US-003: Player Risk Watchlist Card
**Description:** As a bookie, I want to see which players need attention so I can proactively manage risk.

**Acceptance Criteria:**
- [ ] Add `PlayerRiskWatchlistCard` component to dashboard
- [ ] Auto-populate with players matching ANY risk signal (see US-004)
- [ ] Show player name, balance/credit limit ratio, and risk badge(s)
- [ ] Risk badges: "Near Limit" (orange), "Overdue" (red), "Hot Streak" (green), "Losing Big" (red)
- [ ] Tap row navigates to PlayerDetailView
- [ ] Limit to 5 players max, "View All" link if more
- [ ] Empty state: "No players need attention" with checkmark icon
- [ ] Typecheck passes

### US-004: Player Risk Signal Calculation
**Description:** As a bookie, I want the system to automatically identify risky players based on defined criteria.

**Acceptance Criteria:**
- [ ] Create `PlayerRiskService` in Services folder
- [ ] Risk signal: Balance > 75% of credit limit → "Near Limit"
- [ ] Risk signal: Has overdue settlement → "Overdue"
- [ ] Risk signal: Top 3 winners in last 7 days → "Hot Streak"
- [ ] Risk signal: Top 3 losers in last 7 days → "Losing Big"
- [ ] Return list of players with their applicable risk signals
- [ ] Typecheck passes

### US-005: Tonight's Exposure Card
**Description:** As a bookie, I want to see my exposure for tonight's games so I can manage risk before games start.

**Acceptance Criteria:**
- [ ] Add `TonightsExposureCard` component to dashboard
- [ ] "Tonight" = events starting between now and end of day (local timezone)
- [ ] Display: total potential loss, highest risk game name, # games exceeding threshold
- [ ] High exposure threshold: $1,000 default (can be hardcoded for v1)
- [ ] Highlight highest risk game with potential loss amount
- [ ] "View Exposure" button (can link to GamesView filtered for today initially)
- [ ] If no games tonight, show "No games tonight" empty state
- [ ] Use existing ExposureService for calculations
- [ ] Typecheck passes

### US-006: Reorganize Dashboard Layout
**Description:** As a bookie, I want the new cards arranged in priority order with existing metrics moved lower.

**Acceptance Criteria:**
- [ ] Update DashboardView layout order: AttentionFeed → SettlementSnapshot → PlayerRiskWatchlist → TonightsExposure → existing metrics
- [ ] Add section headers with subtle styling (Theme.textMuted, small caps)
- [ ] Existing metric cards (today's action, pending bets, etc.) grouped under "Activity" section
- [ ] Smooth scrolling, no performance issues
- [ ] Typecheck passes

### US-007: Quick Actions from Settlement Card
**Description:** As a bookie, I want quick actions on the settlement card so I can mark payments without navigating away.

**Acceptance Criteria:**
- [ ] Settlement card shows list of top 3 unpaid players inline
- [ ] Each player row has "Mark Paid" quick action button
- [ ] Tapping "Mark Paid" shows confirmation, then updates settlement status
- [ ] "Send Reminder" action (can be placeholder/no-op for v1)
- [ ] Actions update card totals immediately (optimistic UI)
- [ ] Typecheck passes

---

## Functional Requirements

- FR-1: Dashboard loads all new cards without noticeable delay (<500ms perceived)
- FR-2: All monetary values formatted as currency with Theme styling
- FR-3: Risk calculations use existing services (BalanceService, ExposureService, SettlementService)
- FR-4: Tapping any card row deep-links to the appropriate detail view
- FR-5: Dashboard data refreshes on appear and pull-to-refresh
- FR-6: Empty states are friendly and informative, not error-like

## Non-Goals (Out of Scope)

- Push notifications for alerts
- Configurable thresholds UI (hardcoded for v1)
- Advanced risk scoring or ML
- Full analytics/reporting dashboards
- Alert history or dismissal

## Design Considerations

- Use existing Theme colors: `Theme.danger` for urgent, `Theme.warning` for caution, `Theme.accent` for positive
- Cards should use `Theme.cardBackground` with subtle shadows
- Badge styling should match existing `StatusBadge` component patterns
- Attention feed items should feel like notifications (icon + text + chevron)

## Technical Considerations

- No schema changes required for v1
- New `PlayerRiskService` encapsulates risk signal logic
- Leverage existing `ExposureService.calculateEventExposure()`
- Leverage existing `SettlementService` and settlement period queries
- Dashboard should use `@Query` for reactive updates when data changes

## Open Questions

1. Should risk thresholds be configurable in Settings for v2?
2. Should we track which alerts were "seen" to avoid showing stale alerts?
3. What's the right "tonight" window - today only, or next 24 hours?
