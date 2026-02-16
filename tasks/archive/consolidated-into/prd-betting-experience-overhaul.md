# PRD: Betting Experience Overhaul

## Introduction

This PRD addresses critical bugs and UX issues in the betting system discovered during a comprehensive audit. The most severe issue is that **parlay bets are being submitted as individual singles**, completely breaking the parlay feature. Additionally, bet display needs improvements for clarity, and edge cases need to be handled properly.

## Goals

- Fix the parlay submission bug so parlays are created correctly on the server
- Ensure bet display is clear and consistent for both bookies and players
- Make event information always visible and unambiguous
- Handle all edge cases for different bet types
- Create a swift, reliable betting experience

## Audit Findings Summary

### Critical Bugs

1. **Parlay Submission Broken** - When user selects parlay mode with 3 games, system creates 3 individual single bets instead of 1 parlay
   - `BetSlipSheet.submitBets()` loops through items and calls Edge Function once per selection
   - `submit_bet` Edge Function hard-codes `is_parlay: false, parlay_legs: 1`
   - Each bet gets a different `ticket_id` instead of sharing one
   - `BetService.submitBetToServer()` doesn't accept parlay parameters

2. **Per-Item Stakes Not Initialized on Mode Switch** - When parlay mode auto-switches to singles due to conflicts, per-item stakes are empty, causing "No stake set" errors

### Display Issues

3. **Market Type Case Inconsistency** - "SPREAD" in BetSlipSheet vs "spread" in BetDetailView
4. **Sport/League Not Shown in List Views** - Must drill into detail view to see full event context
5. **Event Fallback Shows UUID** - If event not in local cache, displays "Event abc123..." instead of meaningful info

### Data Model Issues

6. **Side Indicator Not Persisted** - Server uses 'a'/'b', local stores "Lakers -3.5" - can't reconstruct without Event lookup
7. **Market Stored as String** - No reference to actual Market record, just "spread"/"total"/"moneyline"

## User Stories

### Phase 1: Fix Parlay Submission (Critical)

#### US-001: Create Parlay Submission Endpoint
**Description:** As a player, I want my parlay bets to be created correctly so that I get the combined odds benefit.

**Acceptance Criteria:**
- [ ] Create new `submit_parlay` Edge Function that accepts array of legs
- [ ] Function creates one bet record per leg, all sharing the same `ticket_id`
- [ ] All legs have `is_parlay: true` and `parlay_legs: N` set correctly
- [ ] Function validates all legs can be parlayed (no conflicts, all events open)
- [ ] Returns combined odds calculation for verification
- [ ] Idempotency key prevents duplicate submissions
- [ ] Typecheck passes

#### US-002: Update BetSlipSheet Parlay Submission
**Description:** As a player, I want the bet slip to call the parlay endpoint when I'm in parlay mode.

**Acceptance Criteria:**
- [ ] When `betMode == .parlay`, call `submit_parlay` endpoint with all items
- [ ] When `betMode == .singles`, keep existing per-bet submission
- [ ] Single network call for entire parlay (not N calls)
- [ ] Pass combined odds from client for server validation
- [ ] Handle partial failures gracefully (all-or-nothing for parlays)
- [ ] Typecheck passes

#### US-003: Update BetService for Parlay Support
**Description:** As a developer, I need BetService to support parlay submission parameters.

**Acceptance Criteria:**
- [ ] Add `submitParlayToServer()` function accepting array of selections
- [ ] Add `SubmitParlayRequest` struct with legs array, stake, combined odds
- [ ] Add `SubmitParlayResponse` struct returning all created bets
- [ ] Create local Bet objects with correct `isParlay` and `parlayLegs` values
- [ ] All legs share the same `ticketId` locally
- [ ] Typecheck passes

#### US-004: Fix Per-Item Stakes on Mode Switch
**Description:** As a player, I want my stakes to be preserved when the bet slip switches from parlay to singles mode.

**Acceptance Criteria:**
- [ ] When switching from parlay to singles due to conflicts, initialize per-item stakes
- [ ] Default each item's stake to the current shared stake divided by item count, or zero
- [ ] Show user a message explaining the mode switch
- [ ] Typecheck passes

### Phase 2: Improve Bet Display

#### US-005: Standardize Market Type Display
**Description:** As a user, I want market types displayed consistently across all views.

**Acceptance Criteria:**
- [ ] Create `MarketType.displayName` computed property returning "Spread", "Total", "Moneyline" (title case)
- [ ] Update BetSlipSheet to use `displayName` instead of hardcoded uppercase
- [ ] Update BetDetailView to use `displayName` instead of raw `bet.market` string
- [ ] Update BetsListView to show market type badge
- [ ] Typecheck passes

#### US-006: Show Sport/League in Bet List Views
**Description:** As a bookie, I want to see the sport and league for each bet without drilling into details.

**Acceptance Criteria:**
- [ ] BetsListView shows sport icon or abbreviation (e.g., "NBA", "NFL")
- [ ] Event row shows "Sport | Away @ Home" format
- [ ] Use compact display that doesn't overwhelm the list
- [ ] Typecheck passes

#### US-007: Improve Event Fallback Display
**Description:** As a user, I want to see meaningful bet information even if the event is not in my local cache.

**Acceptance Criteria:**
- [ ] Store `eventDescription` on Bet model (e.g., "Lakers @ Celtics")
- [ ] Store `sportLeague` on Bet model (e.g., "NBA")
- [ ] Use stored description as fallback when Event not found
- [ ] Migration to populate existing bets from Events where possible
- [ ] Typecheck passes

#### US-008: Add Market Details to Bet Display
**Description:** As a user, I want to see the full market details (spread size, total number) in the bet list.

**Acceptance Criteria:**
- [ ] BetsListView shows full side string (e.g., "Lakers -6.5" not just "Lakers")
- [ ] For totals, show "Over 215.5" or "Under 215.5" clearly
- [ ] For moneyline, show team name
- [ ] Consistent formatting across player and bookie views
- [ ] Typecheck passes

### Phase 3: Data Model Improvements

#### US-009: Store Side Indicator on Bet
**Description:** As a developer, I need to store the server-side indicator ('a'/'b') for potential re-submission or audit.

**Acceptance Criteria:**
- [ ] Add `sideIndicator: String` field to Bet model ('a' or 'b')
- [ ] Populate from BetSlipItem.sideIndicator during bet creation
- [ ] Include in sync upload payload
- [ ] Migration adds nullable column
- [ ] Typecheck passes

#### US-010: Store Market ID Reference on Bet
**Description:** As a developer, I need to reference the actual Market record for accurate lookups.

**Acceptance Criteria:**
- [ ] Add `marketId: UUID?` field to Bet model
- [ ] Populate from BetSlipItem.marketId during bet creation
- [ ] Can look up Market to get current odds, status
- [ ] Migration adds nullable column
- [ ] Typecheck passes

### Phase 4: Edge Case Handling

#### US-011: Validate Parlay Leg Compatibility
**Description:** As a player, I want clear feedback when my parlay selections are incompatible.

**Acceptance Criteria:**
- [ ] Detect same-game parlay attempts (multiple markets from same event)
- [ ] Show warning but allow same-game parlays (some sportsbooks allow this)
- [ ] Detect opposite-side selections (home spread + away ML = indirect conflict)
- [ ] Show exposure warning for indirect conflicts
- [ ] Typecheck passes

#### US-012: Handle Locked Events During Submission
**Description:** As a player, I want clear feedback if an event locks while I'm placing a bet.

**Acceptance Criteria:**
- [ ] Server validates event lock status for all legs
- [ ] If any leg's event is locked, reject entire parlay
- [ ] Return which specific events were locked
- [ ] Client shows clear error message identifying locked events
- [ ] Offer to remove locked events and resubmit remaining
- [ ] Typecheck passes

#### US-013: Handle Odds Changes During Submission
**Description:** As a player, I want to know if odds changed significantly while I was placing my bet.

**Acceptance Criteria:**
- [ ] Server compares submitted odds to current odds
- [ ] If odds moved against player by more than threshold (e.g., 10 points), reject
- [ ] Return current odds in error response
- [ ] Client shows "Odds have changed" message with option to accept new odds
- [ ] Typecheck passes

### Phase 5: Polish & Performance

#### US-014: Optimistic UI for Bet Submission
**Description:** As a player, I want immediate feedback when I submit a bet.

**Acceptance Criteria:**
- [ ] Show bet as "Submitting..." in bet history immediately
- [ ] Update to "Pending" or "Accepted" when server confirms
- [ ] Rollback and show error if submission fails
- [ ] Smooth animations for state transitions
- [ ] Typecheck passes

#### US-015: Bet Slip Submission Loading State
**Description:** As a player, I want clear visual feedback during bet submission.

**Acceptance Criteria:**
- [ ] Disable all inputs during submission
- [ ] Show progress indicator on submit button
- [ ] For parlays, show "Submitting parlay..." not just "Submitting..."
- [ ] For singles with multiple bets, show "Submitting 1 of 3..."
- [ ] Typecheck passes

## Functional Requirements

- FR-1: Parlay bets MUST be created with correct `is_parlay`, `parlay_legs`, and shared `ticket_id`
- FR-2: Singles bets MUST be created with `is_parlay: false` and unique `ticket_id` per bet
- FR-3: All bet display MUST show sport, market type, and full side description
- FR-4: Market types MUST be displayed in title case: "Spread", "Total", "Moneyline"
- FR-5: Event information MUST be stored on Bet for offline/deleted event scenarios
- FR-6: Parlay submission MUST be atomic - all legs succeed or all fail
- FR-7: Odds validation MUST occur server-side before bet creation
- FR-8: Event lock validation MUST occur server-side before bet creation

## Non-Goals

- Real-time odds streaming (use current manual refresh)
- Same-game parlay builder UI (allow but don't optimize for)
- Teaser/pleaser bet types
- Round robin parlays
- Cash out functionality

## Technical Considerations

- New `submit_parlay` Edge Function needed alongside existing `submit_bet`
- Bet model needs 2 new optional fields: `sideIndicator`, `marketId`
- SwiftData migration required for new fields
- Consider batch insert on server for parlay legs (single transaction)

## Success Metrics

- 0 parlay bets created with `is_parlay: false`
- All bets display event name (no UUID fallbacks)
- Bet submission success rate > 99%
- Average submission time < 2 seconds

## Open Questions

1. Should we allow same-game parlays? (Current: allowed but no special handling)
2. What odds movement threshold should reject bets? (Suggested: 10 points)
3. Should we show combined parlay odds in bet history? (Currently calculated dynamically)
