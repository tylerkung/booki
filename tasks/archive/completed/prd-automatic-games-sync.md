# Automatic Games Sync

## Overview
Games should be automatically available to all bookies and players without any manual import or sync actions. The server handles all game data management.

## Current State (Problem)
- Bookies must manually import games from the Odds API via the app
- Imported games are stored locally first, then require manual sync to Supabase
- Players can only see games that their bookie has imported and synced
- `external_id` often missing from Supabase because sync wasn't triggered
- Auto-refresh can't work without `external_id` in the database

## Desired State (Solution)
- Server automatically fetches and stores games from the Odds API
- All games are shared (bookie_id = NULL) and visible to everyone
- iOS app simply downloads games from Supabase - no API calls needed
- Auto-refresh updates odds and scores automatically
- Zero manual intervention required from bookies or players

## Architecture

### Server-Side (Edge Functions)
1. **`sync_games` Edge Function** (new)
   - Fetches upcoming games from Odds API for configured sports
   - Upserts games into `events` table with `external_id`
   - Creates/updates markets for each game
   - Runs on schedule (cron) or on-demand

2. **`auto_refresh_games` Edge Function** (existing)
   - Already fetches scores and updates odds
   - Will work properly once games have `external_id`

### Client-Side (iOS App)
1. Remove manual import functionality (or make it admin-only)
2. App downloads games from Supabase on sync
3. No Odds API calls from the client

### Database
- All games stored with `bookie_id = NULL` (shared)
- `external_id` always populated for API-sourced games
- Markets linked to events

## User Stories

### US-001: Create sync_games Edge Function
Create a new edge function that fetches games from the Odds API and stores them in Supabase.

**Acceptance Criteria:**
- Function fetches upcoming games for configured sports (NBA, NFL, MLB, NHL)
- Games upserted to `events` table with `external_id` populated
- Markets created for each game (moneyline, spread, totals)
- Existing games updated (odds refreshed), new games inserted
- Games with `bookie_id = NULL` (shared across all bookies)
- Function can be called via HTTP or cron
- Typecheck passes

### US-002: Schedule automatic game sync
Set up cron job to run sync_games automatically.

**Acceptance Criteria:**
- Cron job runs sync_games twice daily (9 AM PT, 5 PM PT)
- Separate from auto_refresh_games (which handles scores)
- Logs success/failure for monitoring
- SQL migration provided for cron setup

### US-003: iOS app downloads games from Supabase
Modify iOS sync to download shared games instead of requiring manual import.

**Acceptance Criteria:**
- SyncService downloads events where `bookie_id IS NULL`
- Games appear in GamesView without any manual import
- Markets downloaded along with events
- Existing local-only events preserved (if any)
- Typecheck passes

### US-007: Move manual tools to Debug section
Keep manual tools available as a fallback for bookies if automatic sync fails.

**Acceptance Criteria:**
- Create "Debug Tools" section at bottom of SettingsView
- Move Import Games button to Debug section
- Move manual Sync button to Debug section
- Add "Trigger Game Sync" button that calls sync_games edge function
- Debug section styled as secondary/less prominent
- Main app flow works without touching Debug section
- Typecheck passes

### US-005: Verify end-to-end flow
Ensure the complete flow works: server fetches → Supabase stores → iOS downloads → users see games.

**Acceptance Criteria:**
- Fresh install shows games without any user action
- Players see same games as bookies
- Games have betting lines (markets) available
- Auto-refresh updates scores when games finish
- Bets can be placed on server-synced games

## Configuration

### Sports to Sync
Initial list (can be expanded):
- `basketball_nba` - NBA
- `americanfootball_nfl` - NFL
- `baseball_mlb` - MLB
- `icehockey_nhl` - NHL

### Sync Schedule
- **sync_games**: 9 AM PT, 5 PM PT (fetch new games, update odds)
- **auto_refresh_games**: 9 AM PT, 1 PM PT (fetch scores, grade bets)

### API Quota Considerations
- Odds API free tier: 500 requests/month
- Each sport = 1 API call
- 4 sports × 2 times/day × 30 days = 240 calls for sync_games
- Leave room for auto_refresh_games calls

## Migration Path
1. Deploy sync_games edge function
2. Run sync_games manually to populate initial games
3. Set up cron schedule
4. Deploy iOS update that removes manual import
5. Users get automatic games on next app launch

## Out of Scope
- Admin UI to configure which sports to sync
- Real-time odds streaming (WebSocket)
- Historical game data backfill
- Custom bookmaker selection per bookie
