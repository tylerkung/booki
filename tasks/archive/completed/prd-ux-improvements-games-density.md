# PRD: Games View UX Improvements - Information Density

## Introduction

Redesign the player Games tab to increase information density and simplify the visual presentation. The current card-based layout with gradients, shadows, and decorative borders uses significant vertical space. Reference apps (Caesars, FanDuel, DraftKings) use compact table-style rows that fit more games on screen while maintaining clarity.

This PRD focuses on simplifying the UI to match industry-standard sportsbook patterns: compact rows, table-style odds columns, and minimal visual decoration. The existing dark theme and accent colors from Theme.swift remain unchanged.

## Goals

- Increase games visible per screen by 40-60% through compact row layout
- Simplify visual styling by removing decorative gradients, shadows, and borders
- Maintain tap targets and readability on odds buttons
- Keep existing functionality (search, sport tabs, favorites, bet slip)
- Preserve Theme.swift color system (no new colors)

## User Stories

### US-001: Replace GameCardView with CompactGameRow
**Description:** As a player, I want to see more games on screen so I can quickly scan available betting options.

**Acceptance Criteria:**
- [ ] Create new `CompactGameRow` component replacing `GameCardView`
- [ ] Row height reduced to ~80-90pt (from ~140pt cards)
- [ ] No card shadows, gradient borders, or decorative overlays
- [ ] Simple `Theme.cardBackground` with single 0.5pt `Theme.border` bottom divider
- [ ] Existing selection state (highlight when odds added to slip) still works
- [ ] Typecheck passes

### US-002: Implement Table-Style Odds Layout
**Description:** As a player, I want odds displayed in aligned columns so I can quickly compare spreads, moneylines, and totals across games.

**Acceptance Criteria:**
- [ ] Column headers (SPREAD, MONEY, TOTAL) displayed once at top of game list, not per-game
- [ ] Odds buttons sized at 52x44pt (reduced from 60x60pt)
- [ ] Away team row and home team row each show: Team name | Spread | ML | Total
- [ ] Remove VStack layout inside odds buttons - single line with spread/total value and odds combined (e.g., "-3.5 -110")
- [ ] Typecheck passes

### US-003: Compact Team Name Display
**Description:** As a player, I want team names displayed clearly without excessive spacing so more content fits on screen.

**Acceptance Criteria:**
- [ ] Team name uses `.system(size: 13, weight: .semibold)` (reduced from 14 bold)
- [ ] Team name row height is 36pt total
- [ ] Team names left-aligned, truncated with `...` if needed
- [ ] No team logos (keep text-only for simplicity)
- [ ] Typecheck passes

### US-004: Simplified Game Time Display
**Description:** As a player, I want game time shown compactly so it doesn't dominate the row.

**Acceptance Criteria:**
- [ ] Game time shown as single line above the matchup: "Today 7:00 PM" or "Sat, Jan 25"
- [ ] Font size `.caption2` (11pt) with `Theme.textSecondary` color
- [ ] Remove clock icon to save horizontal space
- [ ] Live indicator reduced to small "LIVE" badge without pulsing animation
- [ ] Lock icon shows inline when event is locked
- [ ] Typecheck passes

### US-005: Streamlined Odds Buttons
**Description:** As a player, I want odds buttons that are easy to tap but don't waste space with excessive styling.

**Acceptance Criteria:**
- [ ] Odds button background: `Theme.elevatedBackground` (unselected) or `Theme.accent` (selected)
- [ ] No gradient backgrounds - solid colors only
- [ ] No outer glow/shadow effects
- [ ] Border: 1pt `Theme.border` (unselected) or `Theme.accent` (selected)
- [ ] Corner radius: 6pt (Theme.cornerRadiusSmall)
- [ ] Maintain spring animation on tap but remove selection highlight radial gradient
- [ ] Typecheck passes

### US-006: Sticky Column Headers
**Description:** As a player, I want the SPREAD/MONEY/TOTAL column headers to stay visible while scrolling so I know which column is which.

**Acceptance Criteria:**
- [ ] Column headers row sticks below sport tabs when scrolling
- [ ] Headers use `.system(size: 10, weight: .semibold)` with `Theme.textMuted`
- [ ] Headers row has `Theme.background` background
- [ ] 0.5pt bottom border using `Theme.divider`
- [ ] Typecheck passes

### US-007: Sport Section Headers Inline
**Description:** As a player, I want sport/league headers to be compact so they don't interrupt the flow of games.

**Acceptance Criteria:**
- [ ] Section header format: "NBA • Eastern Conference" in single line
- [ ] Font: `.system(size: 12, weight: .medium)` with `Theme.textSecondary`
- [ ] Top padding 16pt, bottom padding 8pt
- [ ] No background color - just text
- [ ] Typecheck passes

### US-008: Remove Card Decorations from GamesView
**Description:** As a developer, I need to update GamesView to use the new compact row component.

**Acceptance Criteria:**
- [ ] GamesView uses `CompactGameRow` instead of `GameCardView`
- [ ] LazyVStack spacing reduced to 0 (dividers handle separation)
- [ ] Horizontal padding reduced to 12pt (from 16pt)
- [ ] Remove ForEach wrapper VStack with 12pt spacing
- [ ] Favorites section uses same compact row style
- [ ] Typecheck passes

### US-009: Consolidate Odds Button Components
**Description:** As a developer, I want a single reusable odds button component to reduce code duplication.

**Acceptance Criteria:**
- [ ] Create single `CompactOddsButton` component replacing SpreadButton, MLButton, TotalButton
- [ ] Parameters: `label: String` (e.g., "-3.5"), `odds: Int`, `isSelected: Bool`, `isDisabled: Bool`, `action: () -> Void`
- [ ] For spread/total: show label on top line, odds on bottom
- [ ] For moneyline: show odds only (centered)
- [ ] Remove OddsButton legacy component
- [ ] Typecheck passes

### US-010: Create Game Detail View
**Description:** As a player, I want to tap into a game and see all available betting markets so I can explore more options beyond the main lines.

**Acceptance Criteria:**
- [ ] Create `GameDetailView.swift` in Booki/Views/ (replaces MarketSelectionView for players)
- [ ] Game header shows: Away team vs Home team, game time, live status if applicable
- [ ] Header uses Theme.cardBackground with team names in `.title3` weight
- [ ] Display game time in format "Today 7:00 PM" or "Sat, Jan 25 • 1:00 PM"
- [ ] Tapping game row in GamesView navigates to GameDetailView
- [ ] Typecheck passes

### US-011: Game Detail Main Markets Section
**Description:** As a player, I want to see the main betting markets (spread, moneyline, total) prominently displayed at the top of the game detail page.

**Acceptance Criteria:**
- [ ] "Main Lines" section displays spread, moneyline, and total markets
- [ ] Each market shows both sides in a horizontal row (same as compact odds buttons)
- [ ] Use `CompactOddsButton` component for consistency
- [ ] Tapping an odds button adds selection to bet slip (via BetSlipManager)
- [ ] Selected state highlights with Theme.accent
- [ ] Section header uses `.system(size: 14, weight: .semibold)` with Theme.textPrimary
- [ ] Typecheck passes

### US-012: Game Detail Market Categories
**Description:** As a player, I want to browse different market categories (alternate lines, player props, game props) so I can find specific bets.

**Acceptance Criteria:**
- [ ] Horizontal scrolling category tabs below main markets: "All Markets", "Alternate Lines", "Player Props", "Game Props"
- [ ] Tab style matches sport tabs in GamesView (capsule buttons)
- [ ] "All Markets" selected by default, shows all available markets grouped by type
- [ ] Each category filters the displayed markets below
- [ ] Empty state shown if category has no markets: "No [category] markets available"
- [ ] Typecheck passes

### US-013: Game Detail Market List
**Description:** As a player, I want to see all markets for the selected category in a scannable list format.

**Acceptance Criteria:**
- [ ] Markets grouped by type with section headers (e.g., "Spread", "Total", "Moneyline")
- [ ] Each market row shows both sides with odds buttons
- [ ] For alternate lines: show the line value prominently (e.g., "Alt Spread -5.5")
- [ ] For player props: show player name and prop type (e.g., "LeBron James - Points")
- [ ] Use same compact styling as main games list (no decorative cards)
- [ ] Scrollable list with Theme.background
- [ ] Typecheck passes

### US-014: Game Detail Bet Slip Integration
**Description:** As a player, I want my selections from the game detail page to appear in my bet slip so I can continue building my ticket.

**Acceptance Criteria:**
- [ ] Selections made in GameDetailView add to BetSlipManager
- [ ] Floating bet slip indicator appears at bottom (same as GamesView)
- [ ] Tapping indicator opens BetSlipSheet
- [ ] Multiple selections from same game allowed (for parlays)
- [ ] Navigating back to GamesView preserves bet slip selections
- [ ] Typecheck passes

## Functional Requirements

### Games List
- FR-1: `CompactGameRow` displays away team and home team in two rows with aligned odds columns
- FR-2: Game time displays above team rows in compact format
- FR-3: SPREAD/MONEY/TOTAL headers display once per game list, sticky on scroll
- FR-4: Odds buttons use solid backgrounds without gradients or shadows
- FR-5: Selected odds buttons highlight with `Theme.accent` background
- FR-6: Tap on game row (outside odds buttons) navigates to GameDetailView
- FR-7: Sport/league section headers display as compact inline text
- FR-8: Live games show "LIVE" badge without pulsing animation
- FR-9: Locked games show lock icon and disabled odds buttons

### Game Detail Page
- FR-10: GameDetailView displays game header with teams, time, and status
- FR-11: Main Lines section shows spread, moneyline, and total at top
- FR-12: Category tabs filter markets: All Markets, Alternate Lines, Player Props, Game Props
- FR-13: Markets display in grouped sections with compact odds buttons
- FR-14: Selections add to BetSlipManager, shared with GamesView
- FR-15: Floating bet slip indicator appears when selections exist
- FR-16: Back navigation preserves bet slip state

## Non-Goals

- No team logos (adds complexity without significant value)
- No horizontal scrolling odds (all three columns visible at once)
- No odds movement indicators (e.g., arrows showing line changes)
- No featured games carousel (keep single list format)
- No alternate layouts or density settings

## Design Considerations

### Layout Reference (based on Caesars/FanDuel/DraftKings patterns)

```
┌─────────────────────────────────────────────────────┐
│ [Search teams...]                    [Filter ▼]     │  <- Existing search/filter
├─────────────────────────────────────────────────────┤
│ All   NBA   NFL   NHL   MLB   Soccer               │  <- Existing sport tabs
├─────────────────────────────────────────────────────┤
│              SPREAD      MONEY      TOTAL          │  <- Sticky column headers
├─────────────────────────────────────────────────────┤
│ NBA • Eastern Conference                           │  <- Section header
├─────────────────────────────────────────────────────┤
│ Today 7:00 PM                           LIVE       │  <- Time + status
│ BOS Celtics      [-3.5 -110] [+150]   [o220 -110] │  <- Away team row
│ NYK Knicks       [+3.5 -110] [-170]   [u220 -110] │  <- Home team row
├─────────────────────────────────────────────────────┤
│ Tomorrow 1:00 PM                                   │
│ MIA Heat         [-1.5 -105] [+120]   [o215 -110] │
│ ATL Hawks        [+1.5 -115] [-140]   [u215 -110] │
└─────────────────────────────────────────────────────┘
```

### Game Detail Page Layout (based on DraftKings/FanDuel patterns)

```
┌─────────────────────────────────────────────────────┐
│ ← Back                                              │
├─────────────────────────────────────────────────────┤
│                   BOS Celtics                       │
│                       vs                            │
│                   NYK Knicks                        │
│              Today 7:00 PM • LIVE                   │
├─────────────────────────────────────────────────────┤
│ MAIN LINES                                          │
│ ┌─────────────┬─────────────┬─────────────┐        │
│ │   SPREAD    │    MONEY    │    TOTAL    │        │
│ ├─────────────┼─────────────┼─────────────┤        │
│ │ BOS -3.5    │ BOS +150    │  o220.5     │        │
│ │   -110      │             │   -110      │        │
│ ├─────────────┼─────────────┼─────────────┤        │
│ │ NYK +3.5    │ NYK -170    │  u220.5     │        │
│ │   -110      │             │   -110      │        │
│ └─────────────┴─────────────┴─────────────┘        │
├─────────────────────────────────────────────────────┤
│ All Markets  Alt Lines  Player Props  Game Props   │  <- Category tabs
├─────────────────────────────────────────────────────┤
│ Alternate Spread                                    │
│ ┌───────────────────┬───────────────────┐          │
│ │ BOS -1.5  -155    │ NYK +1.5  +135    │          │
│ └───────────────────┴───────────────────┘          │
│ ┌───────────────────┬───────────────────┐          │
│ │ BOS -5.5  +120    │ NYK +5.5  -140    │          │
│ └───────────────────┴───────────────────┘          │
│                                                     │
│ Alternate Total                                     │
│ ┌───────────────────┬───────────────────┐          │
│ │ Over 215.5  -130  │ Under 215.5 +110  │          │
│ └───────────────────┴───────────────────┘          │
├─────────────────────────────────────────────────────┤
│ 🎫 2 Selections                          [▲]       │  <- Bet slip indicator
└─────────────────────────────────────────────────────┘
```

### Sizing Reference

| Element | Current | New |
|---------|---------|-----|
| Card/Row height | ~140pt | ~80pt |
| Odds button | 60x60pt | 52x44pt |
| Team name font | 14pt bold | 13pt semibold |
| Horizontal padding | 16pt | 12pt |
| Section spacing | 16pt | 0 (dividers) |

### Color Usage (existing Theme.swift)

- Background: `Theme.background`
- Row background: `Theme.cardBackground`
- Dividers: `Theme.divider` at 0.5pt
- Odds unselected: `Theme.elevatedBackground`
- Odds selected: `Theme.accent`
- Text primary: `Theme.textPrimary`
- Text secondary: `Theme.textSecondary`
- Headers: `Theme.textMuted`

## Technical Considerations

- Keep `BetSlipSelection` model unchanged
- Keep `BetSlipManager` integration unchanged
- `CompactGameRow` should accept same parameters as `GameCardView` for easy swap
- Consider extracting column header as separate component for sticky behavior
- Use `LazyVStack(pinnedViews: [.sectionHeaders])` for sticky headers

## Success Metrics

- 5+ games visible on iPhone screen without scrolling (vs current ~3)
- Odds buttons remain easy to tap (44pt minimum touch target maintained)
- No regression in bet slip functionality
- Visual consistency with dark theme maintained

## Open Questions

- Should we add team abbreviations option (e.g., "BOS" vs "Boston Celtics")?
- Should the row tap area exclude more than just odds buttons?
