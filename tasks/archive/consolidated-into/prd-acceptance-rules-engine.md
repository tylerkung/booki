# PRD: Bookie Acceptance Rules Engine & Event Locking

## Introduction

Add configurable auto-acceptance policies for bets and event locking rules to give bookies control without requiring constant monitoring. Bets that meet policy criteria are auto-accepted; others are queued for manual review with clear reasons displayed.

## Goals

- Allow bookies to configure auto-accept thresholds and rules
- Automatically accept bets that meet all policy criteria
- Queue bets requiring manual review with clear policy violation reasons
- Prevent late bets with configurable event lock times
- Display lock status clearly to players
- Handle edge cases like postponed/canceled events

## User Stories

### US-001: Create AcceptancePolicy Model
**Description:** As a developer, I need a model to store bookie's acceptance policy configuration.

**Acceptance Criteria:**
- [ ] Create AcceptancePolicy.swift in Booki/Models/
- [ ] Model is a SwiftData @Model class associated with Bookie
- [ ] Fields for stake thresholds:
  - `autoAcceptMaxStake: Decimal` (default 100) - auto-accept up to this stake
  - `requireReviewAboveStake: Decimal` (default 500) - always review above this
- [ ] Fields for player rules:
  - `autoAcceptNewPlayers: Bool` (default false) - whether to auto-accept from new players
  - `newPlayerBetThreshold: Int` (default 5) - player needs X bets before considered "established"
- [ ] Fields for bet type rules:
  - `autoAcceptParlays: Bool` (default false) - whether to auto-accept parlays
  - `parlayMaxLegs: Int` (default 4) - max legs for auto-accept if enabled
- [ ] Field for event lock:
  - `eventLockOffsetMinutes: Int` (default 0) - lock X minutes before start (0 = at start time)
- [ ] Project builds and runs in Simulator

### US-002: Create Acceptance Policy Settings UI
**Description:** As a bookie, I want to configure my acceptance rules in Settings.

**Acceptance Criteria:**
- [ ] Add "Acceptance Rules" section to SettingsView.swift
- [ ] Navigation to new AcceptancePolicySettingsView
- [ ] UI includes:
  - Stake thresholds section with text inputs for autoAcceptMaxStake and requireReviewAboveStake
  - Player rules section with toggle for autoAcceptNewPlayers and stepper for newPlayerBetThreshold
  - Parlay rules section with toggle for autoAcceptParlays and stepper for parlayMaxLegs
  - Event lock section with stepper for eventLockOffsetMinutes (0, 1, 2, 5, 10, 15, 30 min options)
- [ ] Changes save automatically (observed model)
- [ ] Use Theme styling consistent with other settings
- [ ] Project builds and runs in Simulator

### US-003: Add Policy Evaluation Logic to BetService
**Description:** As a developer, I need logic to evaluate if a bet should be auto-accepted or queued.

**Acceptance Criteria:**
- [ ] Create AcceptancePolicyService.swift in Booki/Services/
- [ ] Add enum `PolicyViolation` with cases: stakeTooHigh, newPlayer, parlayNotAllowed, parlayTooManyLegs, eventLocked, custom(String)
- [ ] Add function `evaluateBet(bet:player:policy:event:allPlayerBets:) -> [PolicyViolation]`
- [ ] Function checks all policy rules and returns array of violations (empty = auto-accept)
- [ ] Stake check: stake > autoAcceptMaxStake OR stake > requireReviewAboveStake
- [ ] New player check: player's total bet count < newPlayerBetThreshold AND !autoAcceptNewPlayers
- [ ] Parlay check: if bet is part of parlay (check ticketId grouping) AND !autoAcceptParlays
- [ ] Event lock check: event.startTime - lockOffset <= now
- [ ] Project builds and runs in Simulator

### US-004: Add Policy Violation Reason to Bet Model
**Description:** As a developer, I need to store why a bet was queued for review.

**Acceptance Criteria:**
- [ ] Add `policyViolations: [String]` field to Bet model (stored as JSON array or comma-separated)
- [ ] Field is optional/empty for auto-accepted bets
- [ ] Field populated when bet is queued with human-readable reasons
- [ ] Examples: "Stake exceeds $100 auto-accept limit", "New player (2 of 5 required bets)", "Parlay requires manual review"
- [ ] Project builds and runs in Simulator

### US-005: Integrate Policy Evaluation into Bet Submission
**Description:** As a developer, I need to apply policy rules when bets are submitted.

**Acceptance Criteria:**
- [ ] Modify BetService.submitBet to accept optional AcceptancePolicy parameter
- [ ] When policy provided, evaluate bet using AcceptancePolicyService
- [ ] If no violations: set bet status to .accepted (auto-accepted)
- [ ] If violations: set bet status to .pending and store violation reasons
- [ ] If no policy provided: default to .pending (current behavior for backwards compatibility)
- [ ] Update BetSlipSheet to pass policy when submitting
- [ ] Project builds and runs in Simulator

### US-006: Display Policy Violation Reasons in Bets List
**Description:** As a bookie, I want to see why a bet is pending review.

**Acceptance Criteria:**
- [ ] Modify BetsListView (or wherever pending bets are shown) to display policy reasons
- [ ] Show violation reasons as subtitle or expandable section under pending bets
- [ ] Style with Theme.warning color for visibility
- [ ] Format: "Requires review: [reason1], [reason2]"
- [ ] Only show for pending bets with violations
- [ ] Project builds and runs in Simulator

### US-007: Add Event Lock Status to Event Model
**Description:** As a developer, I need to track and compute event lock status.

**Acceptance Criteria:**
- [ ] Add computed property `isLocked(offsetMinutes: Int) -> Bool` to Event model
- [ ] Returns true if current time >= (startTime - offsetMinutes)
- [ ] Add computed property `lockTime(offsetMinutes: Int) -> Date` that returns when event locks
- [ ] Handle edge case: if event status is .live or .final, always return locked
- [ ] Project builds and runs in Simulator

### US-008: Display Lock Status in Player Game Cards
**Description:** As a player, I want to see if an event is locked before trying to bet.

**Acceptance Criteria:**
- [ ] Modify GameCardView to show lock indicator when event is locked
- [ ] Lock indicator: small lock icon or "LOCKED" badge near start time
- [ ] Locked events have muted/disabled appearance on odds buttons
- [ ] Tapping locked odds shows brief message "Event locked for betting"
- [ ] Get lock offset from AcceptancePolicy (need to pass down or use default)
- [ ] Project builds and runs in Simulator

### US-009: Enforce Lock on Bet Submission
**Description:** As a system, I need to prevent bets on locked events.

**Acceptance Criteria:**
- [ ] AcceptancePolicyService.evaluateBet includes event lock check
- [ ] If event is locked, return .eventLocked violation
- [ ] Bet submission with locked event results in immediate rejection (not just queued)
- [ ] Add BetError case for .eventLocked with user-friendly message
- [ ] BetSlipSheet shows error alert if trying to submit locked event bet
- [ ] Project builds and runs in Simulator

### US-010: Handle Postponed and Canceled Events
**Description:** As a bookie, I need proper handling when events are postponed or canceled.

**Acceptance Criteria:**
- [ ] Add EventStatus cases if not present: .postponed, .canceled
- [ ] Postponed events: unlock for betting (new start time TBD), show "POSTPONED" badge
- [ ] Canceled events: lock permanently, show "CANCELED" badge, void any pending/accepted bets
- [ ] Add function to void bets for canceled event in BetService
- [ ] When event marked canceled, auto-void associated pending/accepted bets
- [ ] Project builds and runs in Simulator

## Functional Requirements

- FR-1: AcceptancePolicy model stores all configurable thresholds and rules
- FR-2: Bookie can configure policy via Settings UI with immediate save
- FR-3: Bets evaluated against policy on submission
- FR-4: Policy-compliant bets auto-accepted, violations queued as pending
- FR-5: Pending bets show clear violation reasons to bookie
- FR-6: Events lock at configurable offset before start time
- FR-7: Locked events show visual indicator to players
- FR-8: Bets on locked events rejected with clear error
- FR-9: Postponed events unlock, canceled events void pending bets

## Non-Goals

- No server-side enforcement yet (local-first, sync comes later)
- No per-player policy overrides (one policy for all)
- No machine learning or dynamic thresholds
- No notification system for policy violations

## Technical Considerations

- AcceptancePolicy is 1:1 with Bookie (create default on first launch)
- Policy violations stored as strings for flexibility and human readability
- Event lock computed dynamically (not stored) based on current time
- For parlay detection: check if multiple bets share same ticketId in same submission

## Success Metrics

- Bookies can configure policy without code changes
- Low-risk bets auto-accepted without manual intervention
- High-risk bets clearly flagged with actionable reasons
- No bets placed after event start time
- Clear UX for players on locked events
