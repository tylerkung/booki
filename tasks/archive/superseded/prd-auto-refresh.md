# PRD: Automatic Server-Side Odds & Score Refresh

## Introduction

Implement a minimal automatic refresh system that keeps Booki feeling alive without manual intervention. The system runs entirely server-side via Supabase Edge Functions, refreshing odds and scores twice per day for a small, fixed set of games. This conservative approach guarantees API usage stays well under the 500 requests/month free tier limit.

Design principle: **Predictable > Fresh**

## Goals

- Automatically refresh odds and scores twice daily without bookie intervention
- Keep API usage under 300 requests/month (well within 500 limit)
- Automatically mark events as final when games complete
- Automatically transition accepted bets to "ready to grade" when events finalize
- Maintain full audit trail of all automatic actions
- Require zero client-side API calls for automatic updates

## User Stories

### US-001: Create Supabase migration for auto-refresh fields
**Description:** As a developer, I need database fields to track automatic refresh timestamps.

**Acceptance Criteria:**
- [ ] Add `last_auto_odds_refresh` (timestamptz, nullable) to events table
- [ ] Add `last_auto_score_refresh` (timestamptz, nullable) to events table
- [ ] Migration file created in `supabase/migrations/`
- [ ] Document migration in `SUPABASE_MIGRATIONS.md`
- [ ] Typecheck passes

### US-002: Create auto_refresh_games Edge Function
**Description:** As a system, I need an Edge Function that refreshes odds and scores for qualifying games.

**Acceptance Criteria:**
- [ ] Create `supabase/functions/auto_refresh_games/index.ts`
- [ ] Function reads `ODDS_API_KEY` from environment variables
- [ ] Function selects up to 2 qualifying games (has accepted bet, not locked, not final, ordered by start time)
- [ ] Function fetches odds from Odds API for each game (if start time not passed)
- [ ] Function fetches scores from Odds API for each game
- [ ] Function updates events table with new odds/scores in a transaction
- [ ] Function marks events as `final` when scores indicate completion
- [ ] Function updates accepted bets to `readyToGrade` when event finalizes
- [ ] Function emits audit events for all actions (`odds_refreshed_auto`, `score_refreshed_auto`, `event_finalized_auto`)
- [ ] Function uses idempotency key based on date + window to prevent duplicate runs
- [ ] Function returns summary of actions taken
- [ ] Typecheck passes (Deno)

### US-003: Configure cron triggers for auto refresh
**Description:** As a system, I need the auto_refresh_games function to run automatically twice per day.

**Acceptance Criteria:**
- [ ] Create cron job configuration for 09:00 PT (17:00 UTC)
- [ ] Create cron job configuration for 13:00 PT (21:00 UTC)
- [ ] Cron triggers call `auto_refresh_games` Edge Function
- [ ] Document cron setup in `SUPABASE_MIGRATIONS.md`
- [ ] Typecheck passes

### US-004: Add audit event types for automatic refresh
**Description:** As a bookie, I want to see when automatic refreshes occurred in the audit trail.

**Acceptance Criteria:**
- [ ] Add `odds_refreshed_auto` action type support in audit helper
- [ ] Add `score_refreshed_auto` action type support in audit helper
- [ ] Add `event_finalized_auto` action type support in audit helper
- [ ] Add `auto_refresh_failed` action type for error logging
- [ ] Typecheck passes

### US-005: Display last auto-refresh timestamp in Events UI
**Description:** As a bookie, I want to see when odds/scores were last automatically updated.

**Acceptance Criteria:**
- [ ] EventDetailView shows "Last auto-refresh: [timestamp]" when available
- [ ] Timestamp displays in relative format (e.g., "2 hours ago")
- [ ] Shows "Never" if no auto-refresh has occurred
- [ ] Uses Theme styling
- [ ] Typecheck passes

### US-006: Handle API errors gracefully in auto refresh
**Description:** As a system, I need to handle API failures without causing cascading issues.

**Acceptance Criteria:**
- [ ] If Odds API returns error, log error and emit `auto_refresh_failed` audit event
- [ ] Do NOT retry automatically within same window
- [ ] Continue processing other games if one fails
- [ ] Next scheduled window will attempt recovery
- [ ] Function completes successfully even if individual refreshes fail
- [ ] Typecheck passes

## Functional Requirements

- FR-1: Edge Function `auto_refresh_games` selects up to 2 games per run based on: has accepted bet, not locked, status != final, ordered by closest start time, then highest total wagered amount as tie-breaker
- FR-2: Odds refresh only occurs if event start time has not passed and event is not locked
- FR-3: Score refresh occurs for all selected games regardless of start time
- FR-4: When scores indicate game is complete, event status is set to `final` and `finalScore` is populated
- FR-5: When event becomes final, all accepted bets for that event are updated to `readyToGrade` status
- FR-6: All automatic actions emit audit events with `actor_user_id` set to NULL (system action)
- FR-7: Idempotency key format: `auto_refresh_{YYYY-MM-DD}_{window}` where window is "morning" or "afternoon"
- FR-8: Cron runs at 09:00 PT and 13:00 PT daily (17:00 UTC and 21:00 UTC)
- FR-9: API key is read from Supabase secrets (`ODDS_API_KEY` environment variable)
- FR-10: Manual sync remains available alongside automatic refresh

## Non-Goals (Out of Scope)

- Live betting or real-time score updates
- Per-event adaptive polling based on game state
- More than 2 refresh windows per day
- More than 2 games per refresh window
- Client-side API calls for automatic updates
- Per-bookie refresh schedules or API keys
- Automatic retry on failure within same window
- Push notifications for odds changes
- Background device fetching

## Technical Considerations

### API Usage Budget
- 2 refreshes/day × 2 games × 2 requests (odds + scores) = 8 requests/day
- 8 × 30 days = 240 requests/month
- Well under 500/month limit with buffer for manual tools

### Cron Configuration
Supabase cron uses `pg_cron` extension. Jobs defined in migration:
```sql
SELECT cron.schedule('auto-refresh-morning', '0 17 * * *', $$SELECT net.http_post(...)$$);
SELECT cron.schedule('auto-refresh-afternoon', '0 21 * * *', $$SELECT net.http_post(...)$$);
```

### Game Selection Query
```sql
SELECT e.* FROM events e
JOIN bets b ON b.event_id = e.id
WHERE b.status = 'accepted'
  AND e.locked_at IS NULL
  AND e.status != 'final'
GROUP BY e.id
ORDER BY e.start_time ASC, SUM(b.stake) DESC
LIMIT 2;
```

### Environment Variable Setup
```bash
supabase secrets set ODDS_API_KEY=your_api_key_here
```

## Success Metrics

- API usage remains under 300 requests/month
- Events update predictably twice per day
- Scores finalize without manual intervention
- No duplicate refreshes (idempotency works)
- Audit trail shows all automatic actions
- Zero client-side API calls for auto updates

## Open Questions

- Should we add a "pause auto-refresh" setting for bookies who want manual-only?
- Should finalized events trigger any notification to the bookie?
- What timezone should timestamps display in the UI? (Bookie's local vs PT)
