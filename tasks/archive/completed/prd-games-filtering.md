# PRD: Games Filtering & Historical Data Management

## Problem Statement

The Games view currently shows all events including ones that finished days ago. This clutters the UI and makes it hard to find upcoming games. However, we can't delete old events because bets reference them for historical tracking.

## Goals

1. Show only relevant games in the main Games view (upcoming + recently finished)
2. Preserve all historical data for bet history and reporting
3. Provide access to past events when needed (e.g., viewing bet details)

## User Stories

### US-001: Filter GamesView to show upcoming and recent events
**As a bookie**, I want to see only upcoming games and recently finished games so I can focus on active betting.

**Acceptance Criteria:**
- GamesView shows events where:
  - Status is NOT 'final' (upcoming/live games), OR
  - Status IS 'final' AND finished within last 48 hours
- Events sorted by start_time ascending (soonest first)
- Old finished events are hidden but NOT deleted
- Typecheck passes

### US-002: Add "Past Events" section or toggle
**As a bookie**, I want to optionally view past events so I can review historical games.

**Acceptance Criteria:**
- Add toggle or segmented control: "Upcoming" | "Past"
- "Upcoming" (default): Shows events per US-001 filter
- "Past": Shows events that are 'final' and older than 48 hours
- Past events sorted by start_time descending (most recent first)
- Typecheck passes

### US-003: Event details accessible from bet history
**As a user**, I want to see event details when viewing a historical bet so I can understand the context.

**Acceptance Criteria:**
- BetDetailView or bet rows show event info (teams, final score) even for old events
- No broken UI if event data exists
- Typecheck passes

### US-004: Player GamesView filtering
**As a player**, I want to see only upcoming games I can bet on.

**Acceptance Criteria:**
- Player's game browsing view shows only events where:
  - Status is 'open' or 'scheduled' (can still bet)
  - Start time is in the future
- Finished or locked events hidden from player betting view
- Typecheck passes

## Technical Notes

- All filtering happens at the SwiftData query level (predicates)
- No database changes needed - events stay in DB forever
- SyncService continues to download all events (no change)
- Filtering is UI-only

## Out of Scope

- Automatic deletion/archival of old events
- Database-level cleanup jobs
- Pagination for very large event lists (future consideration)
