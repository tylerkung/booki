# PRD: Booki v3.0 - Game Card Totals & Layout Update

## Introduction

Update the game card layout to display Totals (Over/Under) as a third column alongside Spread and ML, while removing the "All Markets" toggle. This gives players quick access to the three most common bet types directly on the card. Additional markets will be accessible via the game detail view.

## Goals

- Add Totals column to game cards for quick Over/Under betting
- Streamline card layout by removing the "All Markets" toggle
- Maintain consistent button styling across Spread, ML, and Total columns
- Reduce text sizes slightly to accommodate the third column

## User Stories

### US-001: Remove All Markets Toggle Button
**Description:** As a developer, I want to remove the "All Markets" expand button from game cards so the card is cleaner and additional markets are accessed via the detail view.

**Acceptance Criteria:**
- [ ] Remove `expandButton` view builder from GameCardView.swift
- [ ] Remove `isExpanded` state variable
- [ ] Remove `expandedMarketsSection` view builder
- [ ] Remove the conditional rendering of `expandedMarketsSection` in the body
- [ ] Card now shows only the main betting grid (Spread, ML, Total)
- [ ] Tapping the card still navigates to MarketSelectionView for full market access
- [ ] Project builds and runs in Simulator

### US-002: Add Total Column Header
**Description:** As a player, I want to see a "TOTAL" column header next to ML so I know which column shows Over/Under bets.

**Acceptance Criteria:**
- [ ] Add "TOTAL" header in `teamsWithOddsSection` column headers
- [ ] Header appears after ML column: SPREAD -> ML -> TOTAL
- [ ] Header uses same styling as existing headers (font size 10, bold, textMuted, tracking 0.8)
- [ ] Header only shows if `totalMarket` is available
- [ ] Project builds and runs in Simulator

### US-003: Create TotalButton Component
**Description:** As a player, I want Total buttons styled like Spread buttons with the line as main text and odds as secondary text.

**Acceptance Criteria:**
- [ ] Create new `TotalButton` struct in GameCardView.swift
- [ ] Button displays line value as main text (e.g., "o7.5" for over, "u7.5" for under)
- [ ] Button displays odds as smaller secondary text below the line
- [ ] Use same selected/unselected styling as SpreadButton (gradients, borders, animations)
- [ ] Button is tappable and calls action closure when tapped
- [ ] Project builds and runs in Simulator

### US-004: Add Total Buttons to Team Rows
**Description:** As a player, I want to tap Over or Under directly on the game card to add totals bets to my slip.

**Acceptance Criteria:**
- [ ] Modify `teamOddsRow` to accept `totalMarket` parameter
- [ ] Away team row (top) shows Over button
- [ ] Home team row (bottom) shows Under button
- [ ] TotalButton receives correct line value extracted from market sideA/sideB
- [ ] Tapping Over/Under adds selection to bet slip via `onSelectOdds`
- [ ] Selection state reflects correctly (highlighted when in bet slip)
- [ ] Project builds and runs in Simulator

### US-005: Reduce Button Sizes for Three-Column Layout
**Description:** As a developer, I need to adjust button and text sizes so three columns fit comfortably on screen.

**Acceptance Criteria:**
- [ ] Reduce `oddsButtonSize` from 72 to ~60-64 to fit three columns
- [ ] Reduce main text font size in SpreadButton from 16 to 14
- [ ] Reduce secondary text font size in SpreadButton from 11 to 10
- [ ] Apply same reduced sizes to MLButton (16 -> 14)
- [ ] Apply same sizes to new TotalButton
- [ ] Team name font size reduced from 15 to 14
- [ ] All three columns display without horizontal overflow
- [ ] Project builds and runs in Simulator

### US-006: Extract Total Line Value Helper
**Description:** As a developer, I need a helper function to extract and format the total line from market side labels.

**Acceptance Criteria:**
- [ ] Create `formatTotalValue` function in GameCardView
- [ ] Function extracts numeric value from labels like "Over 220.5" or "Under 220.5"
- [ ] Returns formatted string with prefix: "o220.5" for over, "u220.5" for under
- [ ] Handles edge cases (missing number, unexpected format)
- [ ] Project builds and runs in Simulator

## Functional Requirements

- FR-1: Remove the "All Markets" toggle button and expanded markets section from GameCardView
- FR-2: Display three columns in game cards: Spread, ML, Total (in that order)
- FR-3: Total column shows Over on the away team row (top), Under on the home team row (bottom)
- FR-4: Total buttons display line value as main text (e.g., "o7.5") with odds below
- FR-5: Tapping any odds button (Spread, ML, or Total) adds/removes from bet slip
- FR-6: Button and text sizes reduced proportionally to fit three columns
- FR-7: Tapping anywhere else on the card navigates to MarketSelectionView for all markets

## Non-Goals

- No changes to MarketSelectionView (detail view)
- No changes to bet slip functionality
- No changes to the data model (Market, Event)
- No new market types or betting options
- No changes to existing Theme colors or styling patterns

## Technical Considerations

- Reuse existing SpreadButton styling patterns for TotalButton
- Total market already exists in the model (`Market.type == .total`)
- `totalMarket` computed property already defined in GameCardView
- Keep button component structure consistent (SpreadButton, MLButton, TotalButton)
- Maintain existing animation patterns for selection feedback

## Success Metrics

- Three columns (Spread, ML, Total) display cleanly without overflow
- Players can add Over/Under bets with a single tap from the game card
- Card is visually cleaner without the expand button
- All existing functionality (navigation, bet slip) continues to work

### US-007: Fix Bet Slip Segmented Control Tap Area
**Description:** As a player, I want to tap anywhere on the Singles/Parlay segment to switch modes, not just the text.

**Acceptance Criteria:**
- [ ] Identify the segmented control in BetSlipSheet.swift (or related file)
- [ ] Ensure the entire segment button area is tappable, not just the text label
- [ ] Use `.contentShape(Rectangle())` or similar to expand tap area
- [ ] Both Singles and Parlay segments respond to taps on full button area
- [ ] Project builds and runs in Simulator

### US-008: Remove Redundant Review Screen from Bet Submission
**Description:** As a player, I want to submit my bet directly after entering my stake without an extra review step.

**Acceptance Criteria:**
- [ ] Identify the review/confirmation step in bet submission flow
- [ ] Remove the intermediate review screen
- [ ] User enters stake and taps submit to place bet immediately
- [ ] Confirmation feedback still shows after successful submission
- [ ] Project builds and runs in Simulator

### US-009: Fix Player Balance Display Logic
**Description:** As a player, I want the balance display to show positive when I'm in good standing and negative when I owe money.

**Acceptance Criteria:**
- [ ] Review balance calculation in BalanceService or related files
- [ ] Positive balance = player is in credit (good standing)
- [ ] Negative balance = player owes money to the bookie
- [ ] Update any inverted logic in balance calculations
- [ ] Verify balance colors still apply correctly (green = positive/good, red = negative/debt)
- [ ] Project builds and runs in Simulator

### US-010: Standardize Card Background Colors
**Description:** As a user, I want consistent card background styling across the app using the Account page card color.

**Acceptance Criteria:**
- [ ] Identify the card background color used on Player Account page
- [ ] Apply same background color to Settings tab cards/sections
- [ ] Apply same background color to Bookie dashboard cards
- [ ] Ensure consistent visual appearance across all card elements
- [ ] Project builds and runs in Simulator

## Functional Requirements

- FR-1: Remove the "All Markets" toggle button and expanded markets section from GameCardView
- FR-2: Display three columns in game cards: Spread, ML, Total (in that order)
- FR-3: Total column shows Over on the away team row (top), Under on the home team row (bottom)
- FR-4: Total buttons display line value as main text (e.g., "o7.5") with odds below
- FR-5: Tapping any odds button (Spread, ML, or Total) adds/removes from bet slip
- FR-6: Button and text sizes reduced proportionally to fit three columns
- FR-7: Tapping anywhere else on the card navigates to MarketSelectionView for all markets
- FR-8: Bet slip segmented control (Singles/Parlay) fully tappable on entire button area
- FR-9: Bet submission flow goes directly from stake entry to submission (no review screen)
- FR-10: Player balance shows positive for credit, negative for debt
- FR-11: Card backgrounds use consistent Theme.cardBackground color across Account, Settings, and Bookie dashboard

## Non-Goals

- No changes to MarketSelectionView (detail view)
- No changes to the data model (Market, Event)
- No new market types or betting options
- No changes to existing Theme colors or styling patterns (except applying them consistently)

## Technical Considerations

- Reuse existing SpreadButton styling patterns for TotalButton
- Total market already exists in the model (`Market.type == .total`)
- `totalMarket` computed property already defined in GameCardView
- Keep button component structure consistent (SpreadButton, MLButton, TotalButton)
- Maintain existing animation patterns for selection feedback
- Use `.contentShape()` modifier to expand tap targets on segmented controls

## Success Metrics

- Three columns (Spread, ML, Total) display cleanly without overflow
- Players can add Over/Under bets with a single tap from the game card
- Card is visually cleaner without the expand button
- Bet slip mode switching works with taps anywhere on segment
- Bet submission is streamlined (fewer taps)
- Balance display is intuitive (positive = good)
- Visual consistency across all card elements

## Open Questions

- None - requirements are clear from user specifications
