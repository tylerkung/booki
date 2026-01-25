# PRD: UX Improvements - Header & Bet Grouping

## Introduction

This PRD covers incremental UX improvements to the existing Booki player experience. These are modifications to existing components, not a rebuild. The focus is on creating a persistent header, reorganizing tabs, and improving how bets are grouped and displayed.

**IMPORTANT:** This builds on the existing `ralph/player-experience-v2` codebase. All changes should modify existing files, not recreate them.

## Goals

- Reorder player tabs to: Games (Home), Track, Settings
- Create a persistent header with user info and balance visible across all tabs
- Remove redundant account sections now that header shows key info
- Group bets by ticket in Track view for better organization
- Add comprehensive bet detail page when tapping a ticket

## User Stories

### US-001: Reorder Player Mode Tabs
**Description:** As a player, I want the tabs ordered as Games, Track, Settings so Games is my home screen.

**Acceptance Criteria:**
- [ ] Modify `ContentView.swift` `playerModeView` function to reorder tabs
- [ ] Tab order: Games (first), Track (second, renamed from "My Bets"), Settings (third)
- [ ] Games tab uses `house.fill` SF Symbol (change from current icon)
- [ ] Track tab uses `list.bullet.rectangle` SF Symbol
- [ ] Settings tab uses `gearshape.fill` SF Symbol
- [ ] Project builds and runs in Simulator

---

### US-002: Create Persistent App Header Component
**Description:** As a player, I want a fixed header at the top showing my profile and balance so I always know my account status.

**Acceptance Criteria:**
- [ ] Create new `AppHeaderView.swift` in `Booki/Views/` folder
- [ ] Header is fixed at top of screen (does not scroll with content)
- [ ] Left side: Circular avatar (~36pt) with user initials in colored background
- [ ] Initials are first letter of first name + first letter of last name (or first 2 letters if single name)
- [ ] Left side: Player name displayed next to avatar
- [ ] Left side section is tappable (navigation handled in next story)
- [ ] Right side: Current balance displayed, formatted as currency
- [ ] Balance color: use `Theme.balanceColor()` helper (green for credit, red for debt)
- [ ] Balance is NOT tappable (informational only)
- [ ] Header has subtle bottom border using `Theme.divider`
- [ ] Header background uses `Theme.cardBackground`
- [ ] Project builds and runs in Simulator

---

### US-003: Integrate Header Into Player Tab Views
**Description:** As a player, I want the header to appear on Games, Track, and Settings tabs with navigation to Account.

**Acceptance Criteria:**
- [ ] Modify `ContentView.swift` to add `AppHeaderView` to each player tab
- [ ] Header appears above the NavigationStack content for each tab
- [ ] Tapping the user section (avatar + name) navigates to `AccountView`
- [ ] Use `NavigationLink` or `navigationDestination` for proper navigation
- [ ] Header receives `player` parameter for name and balance calculation
- [ ] Query ledger entries in header or pass balance as parameter
- [ ] Project builds and runs in Simulator

---

### US-004: Remove "Your Account" Section from Games Tab
**Description:** As a player, I no longer need the "Your Account" card in Games since the header shows my balance.

**Acceptance Criteria:**
- [ ] In `GamesView.swift`, remove the `accountInfoCard` view builder
- [ ] Remove `accountInfoCard` from the `gamesList` LazyVStack
- [ ] Remove unused computed properties: `balanceSummary`, `availableCreditColor` (if not used elsewhere)
- [ ] Games list now starts with favorites section (if any) or sport sections directly
- [ ] No empty space where the card was
- [ ] Project builds and runs in Simulator

---

### US-005: Remove "Account Summary" Section from Track Tab
**Description:** As a player, I no longer need the Account Summary in Track since the header shows my balance.

**Acceptance Criteria:**
- [ ] In `PlayerHistoryView.swift`, remove the `balanceSection` view builder
- [ ] Remove `balanceSection` from the List
- [ ] Remove unused computed properties: `balanceSummary`, `balanceColor`, `availableCreditColor` (if not used elsewhere)
- [ ] Bet history section now takes full space
- [ ] Project builds and runs in Simulator

---

### US-006: Rename PlayerHistoryView to TrackView
**Description:** As a developer, I want the view name to match the tab name for consistency.

**Acceptance Criteria:**
- [ ] Rename file `PlayerHistoryView.swift` to `TrackView.swift`
- [ ] Rename struct from `PlayerHistoryView` to `TrackView`
- [ ] Update `ContentView.swift` to use `TrackView` instead of `PlayerHistoryView`
- [ ] Update navigation title from "My Bets" to "Track"
- [ ] Project builds and runs in Simulator

---

### US-007: Add ticketId Field to Bet Model
**Description:** As a developer, I need to group bets by ticket so bets placed together are associated.

**Acceptance Criteria:**
- [ ] In `Bet.swift`, add `var ticketId: UUID` field to the Bet model
- [ ] Field is required (not optional) - all bets belong to a ticket
- [ ] Add `ticketId` parameter to init with default value `UUID()` for backwards compatibility
- [ ] In `BetConfirmationSheet.swift`, generate ONE shared ticketId for all bets in the submission
- [ ] Pass the same ticketId to all Bet objects created in that submission
- [ ] Existing bets in simulator will need app reinstall (or migration) - document this
- [ ] Project builds and runs in Simulator

---

### US-008: Group Bets by Ticket in Track View
**Description:** As a player, I want my bets grouped by ticket so I can see which bets were placed together.

**Acceptance Criteria:**
- [ ] Modify `TrackView.swift` to group bets by `ticketId`
- [ ] Create computed property to group bets into tickets (Dictionary or array of ticket groups)
- [ ] Display format: Section header shows ticket summary, individual bets listed below
- [ ] Ticket header shows:
  - Ticket type: "Parlay (3 legs)" or "Singles (3 bets)" based on bet count
  - Total stake (sum of all bet stakes)
  - Total potential payout
  - Combined status (Pending, Won, Lost, Partial, Mixed)
- [ ] Individual bets within ticket show: event name, side, odds, stake
- [ ] Tickets sorted by most recent first (based on createdAt of first bet)
- [ ] Reuse or adapt `HistoryBetRowView` for individual bet display
- [ ] Project builds and runs in Simulator

---

### US-009: Create Ticket Detail View
**Description:** As a player, I want to tap a ticket to see comprehensive details including all bets and status history.

**Acceptance Criteria:**
- [ ] Create new `TicketDetailView.swift` in `Booki/Views/` folder
- [ ] Tapping a ticket section header in Track navigates to detail view
- [ ] Detail view shows:
  - Ticket summary (type, total stake, potential/actual payout)
  - All bets in the ticket with full info (event, market, side, odds, stake)
  - Timestamps: bet placed date, graded date (if applicable), settled date (if applicable)
  - For each bet: current status with color coding
  - If settled: result (win/loss/push) and actual payout for each bet
- [ ] For parlays: shows combined odds calculation breakdown
- [ ] Back navigation returns to Track tab
- [ ] Use existing Theme styling for consistency
- [ ] Project builds and runs in Simulator

---

## Functional Requirements

- FR-1: Player tabs ordered as Games, Track, Settings (left to right)
- FR-2: Persistent header fixed at top showing user avatar (initials), name, and balance
- FR-3: Tapping header user section navigates to Account page
- FR-4: Header balance is display-only (not tappable)
- FR-5: "Your Account" card removed from Games tab
- FR-6: "Account Summary" section removed from Track tab
- FR-7: Bets grouped by `ticketId` in Track view
- FR-8: Ticket sections show aggregate info (bet count, type, total stake, combined status)
- FR-9: Tapping ticket navigates to comprehensive detail view
- FR-10: Detail view shows all bets, timestamps, and payout breakdown

## Non-Goals

- No changes to bookie mode
- No changes to bet placement flow (BetSlipSheet, BetConfirmationSheet UI)
- No changes to Account page content
- No real user photos (initials placeholder only for now)
- No changes to search/filter functionality in Games
- No "Repeat Bet" feature (future enhancement)

## Technical Considerations

- **Existing files to modify:**
  - `ContentView.swift` - tab order, header integration
  - `GamesView.swift` - remove account card
  - `PlayerHistoryView.swift` → `TrackView.swift` - rename, remove balance section, add grouping
  - `Bet.swift` - add ticketId field
  - `BetConfirmationSheet.swift` - generate shared ticketId
- **New files to create:**
  - `AppHeaderView.swift` - persistent header component
  - `TicketDetailView.swift` - bet ticket detail page
- Use `@Query` for ledger entries to calculate real-time balance in header
- Use SwiftData's lightweight migration for ticketId (or require app reinstall for testing)
- Consider `LazyVStack` with section headers for ticket grouping performance

## Design Considerations

- Header height: ~60pt to be compact but readable
- Avatar circle: ~36pt diameter with bold white initials on accent background
- Balance: clearly readable but not overly prominent (subheadline weight)
- Ticket section headers: visually distinct from individual bet rows (bold, larger text)
- Use existing `Theme` colors: `cardBackground`, `accent`, `danger`, `textPrimary`, `textSecondary`
- Follow existing navigation patterns (NavigationStack, navigationDestination)

## Success Metrics

- Header visible and functional across all player tabs
- Bets correctly grouped by ticket
- No regression in existing functionality
- Navigation flows work correctly (header → Account, ticket → detail)
- App builds without errors

## Open Questions

- None - requirements are clear
