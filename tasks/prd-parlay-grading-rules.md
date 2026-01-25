# PRD: Parlay Grading Rules & Settlement

## Introduction

Implement proper parlay grading logic with configurable push/void handling, leg-by-leg status tracking, and correct settlement math for American odds combination. Currently bets are graded individually without parlay-specific logic.

## Goals

- Define parlay outcome rules (any loss = loss, all wins = win)
- Configurable push/void handling (reduce legs & reprice, or treat as push)
- Proper parlay settlement math with American odds multiplication
- Leg-by-leg grading status display for bookie and player
- Handle edge cases: partial grades, canceled legs

## User Stories

### US-001: Add Bet Type Flag to Bet Model
**Description:** As a developer, I need to track whether a bet is part of a parlay or a single for proper grading logic.

**Acceptance Criteria:**
- [ ] Add `isParlay: Bool` field to Bet model (default false)
- [ ] Add `parlayLegs: Int` field to store total legs in the parlay (default 1)
- [ ] Update Bet init to include these parameters
- [ ] Update BetSlipSheet.submitBets to set isParlay=true and parlayLegs for parlay bets
- [ ] Singles get isParlay=false, parlayLegs=1
- [ ] Project builds and runs in Simulator

### US-002: Add Parlay Push/Void Handling Policy
**Description:** As a bookie, I want to configure how pushes and voids are handled in parlays.

**Acceptance Criteria:**
- [ ] Create enum ParlayPushVoidPolicy with cases: reduceLegReprice, treatAsPush
- [ ] Add `parlayPushVoidPolicy: ParlayPushVoidPolicy` to AcceptancePolicy model (default .reduceLegReprice)
- [ ] Add picker to AcceptancePolicySettingsView for this setting
- [ ] reduceLegReprice: push/void leg removed, remaining legs repriced
- [ ] treatAsPush: any push/void makes entire parlay a push
- [ ] Project builds and runs in Simulator

### US-003: Create ParlayGradingService
**Description:** As a developer, I need a service to calculate parlay outcomes based on leg results.

**Acceptance Criteria:**
- [ ] Create ParlayGradingService.swift in Booki/Services/
- [ ] Add function `calculateParlayOutcome(bets:[Bet], policy:ParlayPushVoidPolicy) -> ParlayOutcome`
- [ ] ParlayOutcome enum: .pending, .win(payout:Decimal), .loss, .push, .partiallyGraded
- [ ] Any leg with .loss → parlay loses
- [ ] All legs with .win → parlay wins (calculate combined payout)
- [ ] Handle push/void based on policy setting
- [ ] Return .partiallyGraded if some legs still awaiting results
- [ ] Project builds and runs in Simulator

### US-004: Implement American Odds Combination Math
**Description:** As a developer, I need correct parlay payout calculation using American odds multiplication.

**Acceptance Criteria:**
- [ ] Add `calculateParlayPayout(stake:Decimal, bets:[Bet]) -> Decimal` to ParlayGradingService
- [ ] Convert each leg's American odds to decimal odds
- [ ] Multiply all decimal odds together
- [ ] Apply to stake: payout = stake × combinedDecimalOdds - stake
- [ ] Handle reduced legs (exclude push/void legs from calculation when policy is reduceLegReprice)
- [ ] Project builds and runs in Simulator

### US-005: Add Leg Status Tracking to Ticket Display
**Description:** As a player, I want to see the status of each leg in my parlay.

**Acceptance Criteria:**
- [ ] Modify TicketHeaderView in TrackView to show leg-by-leg status summary
- [ ] Display format: "2/3 legs graded" or "Awaiting 1 result"
- [ ] Show mini status indicators for each leg (green check, red X, yellow dash, gray pending)
- [ ] Update TicketDetailView to show individual leg grading status
- [ ] Each leg shows: event, selection, odds, and grade result (or "Pending")
- [ ] Project builds and runs in Simulator

### US-006: Create Parlay Grading UI for Bookie
**Description:** As a bookie, I want to see and grade parlay legs individually with the combined outcome shown.

**Acceptance Criteria:**
- [ ] Modify grading views to identify parlay tickets
- [ ] Show all legs grouped together when grading a parlay
- [ ] Display current parlay outcome based on graded legs
- [ ] Show "Parlay Status: X of Y legs graded" header
- [ ] Calculate and show projected payout based on current grades
- [ ] Warn if grading will result in parlay loss
- [ ] Project builds and runs in Simulator

### US-007: Integrate Parlay Logic into Settlement
**Description:** As a developer, I need to settle parlays correctly based on combined outcome.

**Acceptance Criteria:**
- [ ] Modify GradingService to handle parlay settlement
- [ ] When settling a parlay bet, use ParlayGradingService to get outcome
- [ ] For parlay win: payout based on combined odds calculation
- [ ] For parlay loss: player loses stake
- [ ] For parlay push: stake returned (zero profit/loss)
- [ ] Create single ledger entry for parlay outcome (not per-leg)
- [ ] Settlement description shows "Parlay (X legs) - Win/Loss/Push"
- [ ] Project builds and runs in Simulator

### US-008: Handle Partial Grades (Some Legs Pending)
**Description:** As a bookie, I need the system to handle parlays where some legs are graded but others are still pending.

**Acceptance Criteria:**
- [ ] Parlay cannot be settled until all legs are graded
- [ ] Show clear status: "X of Y legs graded - awaiting results"
- [ ] Allow individual leg grading as events complete
- [ ] When final leg is graded, parlay becomes ready to settle
- [ ] Bookie can see intermediate state (e.g., "1 loss already - parlay will lose")
- [ ] Project builds and runs in Simulator

### US-009: Handle Canceled/Void Legs
**Description:** As a bookie, I need to handle when a parlay leg is voided (event canceled, etc.)

**Acceptance Criteria:**
- [ ] Add ability to void individual legs (not just whole bets)
- [ ] When leg voided with reduceLegReprice policy:
  - Remove leg from parlay calculation
  - Recalculate odds with remaining legs
  - If only 1 leg remains, treat as single bet
  - If no legs remain, return stake (push)
- [ ] When leg voided with treatAsPush policy:
  - Entire parlay becomes a push
- [ ] Show void reason in leg display
- [ ] Project builds and runs in Simulator

### US-010: Display Parlay Outcome Summary
**Description:** As a player, I want to see a clear summary of my parlay outcome with the math breakdown.

**Acceptance Criteria:**
- [ ] In TicketDetailView, show "Parlay Outcome" section for parlay tickets
- [ ] Display: Original odds, Adjusted odds (if legs removed), Final outcome
- [ ] Show payout calculation breakdown
- [ ] For reduced parlays: "Originally 4 legs, 1 pushed, paid as 3-leg parlay"
- [ ] Color-coded outcome badge (green win, red loss, yellow push)
- [ ] Project builds and runs in Simulator

## Functional Requirements

- FR-1: Bets track isParlay flag and parlayLegs count
- FR-2: Push/void policy configurable: reduceLegReprice or treatAsPush
- FR-3: Parlay outcome: any loss = loss, all wins = win, push/void per policy
- FR-4: Payout calculation uses decimal odds multiplication
- FR-5: Leg-by-leg status visible to player and bookie
- FR-6: Parlay settlement creates single ledger entry for combined outcome
- FR-7: Partial grades tracked; settlement blocked until all legs graded
- FR-8: Voided legs handled according to policy

## Non-Goals

- No "same game parlay" special rules
- No correlated parlay restrictions
- No maximum leg limits (handled by acceptance policy)
- No live/in-play parlay modifications

## Technical Considerations

- Parlay legs share the same ticketId (already implemented)
- Each leg is still a separate Bet record for individual grading
- ParlayGradingService is stateless - calculates outcome from bet array
- Settlement entry references first bet in parlay (or create parlay reference)
- American to decimal: positive odds → 1 + (odds/100), negative → 1 + (100/|odds|)

## Success Metrics

- Parlays grade correctly with any leg combination
- Push/void handling matches configured policy
- Payout math is accurate for American odds
- Bookie can see intermediate parlay state
- Player understands leg-by-leg status
