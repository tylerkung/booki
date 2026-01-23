# PRD: UX Improvements - Header, Bet History & Bet Slip

## Introduction

Streamline the app navigation and information architecture by adding a persistent header with user info and balance, reorganizing tabs, improving how bets are displayed and grouped in the Track tab, and enhancing the bet slip UX with a better layout and sticky stake section.

## Goals

- Provide persistent access to user identity and balance across all tabs
- Reduce redundant UI sections (Your Account, Account Summary)
- Group bets by ticket for clearer bet history organization
- Enable detailed bet viewing with repeat bet action
- Simplify tab structure with logical ordering
- Improve bet slip usability with fuller height and sticky stake/payout section

## User Stories

### US-001: Reorder tabs to Games, Track, Settings
**Description:** As a user, I want the tab bar ordered logically so Games is my home screen and settings are secondary.

**Acceptance Criteria:**
- [ ] Tab order is: Games (1st), Track (2nd), Settings (3rd)
- [ ] Games tab is selected by default on app launch
- [ ] Tab icons and labels remain unchanged
- [ ] Typecheck passes

---

### US-002: Create persistent header component
**Description:** As a user, I want a consistent header across all tabs so I always see my identity and balance.

**Acceptance Criteria:**
- [ ] Header appears on Games, Track, and Settings tabs
- [ ] Header has consistent height and styling across tabs
- [ ] Header uses the app's gamelike theme (gradients, colors)
- [ ] Typecheck passes

---

### US-003: Add user photo and name to header (left side)
**Description:** As a user, I want to see my photo and username in the header so I know I'm logged in.

**Acceptance Criteria:**
- [ ] Left side of header shows user photo (circular, ~32pt)
- [ ] If no photo exists, show initials (first letter of first + last name, or first 2 letters of username)
- [ ] Username displayed next to photo
- [ ] Initials use accent background color with contrasting text
- [ ] Typecheck passes

---

### US-004: Make header user section tappable to Account
**Description:** As a user, I want to tap my photo/name to access my account settings quickly.

**Acceptance Criteria:**
- [ ] Tapping user photo or username navigates to Account page
- [ ] Navigation uses standard push transition
- [ ] Account page has back button to return to previous tab
- [ ] Typecheck passes

---

### US-005: Add balance display to header (right side)
**Description:** As a user, I want to see my current balance at a glance so I know my financial position.

**Acceptance Criteria:**
- [ ] Right side of header shows current balance
- [ ] Balance formatted as currency (e.g., "$1,250.00")
- [ ] Positive balance displayed in accent/green color
- [ ] Negative balance displayed in danger/red color
- [ ] Zero balance displayed in neutral/secondary color
- [ ] Balance is NOT tappable (informational only)
- [ ] Typecheck passes

---

### US-006: Remove "Your Account" section from Games tab
**Description:** As a user, I no longer need the account section on Games since it's now in the header.

**Acceptance Criteria:**
- [ ] "Your Account" section removed from Games/Home view
- [ ] No empty space left where section was removed
- [ ] Games tab layout adjusts properly
- [ ] Typecheck passes

---

### US-007: Remove Account Summary from Track tab
**Description:** As a user, I no longer need the account summary in Track since balance is in the header.

**Acceptance Criteria:**
- [ ] Account summary section removed from Track/My Bets view
- [ ] Bet history section takes full available space
- [ ] No empty space left where section was removed
- [ ] Typecheck passes

---

### US-008: Group bets by ticket in Track tab
**Description:** As a user, I want my bets grouped by ticket so I can see related bets together (e.g., 3 singles placed at once, or a 3-leg parlay).

**Acceptance Criteria:**
- [ ] Bets are grouped by ticket/transaction ID
- [ ] Each ticket displays as a summary card showing:
  - Ticket type (Single, Parlay, etc.)
  - Number of legs (e.g., "3 Legs")
  - Total stake
  - Potential/actual payout
  - Overall status (Pending, Won, Lost, Partial)
- [ ] Cards are sorted by date (newest first)
- [ ] Typecheck passes

---

### US-009: Create bet detail page
**Description:** As a user, I want to tap a bet ticket to see full details so I can review all information about that bet.

**Acceptance Criteria:**
- [ ] Tapping a ticket card navigates to detail page
- [ ] Detail page shows:
  - All legs with team names, odds, and individual status
  - Total stake and potential/actual payout
  - Bet placed timestamp
  - Result timestamp (if settled)
  - Result breakdown (which legs won/lost)
- [ ] Back button returns to Track tab
- [ ] Typecheck passes

---

### US-010: Add repeat bet action to bet detail page
**Description:** As a user, I want to quickly place the same bet again so I can repeat winning strategies.

**Acceptance Criteria:**
- [ ] "Repeat Bet" button visible on bet detail page
- [ ] Button only enabled if all events in the bet are still available
- [ ] Tapping adds the same selections to bet slip
- [ ] User is navigated to Games tab with bet slip open
- [ ] If events unavailable, button is disabled with explanation
- [ ] Typecheck passes

---

### US-011: Remove "All Markets" expand button from game cards
**Description:** As a user, I don't need the expand button since all key markets will be visible by default.

**Acceptance Criteria:**
- [ ] "All Markets" / "Show Less" button removed from game cards
- [ ] Expanded markets section removed
- [ ] Card height adjusts appropriately
- [ ] Typecheck passes

---

### US-012: Add Total column to game card odds grid
**Description:** As a user, I want to see spread, moneyline, AND totals at a glance without expanding.

**Acceptance Criteria:**
- [ ] Three columns displayed: SPREAD | ML | TOTAL (left to right)
- [ ] Total column shows Over on away team row, Under on home team row
- [ ] Column headers updated to show "SPREAD", "ML", "TOTAL"
- [ ] All three columns have equal width boxes
- [ ] Typecheck passes

---

### US-013: Style Total buttons like Spread buttons
**Description:** As a user, I want consistent button styling where the total value is prominent.

**Acceptance Criteria:**
- [ ] Total button main text shows value (e.g., "O 7.5" or "U 7.5")
- [ ] Total button secondary text shows odds (e.g., "-110")
- [ ] Styling matches SpreadButton component (large main text, small secondary)
- [ ] "O" prefix for over, "U" prefix for under
- [ ] Typecheck passes

---

### US-014: Reduce odds button text size for three-column layout
**Description:** As a user, I need the buttons to fit three across while remaining readable.

**Acceptance Criteria:**
- [ ] Button width reduced to fit 3 columns (e.g., ~64pt instead of 72pt)
- [ ] Main text size reduced slightly (e.g., 14pt instead of 16pt)
- [ ] Secondary text size adjusted proportionally (e.g., 10pt instead of 11pt)
- [ ] Team name text can truncate if needed
- [ ] All text remains readable
- [ ] Typecheck passes

---

### US-015: Expand bet slip to fuller height
**Description:** As a user, I want the bet slip to open taller so I can see more of my selections without scrolling.

**Acceptance Criteria:**
- [ ] Bet slip slides open to ~85-90% of screen height (instead of ~50%)
- [ ] Maintains smooth slide animation
- [ ] Can still be dismissed by swiping down or tapping outside
- [ ] Typecheck passes

---

### US-016: Create sticky stake/payout section at bottom of bet slip
**Description:** As a user, I want the stake input and payout always visible so I can adjust my bet without scrolling.

**Acceptance Criteria:**
- [ ] Stake input section is fixed/sticky at bottom of bet slip
- [ ] Potential payout displayed in the sticky section (next to or below stake)
- [ ] Sticky section has clear visual separation from scrollable area (border or shadow)
- [ ] Sticky section remains visible regardless of scroll position
- [ ] Typecheck passes

---

### US-017: Remove bet preselections from bet slip
**Description:** As a user, I don't need preset stake buttons cluttering the bet slip.

**Acceptance Criteria:**
- [ ] Preset stake buttons (e.g., "$10", "$25", "$50", "$100") are removed
- [ ] Only the manual stake input field remains
- [ ] Layout adjusts to use freed space appropriately
- [ ] Typecheck passes

---

### US-018: Make bet selections scrollable above sticky section
**Description:** As a user, I want to scroll through my bet selections while keeping stake/payout visible.

**Acceptance Criteria:**
- [ ] Bet selection cards are in a scrollable area
- [ ] Scrollable area is above the sticky stake/payout section
- [ ] Scroll area has proper padding so last item isn't hidden behind sticky section
- [ ] Scroll indicators visible when content overflows
- [ ] Typecheck passes

---

### US-019: Fix segmented control tap area on bet slip
**Description:** As a user, I want to tap anywhere on the Singles/Parlay segment to switch, not just the text.

**Acceptance Criteria:**
- [ ] Entire segment area is tappable (not just the label text)
- [ ] Tap target covers full width and height of each segment
- [ ] Visual feedback (highlight) on tap covers full segment
- [ ] Typecheck passes

---

### US-020: Remove bet review screen
**Description:** As a user, I want to submit my bet directly after entering stake without an extra confirmation screen.

**Acceptance Criteria:**
- [ ] "Place Bet" button submits bet immediately (no intermediate review screen)
- [ ] Bet confirmation shown as toast/alert after successful submission
- [ ] Error handling shown inline if submission fails
- [ ] Bet slip closes after successful submission
- [ ] Typecheck passes

---

### US-021: Fix player balance color logic
**Description:** As a user, I want balance colors to make sense: positive = good (I have credit), negative = I owe money.

**Acceptance Criteria:**
- [ ] Positive balance displayed in accent/green (player has credit)
- [ ] Negative balance displayed in danger/red (player owes bookie)
- [ ] Zero balance displayed in neutral/secondary color
- [ ] This logic applies to header balance display
- [ ] This logic applies to Track tab and bet history
- [ ] Typecheck passes

---

### US-022: Standardize card background color across app
**Description:** As a user, I want consistent card styling so the app feels cohesive.

**Acceptance Criteria:**
- [ ] Account page card background color identified as the standard
- [ ] Settings tab uses same card background color (replace current gray)
- [ ] Bookie dashboard cards use same card background color
- [ ] All cards use `Theme.cardBackground` or equivalent
- [ ] Typecheck passes

---

## Functional Requirements

- FR-1: Tab bar order must be Games, Track, Settings (left to right)
- FR-2: Persistent header component must appear on all three main tabs
- FR-3: Header left side must show user photo (or initials fallback) and username
- FR-4: Header user section must navigate to Account page on tap
- FR-5: Header right side must show balance with color coding (green=positive, red=negative, gray=zero)
- FR-6: Balance display must not be interactive
- FR-7: Remove "Your Account" section from Games tab
- FR-8: Remove "Account Summary" section from Track tab
- FR-9: Bets in Track tab must be grouped by ticket/transaction
- FR-10: Ticket summary cards must show type, leg count, stake, payout, and status
- FR-11: Tapping a ticket must navigate to bet detail page
- FR-12: Bet detail page must show all legs, timestamps, and result breakdown
- FR-13: Bet detail page must include "Repeat Bet" action (disabled if events unavailable)
- FR-14: Game cards must NOT have "All Markets" expand button
- FR-15: Game cards must show three columns: SPREAD, ML, TOTAL
- FR-16: Total column must show Over (top row) and Under (bottom row)
- FR-17: Total buttons must display value as main text (e.g., "O 7.5") and odds as secondary
- FR-18: Odds button size must be reduced to fit three columns (~64pt width)
- FR-19: Bet slip must open to ~85-90% screen height
- FR-20: Bet slip must have sticky bottom section with stake input and potential payout
- FR-21: Bet slip must NOT include preset stake buttons
- FR-22: Bet selections must be scrollable above the sticky section
- FR-23: Segmented control (Singles/Parlay) must have full-area tap targets
- FR-24: Bet submission must happen directly without review screen
- FR-25: Positive player balance = green (has credit), negative = red (owes money)
- FR-26: Card background color must be consistent: Account, Settings, Dashboard

## Non-Goals

- No user photo upload functionality (use existing photo or initials)
- No push notifications for bet results
- No bet editing (only repeat as new bet)
- No share functionality for bets
- No batch actions on multiple tickets
- No preset stake amounts
- No expandable "All Markets" section on game cards (all markets visible by default)
- No bet review/confirmation screen before submission

## Design Considerations

- Header should use the new gamelike theme (gradients, accent colors)
- Initials avatar should use `Theme.accent` or `Theme.accentSecondary` background
- Ticket cards should use `Theme.cardStyle()` modifier
- Balance color should use `Theme.accent` (positive), `Theme.danger` (negative), `Theme.textSecondary` (zero)
- Detail page should follow existing navigation patterns
- Bet slip sticky section should have subtle top border or shadow to separate from scroll area
- Potential payout should be prominently displayed (larger font, accent color)
- Game card odds grid: 3 equal columns (~64pt each) with 8pt spacing
- Odds button text: main text ~14pt bold, secondary text ~10pt
- Create `TotalButton` component similar to `SpreadButton` for consistency
- Team names may need to truncate with "..." for longer names
- Segmented control should use `Picker` with `.pickerStyle(.segmented)` or custom implementation with proper hit testing
- Card backgrounds: use `Theme.cardBackground` consistently (currently correct on Account page)
- Balance colors: green = positive/credit, red = negative/owes (opposite of "owing" perspective)

## Technical Considerations

- Bets need a `ticketId` or grouping mechanism to associate related bets
- If no ticket grouping exists in data model, may need migration
- Header component should be reusable across tab views
- Consider using `@EnvironmentObject` for user/balance data in header
- Bet slip layout needs `ScrollView` + sticky footer pattern (use `safeAreaInset` or geometry reader)
- Create new `TotalButton` component modeled after `SpreadButton`
- Remove `expandedMarketsSection` and `expandButton` from `GameCardView`
- Update `oddsButtonSize` constant from 72 to ~64 for three-column layout
- `teamsWithOddsSection` needs to include Total market column
- Review screen view/navigation to be removed from bet submission flow
- Segmented control may need custom implementation for full tap area
- Audit all views using gray backgrounds to replace with `Theme.cardBackground`

## Success Metrics

- User can see their balance without navigating away from current tab
- Bet history is clearer with grouped tickets vs flat list
- Reduced tap count to access account (1 tap from any tab)
- Users can repeat bets in under 3 taps
- Stake and payout always visible when adjusting bets

## Open Questions

- Is there an existing ticket/transaction ID in the bet data model?
- What should "Repeat Bet" do for parlays where only some events are available?
