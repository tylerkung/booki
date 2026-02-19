# PRD: Player UX Polish

## Introduction

Close the visual gap between Booki and major sportsbooks (DraftKings, FanDuel, Caesars) with 7 targeted improvements to the player-facing experience. These changes focus on the Games lobby and Bet Slip — the two screens players interact with most. Additionally, replace the system font site-wide with Space Grotesk for a more sporty, techy aesthetic.

## Goals

- Match competitor visual density and polish in game rows (team badges, wider odds buttons, sport icons)
- Improve bet slip usability with balance display and custom keypad
- Make game row navigation more discoverable
- Establish a distinctive brand typography with Space Grotesk
- All changes are player-facing only; bookie views are unaffected

## User Stories

### US-001: Add Space Grotesk font to the project
**Description:** As a developer, I need Space Grotesk font files bundled in the Xcode project so views can reference them.

**Acceptance Criteria:**
- [ ] Download Space Grotesk in Regular, Medium, and Bold weights (`.ttf` or `.otf` files)
- [ ] Add font files to `Booki/Fonts/` directory
- [ ] Register fonts in Info.plist under `UIAppFonts` (Fonts provided by application)
- [ ] Add font files to the Xcode project target (ensure they are included in "Copy Bundle Resources")
- [ ] Verify fonts load at runtime with a test view
- [ ] Typecheck passes

### US-002: Add font helpers to Theme.swift
**Description:** As a developer, I need centralized font helpers so all views use Space Grotesk consistently.

**Acceptance Criteria:**
- [ ] Add static font methods to Theme: `Theme.font(size:weight:)` returning `Font.custom("SpaceGrotesk-...", size:)`
- [ ] Map weight parameter to font file names: `.regular` → SpaceGrotesk-Regular, `.medium` → SpaceGrotesk-Medium, `.bold` → SpaceGrotesk-Bold
- [ ] Add convenience properties matching SwiftUI's type scale: `Theme.title1`, `Theme.headline`, `Theme.body`, `Theme.subheadline`, `Theme.footnote`, `Theme.caption`, `Theme.caption2`
- [ ] Add `Theme.monoDigits(size:weight:)` that returns Space Grotesk with `.monospacedDigit()` for odds/numbers
- [ ] Typecheck passes

### US-003: Apply Space Grotesk site-wide
**Description:** As a user, I want the app to use a consistent, sporty font throughout so it feels distinct from default iOS apps.

**Acceptance Criteria:**
- [ ] Replace `.font(.system(...))` calls across all view files with `Theme.font(...)` or `Theme.headline`, etc.
- [ ] Replace `.font(.largeTitle)`, `.font(.title)`, `.font(.headline)`, `.font(.body)`, `.font(.caption)`, etc. with Theme equivalents
- [ ] Odds displays use `Theme.monoDigits(...)` for tabular number alignment
- [ ] Loading screen, onboarding, auth views, player views, and bookie views all use Space Grotesk
- [ ] No remaining `.font(.system(...))` calls except where truly needed (e.g., SF Symbols)
- [ ] Typecheck passes

### US-004: Add team abbreviation badges to CompactGameRow
**Description:** As a player, I want to see team abbreviation badges next to team names so games are instantly recognizable, matching the look of major sportsbooks.

**Acceptance Criteria:**
- [ ] Add a helper function that derives a 2-3 letter abbreviation from a team name (e.g., "Los Angeles Lakers" → "LAL", "Boston Celtics" → "BOS")
- [ ] Logic: Use last word of team name, take first 3 letters, uppercase. For two-word cities (e.g., "Golden State Warriors"), use first letter of city + first 2 letters of team name
- [ ] Display abbreviation inside a small circle (24x24pt) with `Theme.elevatedBackground` fill and `Theme.textSecondary` text
- [ ] Position badge to the left of each team name in the two-row game layout
- [ ] Badge uses `Theme.caption2` equivalent font size, bold weight
- [ ] Away team badge on the top row, home team badge on the bottom row
- [ ] Typecheck passes

### US-005: Widen odds buttons from 52pt to 65pt
**Description:** As a player, I want larger odds buttons so they're easier to read and tap, especially for spread/total buttons that show two lines of text.

**Acceptance Criteria:**
- [ ] Change `oddsButtonWidth` from 52 to 65 in CompactGameRow
- [ ] Verify spread buttons (line value + odds) have adequate spacing at new width
- [ ] Verify moneyline buttons display cleanly at new width
- [ ] Verify the three-column layout (Spread | Money | Total) still fits on smallest supported device (iPhone SE / 375pt width)
- [ ] Selected state styling looks correct at new width
- [ ] Typecheck passes

### US-006: Add sport icons to filter tabs
**Description:** As a player, I want sport filter tabs with icons so I can quickly identify and switch between sports visually.

**Acceptance Criteria:**
- [ ] Create a helper function/dictionary mapping sport keys to SF Symbol names: `basketball` → `basketball.fill`, `football` → `football.fill`, `soccer` → `soccerball`, `baseball` → `baseball.diamond.bases`, `hockey` → `hockey.puck.fill`, `mma` → `figure.martial.arts`, `tennis` → `tennisball.fill`, `golf` → `figure.golf`
- [ ] Update sport filter pills in GamesView to show icon + text (e.g., 🏀 NBA)
- [ ] Icon size 14pt, positioned to the left of the sport text
- [ ] Selected state: accent background with dark text (existing pattern)
- [ ] Unselected state: card background with secondary text (existing pattern)
- [ ] "All" tab has no icon or uses `sportscourt` symbol
- [ ] Typecheck passes

### US-007: Add available markets count badge to game rows
**Description:** As a player, I want to see how many additional markets are available for each game so I know there's more to explore beyond the 3 main lines.

**Acceptance Criteria:**
- [ ] Count the number of Market records associated with each Event
- [ ] Display a small badge at the trailing edge of the game row: "+N" format (e.g., "+12") where N is total markets minus the 3 shown (spread/money/total)
- [ ] Only show badge when additional markets exist (N > 0)
- [ ] Badge styled as a pill: `Theme.elevatedBackground` background, `Theme.textMuted` text, `Theme.caption2` font
- [ ] Add a subtle chevron (`chevron.right`) after the badge
- [ ] Tapping anywhere on the game row (outside odds buttons) navigates to game detail
- [ ] Typecheck passes

### US-008: Show player balance in bet slip header
**Description:** As a player, I want to see my current balance and credit limit at the top of the bet slip so I know how much I can wager without leaving the slip.

**Acceptance Criteria:**
- [ ] Add a balance display row between the bet slip title bar and the first bet card
- [ ] Format: "Balance: $250.00 / $1,000.00 limit" using player's current display balance and credit limit
- [ ] Balance amount uses `balanceColor` logic (green if positive/credit, red if negative/debt, secondary if zero)
- [ ] Credit limit shown in `Theme.textMuted`
- [ ] Balance data sourced from the Player object passed to BetSlipSheet (or via environment)
- [ ] Row has subtle bottom divider matching existing `Theme.divider` pattern
- [ ] Typecheck passes

### US-009: Build custom numeric keypad component
**Description:** As a developer, I need a reusable custom numeric keypad view that replaces the iOS system keyboard for stake entry.

**Acceptance Criteria:**
- [ ] Create `NumericKeypadView` in a new file `Booki/Views/NumericKeypadView.swift`
- [ ] Grid layout: 4 columns × 4 rows: `[1][2][3][DEL]` / `[4][5][6][+$5]` / `[7][8][9][+$10]` / `[.][0][+$25][+$50]`
- [ ] Each number key appends the digit to the bound text value
- [ ] Decimal key (`.`) only works once per value (prevent "12.5.3")
- [ ] Delete key removes the last character
- [ ] Quick stake buttons (+$5, +$10, +$25, +$50) add to the current numeric value (additive)
- [ ] Keys styled with `Theme.elevatedBackground` background, `Theme.textPrimary` text, 44pt minimum height
- [ ] Quick stake keys styled with `Theme.accent.opacity(0.15)` background and `Theme.accent` text
- [ ] Press animation: scale to 0.95 on tap with spring animation
- [ ] Accepts a `Binding<String>` for the text value and an optional `onValueChanged` callback
- [ ] Typecheck passes

### US-010: Integrate custom keypad into BetSlipSheet
**Description:** As a player, I want the bet slip to use the custom keypad instead of the iOS keyboard so the slip doesn't jump around and feels more polished.

**Acceptance Criteria:**
- [ ] Replace all `TextField` stake inputs with display-only `Text` views that show the current value
- [ ] Tapping a stake field sets it as the "active field" (track which field is being edited via state)
- [ ] Active field has a highlighted border (accent glow, existing `glowingBorder` pattern)
- [ ] NumericKeypadView appears pinned to the bottom of the bet slip (above the Place Bet button)
- [ ] Keypad is always visible when a stake field is active (no iOS keyboard dismiss animation)
- [ ] Tapping outside stake fields or tapping the active field again deactivates the keypad
- [ ] Both WAGER and TO WIN fields are tappable; editing one auto-calculates the other (existing bidirectional logic)
- [ ] In parlay mode, keypad edits the single parlay stake field
- [ ] In singles mode, keypad edits the per-card stake field that is currently active
- [ ] Quick stake buttons on the keypad work with whichever field is active
- [ ] Typecheck passes

## Functional Requirements

- FR-1: Space Grotesk font files (Regular, Medium, Bold) must be bundled and registered in the app
- FR-2: All text in the app must use Space Grotesk via Theme font helpers; no raw `.font(.system(...))` calls
- FR-3: Team abbreviation badges must derive abbreviations from existing Event team name strings
- FR-4: Odds buttons must be 65pt wide and fit within the smallest supported screen width (375pt)
- FR-5: Sport filter tabs must show SF Symbol icons alongside sport text labels
- FR-6: Game rows must display a "+N markets" badge when additional markets exist beyond the 3 main lines
- FR-7: Bet slip header must display the player's current balance and credit limit
- FR-8: Custom numeric keypad must replace the iOS system keyboard for all stake entry in the bet slip
- FR-9: The keypad must integrate quick stake buttons (+$5, +$10, +$25, +$50) as additive increments
- FR-10: All changes must use Theme.swift colors and the new Theme font system; no hardcoded values

## Non-Goals (Out of Scope)

- Actual team logo image assets (using text abbreviation badges instead)
- Player prop market browsing (separate feature)
- Bookie-side view changes
- "Stake All" functionality for singles mode (future enhancement)
- Configurable quick stake amounts (future enhancement)
- Live score display inline in game rows (separate feature)
- Custom keypad for non-stake inputs (login, settings, etc.)

## Design Considerations

### Team Badge Styling
```
Circle: 24x24pt
Background: Theme.elevatedBackground
Text: 2-3 chars, Theme.textSecondary, bold, ~10pt
Position: Left of team name in each row
```

### Odds Button Sizing
```
Before: 52 × 44pt (cramped)
After:  65 × 44pt (readable, matches competitors)
```

### Sport Tab with Icon
```
[🏀 NBA] [🏈 NFL] [⚾ MLB] [🏒 NHL]
Icon: 14pt SF Symbol
Text: Sport abbreviation
Spacing: 4pt between icon and text
```

### Custom Keypad Layout
```
┌────────┬────────┬────────┬────────┐
│   1    │   2    │   3    │  DEL   │
├────────┼────────┼────────┼────────┤
│   4    │   5    │   6    │  +$5   │
├────────┼────────┼────────┼────────┤
│   7    │   8    │   9    │  +$10  │
├────────┼────────┼────────┼────────┤
│   .    │   0    │  +$25  │  +$50  │
└────────┴────────┴────────┴────────┘
```

### Balance Display in Bet Slip
```
Balance: $250.00 / $1,000.00 limit
[green]          [muted]
```

## Technical Considerations

- **Font bundling:** Space Grotesk `.ttf` files need to be added to the Xcode target's "Copy Bundle Resources" build phase and registered in Info.plist under `UIAppFonts`
- **Font.custom behavior:** `Font.custom("SpaceGrotesk-Bold", size: 17)` — ensure the font name matches the PostScript name in the font file
- **Odds button width change:** Verify total row width: team section + 3 buttons × 65pt + spacing fits in 375pt (iPhone SE). Budget: ~195pt for buttons + ~12pt spacing = ~207pt, leaving ~168pt for team names. Should be tight but workable.
- **Market count for badges:** Markets are already loaded via `@Query` in GamesView. Count markets per event using `markets.filter { $0.event?.id == event.id }.count`
- **Keypad state management:** Track `activeFieldId: String?` in BetSlipSheet to know which stake field the keypad should target. Use an enum or string identifier per bet item.
- **Balance in bet slip:** BetSlipSheet is presented as a sheet from PlayerMainView which has access to the player and balance. Pass these through to BetSlipSheet or use an EnvironmentObject.

## Success Metrics

- Visual parity with DraftKings/FanDuel on game rows (team badges, button size, sport icons)
- Zero iOS keyboard appearances during stake entry in bet slip
- Player can see their available credit at all times while building a bet
- Space Grotesk renders correctly at all type scale sizes across all screens
- No performance regression from font loading or keypad rendering

## Open Questions

- Should the team abbreviation helper handle edge cases like "76ers" (→ "PHI"?) or international teams? Start with simple last-word logic and iterate.
- Should the custom keypad support haptic feedback on key press?
- Should quick stake amounts eventually be configurable by the bookie in Settings?
