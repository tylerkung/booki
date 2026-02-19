# PRD: Games Availability States

## Introduction

Handle edge cases in the Player's Games view for games that are no longer available for betting. Games without odds/lines should appear grayed out with an explanation, while games whose start time has passed should be removed from the list in real-time. This improves the player experience by clearly communicating why certain games can't be bet on.

## Goals

- Show games with no lines as grayed out with "No lines available" message
- Remove games from the list in real-time when their start time passes
- Apply these rules to the Player's Games view only
- Maintain a clean, uncluttered betting interface

## User Stories

### US-001: Gray out games with no available lines
**Description:** As a player, I want to see games without betting lines displayed as grayed out so I understand why I can't bet on them.

**Acceptance Criteria:**
- [ ] Games with no markets (empty markets array or all markets have nil odds) appear grayed out
- [ ] Grayed out games show "No lines available" text overlay or badge
- [ ] Grayed out games are not tappable / cannot open bet slip
- [ ] Grayed out games appear at the bottom of their section (after bettable games)
- [ ] Uses Theme colors for disabled/grayed state
- [ ] Typecheck passes

### US-002: Real-time removal of started games
**Description:** As a player, I want games to disappear from the list the moment they start so I only see games I can actually bet on.

**Acceptance Criteria:**
- [ ] Games where `startTime <= now` are filtered out of the Games list
- [ ] Filtering updates in real-time (use Timer or similar mechanism)
- [ ] No visual flicker or jarring transitions when games disappear
- [ ] Works correctly across time zones (compare UTC times)
- [ ] Typecheck passes

### US-003: Combine filters in GamesView
**Description:** As a developer, I need the GamesView to apply both availability filters so the list shows the correct games.

**Acceptance Criteria:**
- [ ] GamesView filters out games where start time has passed
- [ ] GamesView identifies games with no lines and passes flag to card component
- [ ] Filter logic is efficient (doesn't cause UI lag with many games)
- [ ] Typecheck passes

## Functional Requirements

- FR-1: A game is considered "no lines available" when it has no markets OR all its markets have nil/zero odds for both sides
- FR-2: A game is considered "started" when `startTime <= Date()`
- FR-3: Started games must be removed from the Player's Games view (not just disabled)
- FR-4: Games with no lines must be visually distinct (grayed out) and non-interactive
- FR-5: The real-time check for started games should run at least every 30 seconds
- FR-6: Grayed out games should sort to the bottom of their league/sport section

## Non-Goals

- No changes to Bookie's Events view (they may need to see all games for management)
- No "unavailable games" counter or section
- No notification when a game becomes unavailable
- No caching or persistence of availability state

## Technical Considerations

- **Timer for real-time updates:** Use a SwiftUI Timer or `onReceive` with a time publisher to trigger re-evaluation of the games list
- **Existing components:** Modify `GameCard` (or equivalent) to accept an `isDisabled` or `hasNoLines` flag
- **Theme colors:** Use `Theme.textSecondary` or create a new `Theme.disabled` color for grayed state
- **Performance:** Filter logic should be O(n) - simple pass through the events array

## Success Metrics

- Players never see a game they can't bet on without clear indication why
- No player confusion about why a game is grayed out
- Games disappear smoothly when they start (no stuck/stale games)

## Open Questions

- Should grayed out games show their start time still? (Likely yes, for context)
- What opacity level looks best for the grayed state? (Suggest 0.5)
