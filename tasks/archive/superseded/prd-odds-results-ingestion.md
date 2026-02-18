# PRD: Odds & Results Ingestion + Background Jobs

## Introduction

Integrate with a sports data API to automatically fetch odds and results for major US sports (NFL, NBA, MLB, NHL). This eliminates manual data entry for events and enables auto-grading of bets when games complete. Background jobs will keep data fresh and process results automatically.

## Goals

- Integrate with The Odds API (or similar reliable paid API)
- Auto-populate events with current odds (spread, moneyline, totals)
- Fetch final scores and auto-grade bets when games complete
- Run background jobs to keep odds fresh and check for results
- Support NFL, NBA, MLB, NHL initially

## Non-Goals

- Real-time live odds streaming (poll-based updates sufficient)
- International sports (soccer, etc.) - future expansion
- Custom/prop bets from API (focus on main markets)
- In-play/live betting odds updates

## User Stories

### Phase 1: API Integration + Odds Ingestion

#### US-001: Create Sports Data API Service
**Description:** As a developer, I need a service to communicate with The Odds API.

**Acceptance Criteria:**
- [ ] Create `OddsAPIService.swift` in Booki/Services/
- [ ] Add API key configuration in Info.plist (`ODDS_API_KEY`)
- [ ] Implement `fetchUpcomingEvents(sport:)` to get upcoming games
- [ ] Implement `fetchOdds(eventId:)` to get odds for a specific event
- [ ] Handle API errors gracefully (rate limits, invalid key, network errors)
- [ ] Parse response into local Swift structs
- [ ] Support sports: americanfootball_nfl, basketball_nba, baseball_mlb, icehockey_nhl
- [ ] Project builds and runs in Simulator

#### US-002: Create API Response Models
**Description:** As a developer, I need models to parse The Odds API responses.

**Acceptance Criteria:**
- [ ] Create `OddsAPIModels.swift` in Booki/Services/
- [ ] Create `APIEvent` struct: id, sport, commence_time, home_team, away_team
- [ ] Create `APIBookmaker` struct: key, title, markets
- [ ] Create `APIMarket` struct: key (h2h, spreads, totals), outcomes
- [ ] Create `APIOutcome` struct: name, price, point (for spreads/totals)
- [ ] All models conform to Codable
- [ ] Handle optional fields gracefully
- [ ] Project builds and runs in Simulator

#### US-003: Map API Events to Local Events
**Description:** As a developer, I need to convert API events to local Event models.

**Acceptance Criteria:**
- [ ] Create `OddsMapper.swift` in Booki/Services/
- [ ] Map API sport keys to local sport names (americanfootball_nfl → "NFL")
- [ ] Map API event to local Event model
- [ ] Map API odds to local Market model (spread, moneyline, total)
- [ ] Convert API odds format (decimal) to American odds
- [ ] Handle missing markets gracefully (not all events have all markets)
- [ ] Store API event ID in Event for future lookups
- [ ] Project builds and runs in Simulator

#### US-004: Create Fetch Events UI
**Description:** As a bookie, I want to fetch upcoming events from the API so I don't have to enter them manually.

**Acceptance Criteria:**
- [ ] Add "Fetch Events" button in GamesView or EventsListView
- [ ] Show sport picker (NFL, NBA, MLB, NHL)
- [ ] On tap: call OddsAPIService.fetchUpcomingEvents()
- [ ] Show loading state during fetch
- [ ] Display preview of events to import (with checkboxes)
- [ ] "Import Selected" creates Event records in SwiftData
- [ ] Skip events that already exist (match by API event ID)
- [ ] Show success/error feedback
- [ ] Use Theme styling
- [ ] Project builds and runs in Simulator

#### US-005: Auto-Create Markets from Odds
**Description:** As a bookie, I want imported events to have markets pre-populated with current odds.

**Acceptance Criteria:**
- [ ] When importing event, also create Market records
- [ ] Create spread market with home/away lines and odds
- [ ] Create moneyline market with home/away odds
- [ ] Create total market with over/under line and odds
- [ ] Link markets to event
- [ ] Handle events with missing markets (not all have totals)
- [ ] Project builds and runs in Simulator

### Phase 2: Results Ingestion + Auto-Grading

#### US-006: Fetch Event Results
**Description:** As a developer, I need to fetch final scores for completed events.

**Acceptance Criteria:**
- [ ] Add `fetchResults(eventId:)` to OddsAPIService (or use scores endpoint)
- [ ] Create `APIScore` model: home_score, away_score, completed
- [ ] Handle events not yet completed (return nil/pending)
- [ ] Store final score on Event model when fetched
- [ ] Update event status to .final when score received
- [ ] Project builds and runs in Simulator

#### US-007: Auto-Grade Bets from Results
**Description:** As a bookie, I want bets to be automatically graded when results come in.

**Acceptance Criteria:**
- [ ] Create `AutoGradingService.swift` in Booki/Services/
- [ ] Given final score, determine bet outcomes (win/loss/push)
- [ ] For spread bets: compare margin to spread line
- [ ] For moneyline bets: winner takes it
- [ ] For total bets: compare combined score to total line
- [ ] Use existing GradingService to apply grades
- [ ] Handle push scenarios (exact spread/total hits)
- [ ] Create ledger entries for settled bets
- [ ] Project builds and runs in Simulator

#### US-008: Check Results UI
**Description:** As a bookie, I want to check for results and auto-grade pending bets.

**Acceptance Criteria:**
- [ ] Add "Check Results" button in GradingView
- [ ] Find all events with status .final or past start_time
- [ ] For each: fetch results from API
- [ ] If results available: auto-grade all bets on that event
- [ ] Show summary: "Graded X bets across Y events"
- [ ] Handle errors gracefully
- [ ] Use Theme styling
- [ ] Project builds and runs in Simulator

### Phase 3: Background Jobs + Scheduling

#### US-009: Create Background Job Scheduler
**Description:** As a developer, I need a system to run periodic background tasks.

**Acceptance Criteria:**
- [ ] Create `BackgroundJobService.swift` in Booki/Services/
- [ ] Use BGAppRefreshTask for periodic background execution
- [ ] Register background task in BookiApp.swift
- [ ] Schedule refresh every 15 minutes when app is backgrounded
- [ ] Track last run time for each job type
- [ ] Handle iOS background execution limits gracefully
- [ ] Project builds and runs in Simulator

#### US-010: Background Odds Refresh
**Description:** As a bookie, I want odds to refresh automatically in the background.

**Acceptance Criteria:**
- [ ] Create "refresh odds" background job
- [ ] Fetch updated odds for events starting in next 24 hours
- [ ] Update existing Market records with new odds
- [ ] Don't update odds for events that have started
- [ ] Log refresh results for debugging
- [ ] Respect API rate limits
- [ ] Project builds and runs in Simulator

#### US-011: Background Results Check
**Description:** As a bookie, I want results to be checked automatically in the background.

**Acceptance Criteria:**
- [ ] Create "check results" background job
- [ ] Find events past their start time without final scores
- [ ] Fetch results from API
- [ ] Auto-grade bets when results received
- [ ] Send local notification: "X bets auto-graded"
- [ ] Log results for debugging
- [ ] Project builds and runs in Simulator

#### US-012: Background Job Settings
**Description:** As a bookie, I want to configure background job behavior.

**Acceptance Criteria:**
- [ ] Add "Auto-Refresh" section in SettingsView
- [ ] Toggle: "Auto-refresh odds" (on/off)
- [ ] Toggle: "Auto-grade bets" (on/off)
- [ ] Picker: "Refresh frequency" (15min, 30min, 1hr)
- [ ] Show last refresh time
- [ ] Show API usage stats (calls remaining)
- [ ] Store settings in UserDefaults
- [ ] Use Theme styling
- [ ] Project builds and runs in Simulator

## Functional Requirements

- FR-1: Integrate with The Odds API for odds and results data
- FR-2: Support NFL, NBA, MLB, NHL sports
- FR-3: Convert decimal odds to American odds format
- FR-4: Import events with pre-populated markets (spread, ML, total)
- FR-5: Fetch final scores and auto-grade bets
- FR-6: Background jobs refresh odds and check results periodically
- FR-7: Configurable background job settings

## Technical Considerations

- **API Key Security**: Store in Info.plist, don't commit to git
- **Rate Limits**: The Odds API has monthly request limits, track usage
- **Background Execution**: iOS limits background time, prioritize critical tasks
- **Odds Format**: API returns decimal, app uses American - need conversion
- **Event Matching**: Use API event ID to prevent duplicate imports
- **Timezone Handling**: API times are UTC, convert to local for display

## API Reference

The Odds API (https://the-odds-api.com/):
- `GET /v4/sports/{sport}/odds` - Get upcoming events with odds
- `GET /v4/sports/{sport}/scores` - Get scores for recent events
- Sports keys: `americanfootball_nfl`, `basketball_nba`, `baseball_mlb`, `icehockey_nhl`
- Markets: `h2h` (moneyline), `spreads`, `totals`

## Success Metrics

- Bookie can import a week's events in under 30 seconds
- 95% of bets auto-grade correctly when results available
- Background refresh keeps odds within 30 minutes of current
- API usage stays within plan limits

## Open Questions

- Should we support multiple bookmakers' odds or just one (consensus)?
- How to handle postponed/cancelled games?
- Should auto-grading require bookie confirmation or be fully automatic?
- What happens if API is down during background job?
