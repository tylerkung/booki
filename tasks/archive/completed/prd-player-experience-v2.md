# PRD: Booki Player Experience v2

## Introduction

Booki is in a functional first-draft state with basic bookie and player capabilities. This phase focuses on elevating the player experience with comprehensive game browsing, an improved bet slip, and enhanced account features. Additionally, we'll implement a dark sports-betting aesthetic throughout the app, add bookie-side event/odds management with mock data support, and significantly improve the grading, settlement, and collection workflows for bookies.

## Goals

- Create a polished, immersive player experience for browsing and betting on games
- Implement a dark theme with sports/betting aesthetic across the entire app
- Enable bookies to manually create and manage events/odds (mock data for testing)
- Improve bet slip UX with multi-bet support and quick picks
- Enhance player account features with detailed financial breakdowns
- Prepare authentication model for future username/password login (keep test mode for now)
- Streamline grading and settlement with bulk operations and undo capability
- Provide clear visibility into who owes what with collection tracking
- Enable payment recording and settlement summaries for end-of-week reconciliation

## User Stories

### Phase 1: Mock Data & Event Management (Bookie Side)

#### US-031: Create Event Management View for Bookie
**Description:** As a bookie, I want to manually create and manage events so I can set up games for my players to bet on.

**Acceptance Criteria:**
- [ ] New "Events" tab in bookie mode TabView (between Players and Grading)
- [ ] EventsListView shows all events grouped by sport/league
- [ ] Events sorted by start time (upcoming first)
- [ ] Status badges: Scheduled (blue), Live (green), Final (gray)
- [ ] Tap event to view/edit details
- [ ] Project builds and runs in Simulator

#### US-032: Build Add Event Form
**Description:** As a bookie, I want to create new events with teams, sport, league, and start time.

**Acceptance Criteria:**
- [ ] "+" button in Events tab toolbar presents AddEventSheet
- [ ] Form fields: sport (picker), league (text), homeTeam, awayTeam, startTime (DatePicker)
- [ ] Sport picker includes: NFL, NBA, MLB, NHL, Soccer, UFC, Tennis, Other
- [ ] Validation: all fields required
- [ ] Save creates event with status "scheduled"
- [ ] Project builds and runs in Simulator

#### US-033: Build Market Management for Events
**Description:** As a bookie, I want to add betting markets (spread, total, moneyline) to events with custom odds.

**Acceptance Criteria:**
- [ ] EventDetailView has "Markets" section with list of existing markets
- [ ] "Add Market" button presents AddMarketSheet
- [ ] Market type picker: Spread, Total, Moneyline
- [ ] Dynamic form based on type:
  - Spread: sideA (team + spread), sideB (team + spread), oddsA, oddsB
  - Total: sideA (Over X), sideB (Under X), oddsA, oddsB
  - Moneyline: sideA (team), sideB (team), oddsA, oddsB
- [ ] Odds input as American odds (e.g., -110, +150)
- [ ] Edit existing market odds inline or via sheet
- [ ] Delete market with swipe action
- [ ] Project builds and runs in Simulator

#### US-034: Seed Mock Data Script
**Description:** As a developer, I want to seed realistic mock game data for testing purposes.

**Acceptance Criteria:**
- [ ] SeedDataService with static method to generate mock events
- [ ] Includes 10+ events across NFL, NBA, MLB sports
- [ ] Each event has 2-3 markets (spread, total, moneyline)
- [ ] Mix of scheduled and live events
- [ ] Button in Settings (bookie mode) to "Load Sample Data"
- [ ] Clears existing events before seeding (with confirmation)
- [ ] Project builds and runs in Simulator

#### US-035: Update Event Status and Final Score
**Description:** As a bookie, I want to update event status and enter final scores for grading.

**Acceptance Criteria:**
- [ ] EventDetailView has status picker: Scheduled, Live, Final
- [ ] When status changed to Final, prompt for final score entry
- [ ] Final score format: homeScore - awayScore
- [ ] Changing to Final auto-transitions related bets to "readyToGrade"
- [ ] Project builds and runs in Simulator

### Phase 2: Player Game Browsing Experience

#### US-036: Redesign Player Games View with Sport Tabs
**Description:** As a player, I want to browse games organized by sport with easy navigation.

**Acceptance Criteria:**
- [ ] Replace current SubmitBetView with new GamesView
- [ ] Horizontal scrolling sport tabs at top (All, NFL, NBA, MLB, etc.)
- [ ] Only show sports that have available events
- [ ] "All" tab selected by default
- [ ] Sticky header that stays visible while scrolling
- [ ] Project builds and runs in Simulator

#### US-037: Build Game Card Component
**Description:** As a player, I want game cards that show key info at a glance with quick betting options.

**Acceptance Criteria:**
- [ ] GameCard component showing: teams, start time, live indicator
- [ ] Team names with abbreviated format option (e.g., "LAL" vs "Lakers")
- [ ] Quick-pick odds buttons for spread and moneyline visible on card
- [ ] Tapping odds button adds selection to bet slip
- [ ] Tapping card expands to show all markets
- [ ] Visual feedback when odds button tapped (selection state)
- [ ] Project builds and runs in Simulator

#### US-038: Implement Search and Filter
**Description:** As a player, I want to search for specific teams or filter games.

**Acceptance Criteria:**
- [ ] Search bar at top of games view
- [ ] Search matches team names (home or away)
- [ ] Filter options: Today, Tomorrow, This Week, All
- [ ] Filter accessible via button next to search
- [ ] Empty state when no results match
- [ ] Project builds and runs in Simulator

#### US-039: Add Favorites System
**Description:** As a player, I want to favorite teams so I can quickly find their games.

**Acceptance Criteria:**
- [ ] Star/heart icon on game cards to favorite
- [ ] Favorites stored in UserDefaults (by team name for now)
- [ ] "Favorites" filter option shows only games with favorited teams
- [ ] Favorites section at top of All games view (if any exist)
- [ ] Project builds and runs in Simulator

### Phase 3: Bet Slip Improvements

#### US-040: Build Persistent Bet Slip
**Description:** As a player, I want a bet slip that persists my selections as I browse games.

**Acceptance Criteria:**
- [ ] BetSlip model stored in app state (not navigation-dependent)
- [ ] Floating bet slip indicator showing selection count
- [ ] Tap indicator to expand full bet slip sheet
- [ ] Selections persist while browsing different games
- [ ] Clear all button in bet slip
- [ ] Project builds and runs in Simulator

#### US-041: Support Multi-Bet (Parlay) Selections
**Description:** As a player, I want to add multiple selections to my bet slip.

**Acceptance Criteria:**
- [ ] Can add up to 10 selections to bet slip
- [ ] Each selection shows: event, side, odds
- [ ] Remove individual selections with swipe or X button
- [ ] Show combined odds for parlay (multiply decimal odds)
- [ ] Toggle between "Singles" and "Parlay" mode
- [ ] Project builds and runs in Simulator

#### US-042: Improved Stake Entry
**Description:** As a player, I want a better stake entry experience with quick-pick amounts.

**Acceptance Criteria:**
- [ ] Quick-pick stake buttons: $5, $10, $25, $50, $100
- [ ] Custom amount input field
- [ ] Show potential payout updating in real-time
- [ ] For parlays, show combined payout
- [ ] Stake validation against available credit
- [ ] Project builds and runs in Simulator

#### US-043: Bet Confirmation Flow
**Description:** As a player, I want a clear confirmation before submitting my bet request.

**Acceptance Criteria:**
- [ ] Review screen showing all selections with odds and stake
- [ ] Total stake and potential payout summary
- [ ] Compliance disclosure text
- [ ] "Confirm" button submits all bets
- [ ] Success animation/feedback on submission
- [ ] Bet slip clears after successful submission
- [ ] Project builds and runs in Simulator

### Phase 4: Player Account Features

#### US-044: Enhanced Account Summary View
**Description:** As a player, I want a comprehensive view of my account status.

**Acceptance Criteria:**
- [ ] Dedicated "Account" tab in player mode (replace current My Bets as primary)
- [ ] Hero section with current balance (large, prominent)
- [ ] Available credit with visual progress bar toward limit
- [ ] Quick stats: Open bets count, Pending bets count, Win rate
- [ ] Project builds and runs in Simulator

#### US-045: Transaction History View
**Description:** As a player, I want to see a detailed history of all balance changes.

**Acceptance Criteria:**
- [ ] "History" section in Account tab
- [ ] List of all ledger entries (settlements, adjustments, payments)
- [ ] Each entry shows: date, type, amount (+/-), description
- [ ] Color coding: green for credits, red for debits
- [ ] Filter by type: All, Settlements, Adjustments, Payments
- [ ] Project builds and runs in Simulator

#### US-046: Bet History with Filtering
**Description:** As a player, I want to view my bet history with filters for status.

**Acceptance Criteria:**
- [ ] "My Bets" section accessible from Account tab
- [ ] Filter tabs: Active, Settled, All
- [ ] Active = pending + accepted
- [ ] Settled = won, lost, push, void
- [ ] Sort by date (newest first)
- [ ] Tap bet for detail view with full info
- [ ] Project builds and runs in Simulator

#### US-047: Win/Loss Statistics
**Description:** As a player, I want to see my betting performance statistics.

**Acceptance Criteria:**
- [ ] Stats card in Account view
- [ ] Total bets placed
- [ ] Win/Loss/Push record (e.g., "12-8-1")
- [ ] Win percentage
- [ ] Total profit/loss amount
- [ ] ROI percentage (profit / total staked)
- [ ] Project builds and runs in Simulator

### Phase 5: Dark Theme & Styling

#### US-048: Define Color Palette and Design Tokens
**Description:** As a developer, I need a consistent color system for the dark sports-betting theme.

**Acceptance Criteria:**
- [ ] Create Theme.swift with color definitions
- [ ] Primary background: near-black (#0D0D0D or similar)
- [ ] Secondary background: dark gray for cards (#1A1A1A)
- [ ] Accent color: vibrant green for positive/wins (#00FF87 or similar)
- [ ] Secondary accent: gold/yellow for highlights
- [ ] Danger color: red for losses/errors
- [ ] Text colors: white primary, gray secondary
- [ ] Project builds and runs in Simulator

#### US-049: Apply Dark Theme to App Shell
**Description:** As a user, I want the app to have a dark theme throughout.

**Acceptance Criteria:**
- [ ] Set app-wide color scheme to dark
- [ ] TabView with custom styling (dark background, accent selection)
- [ ] NavigationStack with dark styling
- [ ] All List views with dark background (not system grouped)
- [ ] Consistent across bookie and player modes
- [ ] Project builds and runs in Simulator

#### US-050: Style Game Cards with Betting Aesthetic
**Description:** As a player, I want game cards that feel like a premium sportsbook.

**Acceptance Criteria:**
- [ ] Card background with subtle gradient or border
- [ ] Team names in bold, high-contrast typography
- [ ] Odds buttons with pill/capsule shape
- [ ] Selected odds have bright accent background
- [ ] Live games have pulsing/glowing live indicator
- [ ] Subtle shadows for depth
- [ ] Project builds and runs in Simulator

#### US-051: Style Bet Slip with Premium Feel
**Description:** As a player, I want the bet slip to feel polished and exciting.

**Acceptance Criteria:**
- [ ] Dark sheet background with accent border at top
- [ ] Each selection in a card with team logos placeholder (colored circles)
- [ ] Odds displayed prominently with color
- [ ] Stake input with custom styling (not default TextField)
- [ ] Payout display with green accent
- [ ] Submit button with gradient or glow effect
- [ ] Project builds and runs in Simulator

#### US-052: Style Account and Stats Views
**Description:** As a player, I want the account views to match the dark theme.

**Acceptance Criteria:**
- [ ] Balance displayed in large, bold typography
- [ ] Credit utilization as styled progress bar
- [ ] Stats cards with dark backgrounds and accent highlights
- [ ] Win/loss colored appropriately (green/red)
- [ ] Transaction history with clear visual hierarchy
- [ ] Project builds and runs in Simulator

#### US-053: Add Subtle Animations
**Description:** As a user, I want subtle animations that make the app feel alive.

**Acceptance Criteria:**
- [ ] Odds button tap has scale animation
- [ ] Bet slip expand/collapse is animated
- [ ] Adding selection to slip has brief highlight animation
- [ ] Successful bet submission has celebration animation (subtle)
- [ ] Tab switching has smooth transition
- [ ] No animations that slow down core interactions
- [ ] Project builds and runs in Simulator

### Phase 6: Authentication Prep

#### US-054: Add Username/Password Fields to Player Model
**Description:** As a developer, I need to store credentials for future player authentication.

**Acceptance Criteria:**
- [ ] Add optional `username` field to Player model
- [ ] Add optional `passwordHash` field to Player model (never store plain text)
- [ ] Migration handles existing players (fields are nil)
- [ ] AddPlayerSheet has optional username field
- [ ] Project builds and runs in Simulator

#### US-055: Player Login View (UI Only)
**Description:** As a developer, I want to build the login UI for future implementation.

**Acceptance Criteria:**
- [ ] PlayerLoginView with username and password fields
- [ ] "Login" button (currently triggers test mode with matching player)
- [ ] "Forgot Password" link (shows placeholder alert)
- [ ] Styled with dark theme
- [ ] Not active in main flow yet (accessible via Settings for testing)
- [ ] Project builds and runs in Simulator

### Phase 7: Grading, Settlements & Collections (Bookie Side)

#### US-056: Bulk Grading by Event
**Description:** As a bookie, I want to grade all bets for a finished event at once based on the final score.

**Acceptance Criteria:**
- [ ] EventDetailView shows "Grade All Bets" button when event status is Final
- [ ] Button shows count of bets to grade (e.g., "Grade All Bets (12)")
- [ ] Tapping opens GradeEventSheet with:
  - Event summary (teams, final score)
  - List of all bets grouped by market type
  - Auto-calculated suggested outcome per bet based on final score
  - Override option per bet if needed
- [ ] "Apply All" button grades all bets with suggested outcomes
- [ ] Confirmation dialog before applying
- [ ] Success summary shows grades applied (X wins, Y losses, Z pushes)
- [ ] Project builds and runs in Simulator

#### US-057: Undo/Reverse Settlement
**Description:** As a bookie, I want to reverse a settled bet if I made an error.

**Acceptance Criteria:**
- [ ] BetDetailView shows "Reverse Settlement" button for settled bets
- [ ] Reversal creates a new ledger entry that negates the original settlement
- [ ] Bet status changes back to "graded" (can be re-settled)
- [ ] Reversal entry has type "reversal" with description noting original bet
- [ ] Confirmation dialog with warning about impact on player balance
- [ ] Reversal is logged for audit trail
- [ ] Project builds and runs in Simulator

#### US-058: Payment Recording
**Description:** As a bookie, I want to record when a player pays me or I pay a player.

**Acceptance Criteria:**
- [ ] PlayerDetailView has "Record Payment" button
- [ ] PaymentSheet with fields:
  - Amount (positive number)
  - Direction: "Player Paid Me" or "I Paid Player"
  - Payment method (Cash, Venmo, Zelle, Bank, Other)
  - Optional note/reference
- [ ] Creates ledger entry with type "paymentLogged"
- [ ] Negative amount for player paying bookie (reduces what they owe)
- [ ] Positive amount for bookie paying player (reduces what bookie owes)
- [ ] Payment history visible in player's ledger
- [ ] Project builds and runs in Simulator

#### US-059: Weekly Settlement Summary
**Description:** As a bookie, I want to see a summary of the week's activity for settlement purposes.

**Acceptance Criteria:**
- [ ] New "Settlements" section in Dashboard or dedicated view
- [ ] Week picker to select settlement period (Mon-Sun default)
- [ ] Summary shows:
  - Total bets graded this period
  - Total won by players (sum of winning payouts)
  - Total lost by players (sum of losing stakes)
  - Net movement (who owes whom overall)
- [ ] Per-player breakdown:
  - Player name, bets settled, net result, current balance
- [ ] Export summary as text/CSV for sharing
- [ ] Project builds and runs in Simulator

#### US-060: Who Owes Dashboard Widget
**Description:** As a bookie, I want to see at a glance who owes me and who I owe.

**Acceptance Criteria:**
- [ ] Dashboard has "Balances" section prominently displayed
- [ ] Split into two lists:
  - "Players Owe You" (positive balances) - sorted by amount descending
  - "You Owe Players" (negative balances) - sorted by amount descending
- [ ] Each row shows: player name, amount, days since last activity
- [ ] Total owed to you and total you owe at section headers
- [ ] Tap player to go to their detail view
- [ ] Project builds and runs in Simulator

#### US-061: Collection Tracking
**Description:** As a bookie, I want to track collection status for outstanding balances.

**Acceptance Criteria:**
- [ ] Player model has optional `collectionStatus` field: none, reminded, promised, overdue
- [ ] PlayerDetailView shows collection status badge if balance > 0
- [ ] "Mark as Reminded" button sets status and logs date
- [ ] "Mark as Promised" button with optional promised date
- [ ] "Mark as Overdue" button for delinquent accounts
- [ ] Collection status visible in Players list for players who owe
- [ ] Filter players list by collection status
- [ ] Project builds and runs in Simulator

#### US-062: Outstanding Balance Alerts
**Description:** As a bookie, I want to be alerted about players with high or aging balances.

**Acceptance Criteria:**
- [ ] Settings option to set balance threshold (e.g., $500)
- [ ] Settings option to set aging threshold (e.g., 7 days)
- [ ] Dashboard shows alert banner when any player exceeds thresholds
- [ ] Alert shows count: "3 players need attention"
- [ ] Tapping alert shows filtered list of flagged players
- [ ] Player row shows specific flag reason (high balance, aging, or both)
- [ ] Badge on Players tab when alerts exist
- [ ] Project builds and runs in Simulator

#### US-063: Bulk Settlement Processing
**Description:** As a bookie, I want to settle all graded bets at once.

**Acceptance Criteria:**
- [ ] GradingView has "Settle All Graded" button when graded bets exist
- [ ] Shows count of bets to settle
- [ ] Confirmation shows summary:
  - Total bets to settle
  - Total player winnings
  - Total player losses
  - Net impact
- [ ] Processes all settlements and creates ledger entries
- [ ] Success summary shows settled count
- [ ] Project builds and runs in Simulator

## Functional Requirements

- FR-1: Bookies can create, edit, and delete events with sport, league, teams, and start time
- FR-2: Bookies can add multiple markets to events with customizable odds
- FR-3: Mock data can be seeded for testing via Settings
- FR-4: Players browse games organized by sport with horizontal tab navigation
- FR-5: Players can search games by team name
- FR-6: Players can filter games by date range
- FR-7: Players can favorite teams for quick access
- FR-8: Bet slip persists selections across navigation
- FR-9: Players can build multi-selection (parlay) bets
- FR-10: Quick-pick stake amounts speed up bet entry
- FR-11: Players see comprehensive account summary with balance and stats
- FR-12: Players can view transaction history filtered by type
- FR-13: Players can view bet history filtered by status
- FR-14: Dark theme applied consistently throughout the app
- FR-15: Visual styling matches premium sportsbook aesthetic
- FR-16: Subtle animations enhance UX without slowing interactions
- FR-17: Player model supports username/password for future auth
- FR-18: Bookies can grade all bets for an event in one action
- FR-19: Settled bets can be reversed with full audit trail
- FR-20: Payments can be recorded with method and direction
- FR-21: Weekly settlement summaries show net positions
- FR-22: Dashboard shows who owes whom at a glance
- FR-23: Collection status tracked per player (reminded, promised, overdue)
- FR-24: Alerts flag high or aging balances
- FR-25: Bulk settlement processes all graded bets at once

## Non-Goals

- No live API integration (future phase)
- No push notifications
- No real-time odds updates or WebSocket connections
- No actual authentication/session management (UI only)
- No player-to-player features or social elements
- No payment processing or real money handling
- No support for live in-play betting adjustments

## Technical Considerations

- Use `@AppStorage` for favorites and simple preferences
- Bet slip state should be an `@Observable` class in the environment
- Theme colors defined as static properties on a Theme struct for consistency
- Consider using `ViewModifier` for common card styling
- Parlay odds calculation: convert American to decimal, multiply, convert back
- Mock data service should be easily replaceable with API service later

## Design Considerations

- Reference popular sportsbooks (DraftKings, FanDuel, Caesars) for UX patterns
- Prioritize one-handed use for mobile betting
- Odds buttons should be large enough for easy tapping (44pt minimum)
- High contrast for readability in various lighting conditions
- Use SF Symbols where appropriate, custom icons sparingly

## Success Metrics

- Player can find and bet on a game in under 30 seconds
- Bet slip supports up to 10 selections without performance issues
- All views render correctly in dark mode
- Zero crashes during normal betting flow
- App remains responsive during navigation and animations
- Bookie can grade all bets for an event in under 1 minute
- Bookie can see outstanding balances within 2 taps from dashboard
- Settlement reversal maintains full audit trail
- Weekly settlement summary accurately reflects all activity

## Open Questions

- Should we support landscape orientation for tablets?
- What team abbreviations/logos to use (placeholder for now)?
- Should parlays have a minimum number of selections (typically 2)?
- Do we want sound effects for bet confirmation?
