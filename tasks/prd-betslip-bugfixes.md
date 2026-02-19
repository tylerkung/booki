# PRD: Bet Slip Bug Fixes & Polish

## Introduction

A set of UX bugs and polish items for the bet slip experience identified during testing. Issues include the Place Bet button causing layout shifts when it appears, the numpad missing decimal support, partial stake submission being allowed in singles mode, the floating bet slip indicator looking like a partially-hidden sheet, and a missing "re-use selections" option on the success screen.

## Goals

- Eliminate layout shifts in the sticky bottom section when entering stakes
- Support decimal/cents entry on the numeric keypad
- Require all singles bets to have stakes before submission
- Make the bet slip indicator feel like a proper floating button, fully hidden when dismissed
- Let players quickly re-use their selections after placing a bet

## User Stories

### US-001: Always show Place Bet button (dimmed when disabled)
**Description:** As a player, I don't want the UI to shift when I start entering a stake — the Place Bet button should always be visible.

**Acceptance Criteria:**
- Remove the `if canSubmit` conditional wrapping `submitSection` in `stickyBottomSection` (around line 567)
- Place Bet button is always rendered in the sticky bottom section
- When `canSubmit` is false: button has 0.4 opacity and is `.disabled(true)`
- When `canSubmit` is true: button has full opacity and is enabled
- No layout shift occurs when typing a stake amount — the keypad, quick stakes, and button remain stable

### US-002: Add decimal key to numeric keypad
**Description:** As a player, I want to enter cents (e.g. $25.50) on my wager.

**Acceptance Criteria:**
- Bottom row of keypad changes from [0, 00, ⌫] to [., 0, ⌫]
- Decimal key (.) inserts a "." into the text
- Only one decimal point allowed — if text already contains ".", the decimal key is a no-op
- Maximum 2 digits after the decimal point (e.g. "25.50" is valid, typing another digit after "25.50" is a no-op)
- Backspace works normally through the decimal point

### US-003: Require all singles stakes before submission
**Description:** As a player, I should not be able to submit if some of my singles bets are missing stakes.

**Acceptance Criteria:**
- In `canSubmit` for singles mode: check that every selection in the bet slip has a stake > 0 (not just that the total is > 0)
- Use `BetSlipManager.getItemStake(marketId:sideIndicator:)` to check each item
- If any item has stake == 0, `canSubmit` returns false and the Place Bet button remains dimmed/disabled
- Parlay mode validation unchanged (only checks total stake > 0)

### US-004: Fix bet slip indicator styling and presentation
**Description:** As a player, I want the bet slip indicator to look like a proper floating button and be fully hidden when the slip is closed.

**Acceptance Criteria:**
- Bet slip indicator in GamesView has rounded corners (`cornerRadius: 16` or `Theme.cornerRadius`)
- Indicator has horizontal margin (16pt padding from edges)
- Indicator has bottom margin to sit above the tab bar (not flush against it)
- Indicator has a shadow for floating effect (`shadow(color:radius:)`)
- When bet slip is empty, indicator is completely hidden (no partial/peeking visibility)
- Same fixes applied to the bet slip indicator in GameDetailView

### US-005: Add "Re-use Selections" CTA on success screen
**Description:** As a player, I want to quickly re-add my same selections after placing a bet, so I can place a follow-up bet (e.g. same picks as a parlay).

**Acceptance Criteria:**
- Text-only button "Re-use selections" appears above the "Done" button on the success screen
- Tapping it saves the current `betSlipManager.items` before clearing, then re-adds them via `betSlipManager.add()`
- After re-adding, dismisses the success overlay and returns to the bet slip with selections restored (stakes reset to 0)
- Button uses `Theme.accent` text color, no background (text-only style)
- `submissionComplete` is set back to false to return to the normal bet slip view
- Item stake texts and to-win texts are cleared (fresh entry for the new bet)

## Functional Requirements

- FR-1: Place Bet button always rendered in sticky bottom, dimmed at 0.4 opacity when disabled
- FR-2: Numeric keypad bottom row is [., 0, ⌫] with decimal validation (max 1 dot, max 2 decimal places)
- FR-3: Singles `canSubmit` requires every item to have stake > 0
- FR-4: Bet slip indicator is a rounded, floating pill with margins and shadow in both GamesView and GameDetailView
- FR-5: Success screen has "Re-use selections" text button above "Done" that restores selections with cleared stakes

## Non-Goals

- No changes to parlay submission validation
- No changes to edge functions or backend
- No changes to bet calculation math
- No changes to the login screen or other views

## Technical Considerations

- The `canSubmit` computed property (line ~821) needs to iterate all `betSlipManager.items` for singles mode
- `BetSlipManager.items` is the array of `BetSlipItem` — save a copy before `removeAll()` on success for re-use
- The decimal key affects `activeKeypadBinding` setter logic — ensure bidirectional calculation handles decimal amounts properly (Decimal(string:) already supports "25.50")
- The bet slip indicator exists in both `GamesView.swift` (line 249) and `GameDetailView.swift` (line 645) — both need the same styling fix
