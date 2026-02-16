# PRD: Data Consistency & Financial Calculation Bug Fixes

## Introduction

This PRD addresses critical and medium-severity bugs that affect data consistency, financial calculations, and app stability. The focus is on issues that could lead to incorrect balance/payout calculations, app crashes, or silent data corruption. These fixes ensure the reliability of the core betting and settlement functionality.

## Goals

- Fix bugs that could cause incorrect parlay payout calculations
- Fix parlay stake display to show correct totals (not sum of all legs)
- Fix player login incorrectly assigning bookie role
- Prevent app crashes from force-unwrapped optionals
- Ensure data consistency during sync operations
- Validate player relationships to prevent orphaned bets affecting balances
- Improve thread safety in critical services

## User Stories

### US-001: Fix Parlay Stake Assumption Bug
**Description:** As a bookie, I need parlay payout calculations to be robust so that payouts are always correct even when edge cases occur.

**File:** `Booki/Services/ParlayGradingService.swift` (lines 101, 108)

**Acceptance Criteria:**
- [ ] Add guard check to ensure `bets` array is not empty before accessing `bets.first`
- [ ] Return appropriate fallback (`.zero` or error) when bets array is empty
- [ ] Add inline comment documenting single-stake parlay assumption
- [ ] Typecheck passes

---

### US-002: Fix Force-Unwrapped URLs in OddsAPIService
**Description:** As a user, I need the app to handle invalid API keys gracefully so the app doesn't crash when URL construction fails.

**File:** `Booki/Services/OddsAPIService.swift` (lines 97, 128, 167)

**Acceptance Criteria:**
- [ ] Replace force-unwrapped `URL(string:)!` with safe URL construction
- [ ] Add URL encoding for the API key parameter using `addingPercentEncoding(withAllowedCharacters:)`
- [ ] Throw `OddsAPIError.networkError` or appropriate error when URL construction fails
- [ ] All three URL constructions (sports list, odds, scores) are fixed
- [ ] Typecheck passes

---

### US-003: Fix WeeklySettlementView Date Calculation Crash
**Description:** As a bookie, I need the weekly settlement view to load reliably without crashing due to date calculations.

**File:** `Booki/Views/WeeklySettlementView.swift` (line 256)

**Acceptance Criteria:**
- [ ] Replace force-unwrapped date calculation with safe unwrapping using `guard let`
- [ ] Provide sensible fallback (use `today` as fallback) if date calculation fails
- [ ] Typecheck passes

---

### US-004: Add Player Relationship Validation in Bet Creation
**Description:** As a bookie, I need all bets to have valid player relationships so that settlement always creates correct ledger entries and balance calculations.

**File:** `Booki/Services/GradingService.swift` (around line 73-74)

**Acceptance Criteria:**
- [ ] Add early validation in bet settlement to log warning when player relationship is missing
- [ ] Ensure orphaned bets (no player) are flagged in settlement result rather than silently skipping
- [ ] Review `BetService` to ensure player is always set during bet creation
- [ ] Typecheck passes

---

### US-005: Handle Missing Player in RealtimeService Bet Sync
**Description:** As a user, I need bet sync to handle race conditions gracefully so that bets are not silently dropped when they arrive before their player record.

**File:** `Booki/Services/RealtimeService.swift` (lines 410-414)

**Acceptance Criteria:**
- [ ] Add logging when a bet update arrives but the associated player is not found locally
- [ ] Ensure the bet record is still created/updated (with nil player) so it can be fixed on next full sync
- [ ] Mark such bets with `needsSync = true` so they get re-processed
- [ ] Typecheck passes

---

### US-006: Add Empty Bet Array Validation in TicketDetailView
**Description:** As a user, I need ticket details to display correctly even if edge cases create empty tickets.

**Files:**
- `Booki/Views/TicketDetailView.swift` (lines 209, 642)
- `Booki/Views/TrackView.swift` (line 74)

**Acceptance Criteria:**
- [ ] Add guard checks before accessing `bets.first?.stake`
- [ ] Display "No bets" or appropriate fallback UI when bet array is empty
- [ ] Prevent showing misleading $0.00 stake for corrupted data
- [ ] Typecheck passes

---

### US-007: Add Silent Failure Logging in AuthManager
**Description:** As a developer, I need to know when player ID conversion fails so authentication issues can be diagnosed.

**File:** `Booki/Services/AuthManager.swift` (lines 101-108)

**Acceptance Criteria:**
- [ ] Add logging (print or os_log) when `UUID(uuidString:)` conversion fails
- [ ] Include the invalid `userId` value in the log for debugging
- [ ] Keep existing behavior (silent failure) but make it observable
- [ ] Typecheck passes

---

### US-008: Make BetSlipManager Thread-Safe
**Description:** As a user, I need the bet slip to work reliably without crashes when updates come from different threads.

**File:** `Booki/Services/BetSlipManager.swift`

**Acceptance Criteria:**
- [ ] Add `@MainActor` annotation to `BetSlipManager` class
- [ ] Verify all `@Published` property updates happen on main thread
- [ ] Ensure all public methods are called from main actor context
- [ ] Typecheck passes

---

### US-009: Add Odds Validation in LiabilityService
**Description:** As a bookie, I need liability calculations to handle invalid odds gracefully so payouts are never calculated with bad data.

**File:** `Booki/Services/LiabilityService.swift` (lines 12-21)

**Acceptance Criteria:**
- [ ] Add validation that odds are non-zero
- [ ] Add validation for reasonable odds range (e.g., American odds typically -10000 to +10000)
- [ ] Return zero or throw error for invalid odds rather than calculating incorrect values
- [ ] Typecheck passes

---

### US-010: Fix Parlay Stake Display Bug
**Description:** As a player, I need parlay stakes to display correctly so that a 2-leg $25 parlay shows as $25 total, not $50.

**Background:** When creating a parlay, the full stake is stored on each leg (by design - this allows grading to work correctly when legs are voided). However, display logic incorrectly sums all leg stakes instead of treating them as one shared stake.

**Files:**
- `Booki/Views/TrackView.swift` (line 16) - `Ticket.totalStake` computed property
- `Booki/Views/AccountView.swift` (line 143) - `totalStaked` computed property for ROI calculation

**Acceptance Criteria:**
- [ ] Fix `Ticket.totalStake` in TrackView.swift to return `bets.first?.stake` when `isParlay` is true
- [ ] Fix `totalStaked` in AccountView.swift to correctly calculate stake totals by grouping bets by `ticketId` and using first bet's stake for parlays
- [ ] Verify parlay stake displays correctly in Track view (e.g., 2-leg $25 parlay shows $25)
- [ ] Verify ROI calculations in Account view are correct for players with parlays
- [ ] Existing singles behavior unchanged (stakes still sum correctly)
- [ ] Typecheck passes

**Technical Notes:**
- The grading logic (`ParlayGradingService`) already correctly uses `bets.first?.stake` - this is display-only
- The `potentialPayout` calculation in `Ticket` (line 74) already handles this correctly - use same pattern
- For AccountView, group `settledBets` by `ticketId`, then for each group use `first?.stake` if `isParlay`

---

### US-011: Fix Player Login Creating Bookie Record
**Description:** As a player, I need to log in and be recognized as a player, not incorrectly assigned as a bookie.

**Background:** When any user logs in, `ensureBookieRecord()` is called which attempts to fetch a bookie record, and if not found, CREATES one via `fetchOrCreateBookie()`. This means players who log in get a bookie record created for them and are incorrectly assigned the bookie role.

**Files:**
- `Booki/Services/AuthManager.swift` (lines 75-112) - `ensureBookieRecord()` method
- `Booki/Services/BookieService.swift` (lines 169-181) - `fetchOrCreateBookie()` method

**Acceptance Criteria:**
- [ ] Modify `ensureBookieRecord()` to check if user is a player BEFORE attempting to create a bookie record
- [ ] Add a method to check if a player record exists for the current auth user ID (query players table by `authUserId`)
- [ ] Update role determination logic:
  1. Try to fetch existing bookie record → if found, set as bookie
  2. Try to fetch existing player record → if found, set as player
  3. Only create bookie record if explicitly signing up as bookie (not on general login)
- [ ] Consider adding a `isBookieSignup` parameter to `ensureBookieRecord()` to distinguish signup from login
- [ ] Verify: player can log in and sees player UI
- [ ] Verify: bookie can log in and sees bookie UI
- [ ] Verify: new bookie signup still creates bookie record correctly
- [ ] Typecheck passes

**Technical Notes:**
- Need to query Supabase `players` table for `auth_user_id` match
- May need a new `PlayerService.fetchCurrentPlayer()` method similar to `BookieService.fetchCurrentBookie()`
- The auth listener's `signedIn` case should call a role-determination method, not a bookie-creation method
- Consider renaming `ensureBookieRecord()` to `determineUserRole()` to clarify intent

## Functional Requirements

- FR-1: All optional unwrapping must use safe patterns (`guard let`, `if let`, or nil coalescing with appropriate fallback)
- FR-2: Financial calculations (parlay payouts, liability) must validate inputs before calculating
- FR-3: Sync operations must handle missing relationships gracefully without silent data loss
- FR-4: UI must handle empty or corrupted data states without showing misleading values
- FR-5: Thread-sensitive classes must be properly annotated for main actor execution
- FR-6: Parlay stake display must use single stake value (from first leg), not sum of all leg stakes
- FR-7: User role determination must check for existing player record before creating bookie record

## Non-Goals

- No new features or UI changes beyond fixing display of edge cases
- No refactoring of architecture or data models
- No adding unit tests (separate effort)
- No changes to debug print statements
- No performance optimizations

## Technical Considerations

- All fixes should be minimal and surgical - change only what's necessary
- Maintain backward compatibility with existing data
- Use Swift's built-in safety features (guard, if-let, nil coalescing)
- For `@MainActor`, ensure no deadlocks by checking call sites

## Success Metrics

- Zero crashes from force-unwrapped optionals in fixed code paths
- All parlay calculations produce correct results with edge case inputs
- Sync operations log warnings instead of silently dropping data
- Players log in and see player UI; bookies log in and see bookie UI
- No regressions in existing functionality

## Open Questions

- Should we add a data integrity check on app launch to detect and report orphaned bets?
- Should invalid odds throw an error or silently return zero payout?
