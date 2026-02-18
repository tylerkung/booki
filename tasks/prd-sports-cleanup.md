# PRD: Sports & UI Cleanup

## Introduction

Clean up the sports selection, remove legacy UI elements, and improve the player experience. This includes fixing sports availability to show only active leagues, removing the Upcoming/Past toggle, removing dev test mode, and converting the player Settings tab to an Account tab.

## Goals

- Show only sports with active games (NBA, NFL, MLB, NCAAB, NCAAF, NHL as the standard 6)
- Simplify the games view by removing the Past games filter
- Remove development test mode toggle from production
- Give players a dedicated Account tab with profile info and preferences

## User Stories

### US-001: Update supported sports list to standard 6
**Description:** As a bookie, I want to see all major sports leagues so I can import games from any active league.

**Acceptance Criteria:**
- [ ] Supported sports list includes: NBA, NFL, MLB, NCAAB, NCAAF, NHL
- [ ] Sports are mapped to correct Odds API sport keys (basketball_nba, americanfootball_nfl, baseball_mlb, basketball_ncaab, americanfootball_ncaaf, icehockey_nhl)
- [ ] Typecheck passes

### US-002: Filter sports to only show those with active games
**Description:** As a bookie, I want to only see sports that have upcoming games so I don't try to import from inactive leagues.

**Acceptance Criteria:**
- [ ] Before showing sport selection, check which sports have upcoming games via Odds API
- [ ] Only display sports that return at least 1 upcoming event
- [ ] Show loading indicator while checking sport availability
- [ ] If no sports have games, show appropriate empty state message
- [ ] Cache sport availability for reasonable duration (e.g., 1 hour) to avoid excessive API calls
- [ ] Typecheck passes
- [ ] Verify in browser/simulator

### US-003: Remove Upcoming/Past games toggle
**Description:** As a bookie, I only need to see upcoming games since past games are handled through grading.

**Acceptance Criteria:**
- [ ] Remove the Upcoming/Past segmented control from GamesView
- [ ] Default to showing only upcoming games
- [ ] Remove any code related to fetching/displaying past games in the games list
- [ ] Past games still accessible through GradingView for score fetching
- [ ] Typecheck passes
- [ ] Verify in browser/simulator

### US-004: Remove player/bookie mode toggle from Settings
**Description:** As a developer preparing for production, I need to remove the test mode toggle that allows switching between player and bookie views.

**Acceptance Criteria:**
- [ ] Remove "Test Mode" section from SettingsView
- [ ] Remove `isPlayerMode` @AppStorage property
- [ ] Remove `selectedPlayerID` @AppStorage property
- [ ] Remove any related state management code
- [ ] App routing based solely on authenticated user role (bookie vs player)
- [ ] Typecheck passes

### US-005: Create Account tab for player view
**Description:** As a player, I want an Account tab instead of Settings so I can manage my profile and preferences.

**Acceptance Criteria:**
- [ ] Rename Settings tab to "Account" in player's tab bar
- [ ] Change tab icon to person.circle or similar account icon
- [ ] Typecheck passes
- [ ] Verify in browser/simulator

### US-006: Build Account view with profile section
**Description:** As a player, I want to see my profile information in the Account tab.

**Acceptance Criteria:**
- [ ] Display player's name
- [ ] Display player's email
- [ ] Display which bookie they're connected to (bookie name)
- [ ] Show when account was created (member since date)
- [ ] Use existing Theme styling (cardBackground, textPrimary, textSecondary)
- [ ] Typecheck passes
- [ ] Verify in browser/simulator

### US-007: Add preferences section to Account view
**Description:** As a player, I want to manage my preferences in the Account tab.

**Acceptance Criteria:**
- [ ] Add preferences section with appropriate settings for players
- [ ] Include notification preferences toggle (if applicable)
- [ ] Include any display preferences (odds format if supported)
- [ ] Preferences persist using @AppStorage
- [ ] Typecheck passes
- [ ] Verify in browser/simulator

### US-008: Add logout functionality to Account view
**Description:** As a player, I want to log out from the Account tab.

**Acceptance Criteria:**
- [ ] Logout button at bottom of Account view
- [ ] Button styled with DestructiveButtonStyle
- [ ] Confirmation alert before logging out ("Are you sure you want to log out?")
- [ ] On confirm, calls AuthManager.shared.signOut()
- [ ] Returns to login screen after logout
- [ ] Typecheck passes
- [ ] Verify in browser/simulator

## Functional Requirements

- FR-1: The app must support 6 sports: NBA, NFL, MLB, NCAAB, NCAAF, NHL
- FR-2: Sports selection must only show leagues with active upcoming games
- FR-3: Games view must only show upcoming games (no past games toggle)
- FR-4: Player/bookie mode switching must be removed entirely from codebase
- FR-5: Players must have an Account tab with profile, preferences, and logout
- FR-6: Account tab must display player name, email, connected bookie, and member since date

## Non-Goals (Out of Scope)

- Adding new sports beyond the standard 6
- Player profile editing (name/email changes)
- Push notification implementation (just the preference toggle)
- Password change functionality
- Account deletion

## Technical Considerations

- Odds API sport keys: `basketball_nba`, `americanfootball_nfl`, `baseball_mlb`, `basketball_ncaab`, `americanfootball_ncaaf`, `icehockey_nhl`
- Current OddsAPIService likely needs sport key mapping updates
- Sport availability check should use Odds API's sports endpoint or minimal odds call
- Consider caching sport availability to reduce API quota usage
- Player's connected bookie info available via Player.bookie relationship

## Success Metrics

- All 6 major sports accessible when in season
- No API calls wasted on out-of-season sports
- Clean separation between bookie and player experiences
- No test mode artifacts in production build

## Open Questions

- Should sport availability cache duration be configurable?
- What odds format options should be in player preferences (American, Decimal, Fractional)?
