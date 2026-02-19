# PRD: Weekly Settlement Workflow

## Introduction

Implement a complete weekly settlement workflow for bookies to close out periods, review player balances, track payments, and export reports. Settlements are organized by week-ending date with per-player breakdowns showing starting balance, activity, payments, and ending balance.

## Goals

- Allow bookies to select and manage settlement periods (week ending date)
- Generate per-player settlement reports with full breakdown
- Track "marked as settled" state per player per period
- Automate collection status based on balance and time
- Support partial payments and rolling balances
- Export settlement reports to CSV

## User Stories

### US-001: Create SettlementPeriod Model
**Description:** As a developer, I need a model to track weekly settlement periods.

**Acceptance Criteria:**
- [ ] Create SettlementPeriod.swift in Booki/Models/
- [ ] Model is a SwiftData @Model class
- [ ] Fields: id (UUID), weekEndingDate (Date), createdAt (Date)
- [ ] weekEndingDate represents the Sunday ending the settlement week
- [ ] Add computed property `weekStartDate` (7 days before weekEndingDate)
- [ ] Add computed property `dateRangeDescription` for display (e.g., "Jan 13 - Jan 19, 2026")
- [ ] Register model in BookiApp.swift schema
- [ ] Project builds and runs in Simulator

### US-002: Create PlayerSettlement Model
**Description:** As a developer, I need a model to track per-player settlement status within a period.

**Acceptance Criteria:**
- [ ] Create PlayerSettlement.swift in Booki/Models/
- [ ] Model is a SwiftData @Model class
- [ ] Fields: id (UUID), isSettled (Bool, default false), settledAt (Date?), notes (String?)
- [ ] Relationships: settlementPeriod (SettlementPeriod), player (Player)
- [ ] isSettled marks when bookie has reviewed and closed this player for the period
- [ ] Register model in BookiApp.swift schema
- [ ] Project builds and runs in Simulator

### US-003: Create SettlementService for Calculations
**Description:** As a developer, I need a service to calculate settlement report data.

**Acceptance Criteria:**
- [ ] Create SettlementService.swift in Booki/Services/
- [ ] Create struct PlayerSettlementReport with fields: player, startingBalance, betsWon, betsLost, betsPushed, netResults, paymentsReceived, adjustments, endingBalance
- [ ] Add function calculatePlayerReport(player:period:bets:ledgerEntries:) -> PlayerSettlementReport
- [ ] startingBalance = balance at weekStartDate (sum ledger entries before period)
- [ ] netResults = sum of settlements within the period
- [ ] paymentsReceived = sum of payment ledger entries within period
- [ ] adjustments = sum of adjustment ledger entries within period
- [ ] endingBalance = startingBalance + netResults - paymentsReceived + adjustments
- [ ] Add function calculateAllPlayerReports(players:period:bets:ledgerEntries:) -> [PlayerSettlementReport]
- [ ] Project builds and runs in Simulator

### US-004: Create Settlement Period Selection UI
**Description:** As a bookie, I want to select which week to view for settlement.

**Acceptance Criteria:**
- [ ] Create WeeklySettlementView.swift in Booki/Views/
- [ ] Add navigation to WeeklySettlementView from Dashboard or Settings
- [ ] Show week picker with recent weeks (current + past 4 weeks)
- [ ] Display selected week's date range prominently
- [ ] Create new SettlementPeriod if one doesn't exist for selected week
- [ ] Show summary stats: total players, settled count, total owed, total owed to players
- [ ] Use Theme styling consistent with app
- [ ] Project builds and runs in Simulator

### US-005: Create Player Settlement List
**Description:** As a bookie, I want to see all players and their settlement status for the selected week.

**Acceptance Criteria:**
- [ ] In WeeklySettlementView, list all active players with settlement summary
- [ ] Each row shows: player name, starting balance, net results, payments, ending balance
- [ ] Color code ending balance: red if player owes, green if bookie owes
- [ ] Show checkmark or badge for players marked as settled
- [ ] Add filter: All, Unsettled Only, Settled Only
- [ ] Sort by ending balance (highest owed first) by default
- [ ] Tap row to navigate to player settlement detail
- [ ] Project builds and runs in Simulator

### US-006: Create Player Settlement Detail View
**Description:** As a bookie, I want to see full breakdown and mark a player as settled.

**Acceptance Criteria:**
- [ ] Create PlayerSettlementDetailView.swift in Booki/Views/
- [ ] Show full settlement report: starting balance, each category of activity, ending balance
- [ ] List individual bets settled in this period with results
- [ ] List payments received in this period
- [ ] List adjustments made in this period
- [ ] "Mark as Settled" button (creates/updates PlayerSettlement record)
- [ ] Show settled timestamp if already settled
- [ ] Allow adding notes when marking settled
- [ ] Project builds and runs in Simulator

### US-007: Add Quick Payment Recording from Settlement
**Description:** As a bookie, I want to record a payment directly from the settlement view.

**Acceptance Criteria:**
- [ ] Add "Record Payment" button in PlayerSettlementDetailView
- [ ] Opens sheet/modal with amount input (pre-filled with amount owed)
- [ ] Creates LedgerEntry with type .payment
- [ ] Refreshes settlement report after payment recorded
- [ ] Support partial payments (any amount up to owed)
- [ ] Show confirmation after payment recorded
- [ ] Project builds and runs in Simulator

### US-008: Automate Collection Status Updates
**Description:** As a bookie, I want collection status to update based on settlement state.

**Acceptance Criteria:**
- [ ] In SettlementService, add function updateCollectionStatuses(players:period:)
- [ ] If player owes money and period ended > 7 days ago and not settled: set to .overdue
- [ ] If player owes money and marked as settled with notes containing "promised": set to .promised
- [ ] Provide manual override capability (existing collection status UI)
- [ ] Run status update when viewing settlement period
- [ ] Show collection status badge in player settlement list
- [ ] Project builds and runs in Simulator

### US-009: Export Settlement Report to CSV
**Description:** As a bookie, I want to export the settlement report for record keeping.

**Acceptance Criteria:**
- [ ] Add "Export" button in WeeklySettlementView header
- [ ] Generate CSV with columns: Player, Starting Balance, Bets Won, Bets Lost, Net Results, Payments, Adjustments, Ending Balance, Settled
- [ ] Include all players in the export
- [ ] Filename format: settlement_YYYY-MM-DD.csv (week ending date)
- [ ] Use ShareLink or UIActivityViewController to share/save file
- [ ] Project builds and runs in Simulator

### US-010: Handle Rolling Balances Between Periods
**Description:** As a developer, I need to ensure balances roll correctly from week to week.

**Acceptance Criteria:**
- [ ] Starting balance for any period = ending balance of previous period
- [ ] Verify SettlementService calculates this correctly using ledger entry dates
- [ ] If no activity in a period, starting balance = ending balance (carry forward)
- [ ] Add "Previous Period" and "Next Period" navigation in WeeklySettlementView
- [ ] Show warning if viewing a period with unsettled prior periods
- [ ] Project builds and runs in Simulator

## Functional Requirements

- FR-1: SettlementPeriod tracks week-ending dates (Sundays)
- FR-2: PlayerSettlement tracks per-player settled status per period
- FR-3: Settlement report calculates: starting balance, net results, payments, adjustments, ending balance
- FR-4: Bookie can select week and view all player settlement summaries
- FR-5: Bookie can mark individual players as settled with optional notes
- FR-6: Payments can be recorded directly from settlement view
- FR-7: Collection status updates based on settlement state and time
- FR-8: Settlement data exportable to CSV
- FR-9: Balances roll forward correctly between periods

## Non-Goals

- PDF export (CSV only for now)
- Automated payment reminders/notifications
- Multi-currency support
- Tax report generation

## Technical Considerations

- Settlement calculations are derived from existing Bet and LedgerEntry data
- No duplication of amounts - always calculate from source of truth
- SettlementPeriod and PlayerSettlement are metadata only (status tracking)
- Use Date ranges carefully (start of day, end of day boundaries)
- Consider timezone handling for week boundaries

## Success Metrics

- Bookie can close out a week in under 2 minutes
- All balance calculations match manual verification
- Export contains accurate, complete data
- Collection status reflects actual payment state
