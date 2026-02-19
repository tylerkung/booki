# PRD: Bet Slip Layout Improvements

## Introduction

Improve the bet slip UX with full-height modal, sticky bottom section for stake/submit, and per-bet stake inputs for singles mode. Remove quick-pick preselection buttons and streamline the layout.

## Goals

- Open bet slip to full modal height for better visibility
- Keep stake entry and submit button always visible in sticky bottom section
- Allow individual stake entry per bet in singles mode
- Remove quick-pick stake buttons to declutter UI
- Show potential payout in sticky section for parlay mode

## User Stories

### US-001: Change Bet Slip to Full Height Modal
**Description:** As a player, I want the bet slip to open to full height so I can see all my selections without scrolling.

**Acceptance Criteria:**
- [ ] Locate where BetSlipSheet presentation detents are configured (likely in GamesView.swift)
- [ ] Change `.presentationDetents([.medium, .large])` to `.presentationDetents([.large])`
- [ ] Bet slip now opens to full modal height (100% of stacked modal)
- [ ] Project builds and runs in Simulator

### US-002: Remove Quick-Pick Stake Buttons
**Description:** As a player, I want a cleaner stake entry without preset amount buttons.

**Acceptance Criteria:**
- [ ] In BetSlipSheet.swift stakeEntrySection, remove the quick-pick buttons HStack
- [ ] Remove PremiumQuickPickButton usage from stakeEntrySection
- [ ] Keep the custom amount input field ($ text field)
- [ ] Stake section now shows only the text input
- [ ] Project builds and runs in Simulator

### US-003: Add Per-Bet Stake Input for Singles Mode
**Description:** As a player betting singles, I want to enter a different stake for each bet individually.

**Acceptance Criteria:**
- [ ] Modify PremiumBetSlipItemCard to include stake input field when in singles mode
- [ ] Add stake text field to each bet card (similar styling to current stake input)
- [ ] Store individual stakes in BetSlipManager (may need to add per-item stake storage)
- [ ] Each bet card shows its own stake input and individual potential payout
- [ ] Stake validation applies per bet (check against available credit)
- [ ] Project builds and runs in Simulator

### US-004: Create Sticky Bottom Section Structure
**Description:** As a developer, I need to restructure the bet slip to have a scrollable top area and sticky bottom section.

**Acceptance Criteria:**
- [ ] Restructure selectionsList to use VStack with ScrollView for bets only
- [ ] Create stickyBottomSection view builder for stake/submit content
- [ ] Use GeometryReader or ZStack to position sticky section at bottom
- [ ] Scrollable area contains: header, mode toggle, bet cards, parlay odds card (if applicable)
- [ ] Sticky section is always visible at bottom regardless of scroll position
- [ ] Add subtle divider (Theme.divider or shadow) between scroll area and sticky section
- [ ] Project builds and runs in Simulator

### US-005: Configure Sticky Section for Parlay Mode
**Description:** As a player betting a parlay, I want to see stake input, potential payout, and submit button in the sticky section.

**Acceptance Criteria:**
- [ ] When betMode == .parlay, sticky section shows:
  - Stake input field (current custom input styling)
  - Potential payout display
  - Place Bet button
- [ ] Stake validation warning appears in sticky section if stake exceeds credit
- [ ] Combined parlay odds card remains in scrollable area above
- [ ] Project builds and runs in Simulator

### US-006: Configure Sticky Section for Singles Mode
**Description:** As a player betting singles, I want only the Place Bet button in the sticky section since stakes are per-bet.

**Acceptance Criteria:**
- [ ] When betMode == .singles, sticky section shows:
  - Total stake summary (sum of individual bet stakes)
  - Total potential payout summary
  - Place Bet button
- [ ] Individual stake inputs are on each bet card in scrollable area (from US-003)
- [ ] canSubmit logic updated to check all individual bet stakes are valid
- [ ] Project builds and runs in Simulator

### US-007: Update Submission Logic for Per-Bet Stakes
**Description:** As a developer, I need to update bet submission to use individual stakes for singles mode.

**Acceptance Criteria:**
- [ ] Modify submitBets() to read individual stakes from bet items in singles mode
- [ ] Parlay mode continues to use single shared stake
- [ ] Each bet submitted with its correct individual stake amount
- [ ] Success/error handling works correctly with new stake structure
- [ ] Project builds and runs in Simulator

## Functional Requirements

- FR-1: Bet slip opens to full modal height (.large detent only)
- FR-2: Quick-pick stake buttons ($10, $25, $50, $100) are removed
- FR-3: Singles mode shows stake input on each bet card
- FR-4: Parlay mode shows single stake input in sticky bottom section
- FR-5: Sticky bottom section always visible with divider separating from scroll area
- FR-6: Place Bet button always visible in sticky section
- FR-7: Potential payout shown in sticky section (total for both modes)

## Non-Goals

- No changes to bet submission API or BetService
- No changes to parlay odds calculation
- No changes to success/error animations
- No new stake validation rules (use existing credit check)

## Technical Considerations

- BetSlipManager may need new property: `itemStakes: [UUID: Decimal]` for per-bet stakes
- Or modify BetSlipItem to include optional stake property
- Use `safeAreaInset(edge: .bottom)` or manual padding for sticky section positioning
- Ensure keyboard doesn't cover stake inputs when editing

## Success Metrics

- Bet slip opens fully without user needing to drag up
- Stake entry is always visible without scrolling
- Singles bets can have different stake amounts
- Cleaner UI without preset stake buttons
