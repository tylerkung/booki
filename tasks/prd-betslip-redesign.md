# PRD: Bet Slip Redesign

## Introduction

Redesign the bet slip component to match industry standards (DraftKings, FanDuel, Caesars) with improved UX, better information hierarchy, and bidirectional stake/payout entry. Users should be able to enter either the wager amount OR the desired winnings, with automatic calculation of the other value.

## Goals

- Match industry-standard bet slip UX patterns
- Enable bidirectional stake entry (Wager ↔ To Win)
- Add quick stake buttons for faster entry
- Show game date/time for context
- Improve visual hierarchy and information density
- Reduce friction in the betting flow

## User Stories

### US-001: Bidirectional stake entry - Wager calculates To Win
**Description:** As a player, I want to enter my wager amount and see the potential winnings automatically calculated.

**Acceptance Criteria:**
- [ ] Stake input field labeled "WAGER" with "$" prefix
- [ ] "TO WIN" field displays calculated payout based on odds
- [ ] Calculation: For +odds: toWin = wager × (odds/100). For -odds: toWin = wager × (100/|odds|)
- [ ] Updates in real-time as user types
- [ ] Wager field has visual focus state (highlighted border)
- [ ] Typecheck passes

### US-002: Bidirectional stake entry - To Win calculates Wager
**Description:** As a player, I want to enter my desired winnings and have the required stake calculated automatically.

**Acceptance Criteria:**
- [ ] "TO WIN" field is editable (not just display)
- [ ] Entering a To Win amount calculates the required wager
- [ ] Calculation: For +odds: wager = toWin / (odds/100). For -odds: wager = toWin / (100/|odds|)
- [ ] Updates in real-time as user types
- [ ] Visual indicator showing which field is being edited (active field)
- [ ] Clearing one field clears the other
- [ ] Typecheck passes

### US-003: Add quick stake buttons
**Description:** As a player, I want quick stake buttons so I can rapidly set common bet amounts without typing.

**Acceptance Criteria:**
- [ ] Row of quick stake buttons: +$5, +$10, +$25, +$50
- [ ] Tapping adds to current wager (not replaces)
- [ ] Buttons styled as pills with border, consistent with competitors
- [ ] Buttons update both Wager and To Win fields
- [ ] Works in both Singles and Parlay modes
- [ ] Typecheck passes
- [ ] Verify in simulator

### US-004: Show game date/time on bet cards
**Description:** As a player, I want to see when each game starts so I know the betting deadline.

**Acceptance Criteria:**
- [ ] Display game start time on each bet card (e.g., "Thu 7:10 PM")
- [ ] Format: Day abbreviation + time (e.g., "Sun 1:00 PM", "Mon 8:30 PM")
- [ ] Position below event matchup text
- [ ] Use Theme.textMuted for subtle appearance
- [ ] Typecheck passes

### US-005: Redesign bet card layout
**Description:** As a player, I want a cleaner bet card that shows all relevant information in a scannable format.

**Acceptance Criteria:**
- [ ] Remove team abbreviation circles (BU, PH, TO)
- [ ] Layout: Selection name (bold) → Event matchup → Game time
- [ ] Odds badge on right side (keep current styling)
- [ ] Remove button (X) more prominent
- [ ] Market type label (SPREAD, MONEYLINE, TOTAL) positioned clearly
- [ ] Typecheck passes
- [ ] Verify in simulator

### US-006: Inline Wager/To Win fields on bet cards (Singles mode)
**Description:** As a player in singles mode, I want side-by-side Wager and To Win fields on each bet card.

**Acceptance Criteria:**
- [ ] Two input fields per bet card: "WAGER" and "TO WIN"
- [ ] Fields are side-by-side (not stacked)
- [ ] Both fields support bidirectional entry (US-001, US-002)
- [ ] Active field has highlighted border
- [ ] Inactive field shows calculated value in muted style
- [ ] Typecheck passes
- [ ] Verify in simulator

### US-007: Add section headers
**Description:** As a player, I want clear section headers so I understand the bet slip structure.

**Acceptance Criteria:**
- [ ] "STRAIGHT BETS" header in Singles mode (with info icon optional)
- [ ] "X-LEG PARLAY" header in Parlay mode
- [ ] Headers use Theme.textMuted, uppercase, tracking
- [ ] Collapsible sections (optional, nice-to-have)
- [ ] Typecheck passes

### US-008: Parlay stake entry with Wager/To Win
**Description:** As a player betting a parlay, I want to enter either my wager or desired winnings.

**Acceptance Criteria:**
- [ ] Parlay section shows combined odds prominently
- [ ] Side-by-side Wager/To Win fields below odds
- [ ] Bidirectional calculation using combined parlay odds
- [ ] Quick stake buttons work for parlay
- [ ] Typecheck passes
- [ ] Verify in simulator

### US-009: Improve summary section
**Description:** As a player, I want a clear summary showing my total stake and potential payout before placing the bet.

**Acceptance Criteria:**
- [ ] Summary section at bottom (sticky)
- [ ] Shows: Total Stake, Number of Bets, Total Potential Payout
- [ ] In singles mode: sum of individual bet stakes and payouts
- [ ] In parlay mode: single stake and parlay payout
- [ ] Potential Payout highlighted in accent color
- [ ] Typecheck passes

### US-010: Visual polish and animations
**Description:** As a player, I want smooth animations and visual feedback when interacting with the bet slip.

**Acceptance Criteria:**
- [ ] Quick stake buttons have tap animation (scale down on press)
- [ ] Field focus transitions are smooth
- [ ] Wager/To Win value changes animate smoothly
- [ ] Use spring animations consistent with app patterns
- [ ] Typecheck passes

## Functional Requirements

- FR-1: Entering a value in WAGER field calculates TO WIN using the bet's odds
- FR-2: Entering a value in TO WIN field calculates WAGER using the bet's odds
- FR-3: Only one field can be "active" (being edited) at a time
- FR-4: Quick stake buttons increment the wager amount (additive)
- FR-5: Game times must be fetched from Event.startTime
- FR-6: All calculations must handle both positive and negative American odds
- FR-7: Stake validation against available credit must work with bidirectional entry

## Non-Goals (Out of Scope)

- Custom numeric keypad (future enhancement)
- Cash Out functionality
- Teasers/Multiples bet types
- Odds movement alerts
- Bet card reordering/drag-drop

## Technical Considerations

### Odds Calculation Formulas

**American Odds to Decimal:**
- Positive odds: decimal = (odds / 100) + 1
- Negative odds: decimal = (100 / |odds|) + 1

**Wager to To Win:**
- toWin = wager × (decimalOdds - 1)

**To Win to Wager:**
- wager = toWin / (decimalOdds - 1)

### State Management
- Track which field is "active" (wager vs toWin) per bet
- Store raw numeric values, format for display
- Use Decimal for precision in calculations

### Existing Code References
- `BetSlipSheet.swift` - Main bet slip component
- `BetSlipManager.swift` - State management
- `PremiumBetSlipItemCard` - Individual bet card component
- Calculation helpers already exist in `BetSlipManager.calculatePayout()`

## Design Considerations

### Layout Reference (FanDuel-style)
```
┌─────────────────────────────────────┐
│ Selection Name              -112    │
│ SPREAD BETTING                      │
│ Event @ Event          Thu 7:10PM   │
├─────────────────────────────────────┤
│  WAGER          │    TO WIN         │
│  $ [25.00]      │    $ 22.32        │
├─────────────────────────────────────┤
│  +$5   +$10   +$25   +$50          │
└─────────────────────────────────────┘
```

### Quick Stake Button Styling
- Pill shape with border
- Theme.cardBackground background
- Theme.textSecondary text
- On tap: brief scale animation
- Additive behavior (tapping +$5 twice = $10)

## Success Metrics

- Faster bet placement (fewer taps to enter stake)
- Reduced user confusion about potential winnings
- Visual parity with major sportsbook apps
- No increase in bet submission errors

## Open Questions

- Should quick stake buttons be configurable by user?
- Should we show "max bet" based on available credit?
- Add "Same for all" button to apply stake to all singles?
