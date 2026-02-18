# PRD: Player UX Fixes & Login Branding

## Introduction

A collection of UX fixes for the player bet slip experience and a login screen branding update. The bet slip has inconsistencies between singles and parlay modes: singles mode is missing bidirectional to-win entry, and parlay mode uses the system keyboard instead of the custom numeric keypad. The submission success copy implies bets aren't confirmed. The payout summary in the sticky bottom section blocks bet cards when the keypad is open. Additionally, the login screen should match the branded teal launch screen with the Booki logo.

## Goals

- Make singles bet slip cards support bidirectional stake/to-win entry (matching parlay behavior)
- Switch parlay mode from system keyboard to custom numeric keypad (matching singles behavior)
- Update success copy so it feels like a confirmed bet, not a pending request
- Move payout summary out of the sticky bottom section so bets are visible when the keypad is up
- Update login screen to match the teal launch/loading screen branding

## User Stories

### US-001: Bidirectional To-Win Entry on Singles Cards
**Description:** As a player, I want to enter either a wager amount or a desired to-win amount on each singles bet card, so I can work backwards from my desired payout.

**Acceptance Criteria:**
- [ ] Each `PremiumBetSlipItemCard` in singles mode shows side-by-side Wager and To Win fields (matching parlay layout)
- [ ] Tapping the Wager field opens the custom keypad and typing a wager updates the To Win amount
- [ ] Tapping the To Win field opens the custom keypad and typing a to-win amount updates the Wager amount
- [ ] Active field has a glowing border (gold for Wager, cyan for To Win) matching parlay styling
- [ ] Calculations use `BetSlipManager.calculateToWin()` and `calculateWagerFromToWin()` (already exist)
- [ ] `itemToWinTexts` dictionary (already exists at line 44) is used to store per-item to-win text

**Files to modify:**
- `Booki/Views/BetSlipSheet.swift` — `PremiumBetSlipItemCard` (lines 1742-1792), replace the current single tappable stake display + read-only "To Win" label with side-by-side editable Wager/To Win fields

### US-002: Custom Numeric Keypad for Parlay Stake Entry
**Description:** As a player, I want the parlay wager and to-win fields to use the same custom numeric keypad as singles mode, so the experience is consistent.

**Acceptance Criteria:**
- [ ] Parlay Wager and To Win fields are tappable (not system `TextField` with `keyboardType(.numberPad)`)
- [ ] Tapping either field sets `activeFieldId` to `"parlay_wager"` or `"parlay_towin"` and shows the custom `NumericKeypadView` in the sticky bottom section
- [ ] Typing on the keypad updates the active field and recalculates the other field bidirectionally (same logic as current `onChange` handlers)
- [ ] Active field has a glowing border using `.glowingBorder()` modifier
- [ ] Quick stake buttons (+$5, +$10, +$25, +$50) still work
- [ ] Remove `@FocusState` variables `isParlayWagerFocused` and `isParlayToWinFocused` (no longer needed since system keyboard is removed)

**Files to modify:**
- `Booki/Views/BetSlipSheet.swift` — `parlayStakeEntrySection` (lines 733-852), replace `TextField` with tappable `Text` + `onTapGesture` pattern (matching singles cards)

### US-003: Update Submission Success Copy
**Description:** As a player, I want the success screen to confirm my bet was placed, not make it sound like a request that might be denied.

**Acceptance Criteria:**
- [ ] Success screen title changed from "Request Submitted!" to "Bet Placed!"
- [ ] Success screen subtitle changed from "X bet(s) recorded and pending review" to "X bet(s) placed successfully" (or "Your parlay has been placed!" for parlay mode)
- [ ] No other success screen behavior changes

**Files to modify:**
- `Booki/Views/BetSlipSheet.swift` — success view (lines 1144-1153)

### US-004: Move Payout Summary Out of Sticky Bottom
**Description:** As a player, I want to see my bet selections while the keypad is open, instead of having the summary block them.

**Acceptance Criteria:**
- [ ] Remove `payoutSummarySection` and `singlesSummarySection` from `stickyBottomSection`
- [ ] Move the summary inline below the list of bet selections in the scrollable area
- [ ] For parlay mode: summary appears below the parlay stake entry section (after quick stake buttons)
- [ ] For singles mode: summary appears below all `PremiumBetSlipItemCard`s
- [ ] Sticky bottom section only contains: validation warnings (if any), custom keypad (when active), and the Place Bet button
- [ ] Bet selections remain scrollable/visible when keypad is showing

**Files to modify:**
- `Booki/Views/BetSlipSheet.swift` — `stickyBottomSection` (lines 496-575) and the main scrollable body (lines ~400-490)

### US-005: Redesign Numeric Keypad Layout
**Description:** As a player, I want a cleaner keypad layout with quick stake buttons readily accessible, so I can enter amounts faster.

**Acceptance Criteria:**
- [ ] Quick stake buttons (+$5, +$10, +$25, +$50) appear in a row above the keypad, inline with the "Done" button
- [ ] Quick stake buttons show for both singles and parlay modes (not just parlay)
- [ ] Keypad is a 4x3 grid: digits 1-9 in rows 1-3, bottom row is [0, 00, ⌫]
- [ ] Backspace (⌫) moves from its current position to bottom-right of the keypad grid
- [ ] Remove `QuickStakeRow` from `parlayStakeEntrySection` (it moves into the keypad area)

**Files to modify:**
- `Booki/Views/NumericKeypadView.swift` — restructure to 4x3 grid with backspace bottom-right
- `Booki/Views/BetSlipSheet.swift` — move quick stake buttons into sticky bottom section above keypad, show for both modes

### US-006: Branded Login Screen
**Description:** As a player, I want the login screen to match the branded teal launch screen with the Booki logo, so the app feels polished and consistent.

**Acceptance Criteria:**
- [ ] Login screen background uses teal/electric cyan (`Color(hex: 0x00F5D4)`) matching the launch screen and `AuthGateView.loadingView`
- [ ] Booki logo (`BookiLogo` asset) displayed prominently at top, same size as loading screen (200pt width)
- [ ] Form fields (email, password) use dark styling that contrasts against the teal background (e.g., `Theme.background` or `Theme.cardBackground` fill with light text)
- [ ] Login button uses dark background (e.g., `Theme.background`) with light text to contrast the teal
- [ ] "Sign Up" and "Claim Account" links remain visible and accessible
- [ ] Apple Sign-In button remains styled appropriately
- [ ] Remove the existing gradient background (`Theme.backgroundGradient`)
- [ ] Remove the current header icon (sportscourt.fill) — logo replaces it

**Files to modify:**
- `Booki/Views/Auth/LoginView.swift` — update background, header, and field styling

## Functional Requirements

- FR-1: Singles bet cards must have two editable fields (Wager and To Win) with bidirectional calculation via custom keypad
- FR-2: Parlay stake entry must use the custom `NumericKeypadView` instead of the system keyboard, supporting both Wager and To Win fields
- FR-3: All keypad-driven fields must use the `activeFieldId` + `activeKeypadBinding` pattern for consistency
- FR-4: Success screen copy must read "Bet Placed!" and confirm the bet without "request" or "pending review" language
- FR-5: Payout summary section must be in the scrollable area, not the sticky bottom
- FR-6: Sticky bottom section contains only: validation warnings, keypad, and submit button
- FR-7: Numeric keypad is a 4x3 grid (1-9, 0, 00, ⌫) with backspace in bottom-right
- FR-8: Quick stake buttons appear above the keypad inline with "Done", visible for both singles and parlay
- FR-9: Login screen uses teal (#00F5D4) background with BookiLogo asset and dark-styled form fields

## Non-Goals

- No changes to bet submission logic or edge functions
- No changes to parlay/singles calculation math
- No changes to sign-up, forgot password, or player claim screens
- No changes to the launch screen itself (it already looks correct)
- No changes to bookie-facing views

## Technical Considerations

- The bidirectional calculation helpers already exist: `BetSlipManager.calculateToWin()` and `calculateWagerFromToWin()`
- `itemToWinTexts` dictionary already exists in `BetSlipSheet` (line 44) but isn't wired to the singles card UI
- The `activeKeypadBinding` computed property (line ~1481) needs to handle new field IDs for parlay (`"parlay_wager"`, `"parlay_towin"`) and singles to-win fields
- Removing `@FocusState` from parlay means no system keyboard will appear — ensure the custom keypad covers all input needs
- Login screen: `BookiLogo` asset and `Color(hex: 0x00F5D4)` are already used in `AuthGateView.loadingView` — reuse the same values
- Login screen: `AuthTextFieldStyle` may need a variant or override for dark-on-teal styling

## Success Metrics

- Pull-to-refresh sync completes without errors (already fixed)
- Bidirectional entry works in both singles and parlay modes
- Custom keypad is the only input method (no system keyboard appears on bet slip)
- Bets are visible while keypad is open (summary doesn't block them)
- Login screen visually matches the loading screen's teal branding
- Success screen language conveys bet confirmation, not uncertainty

## Resolved Questions

- **Quick stake buttons**: Move above the numpad, inline with the "Done" button. Show for both singles and parlay modes.
- **Singles To Win**: Fully bidirectional — editable via custom keypad, same as parlay.
