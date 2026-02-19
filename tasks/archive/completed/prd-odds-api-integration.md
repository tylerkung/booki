# PRD: The Odds API Integration

## Introduction

Integrate The Odds API to automatically fetch sporting events, betting lines, and scores. This replaces manual event creation and enables auto-grading of bets based on final scores. The integration will populate the Games tab with real odds from major sportsbooks and keep lines updated.

**API Documentation:** https://the-odds-api.com/liveapi/guides/v4/

## Goals

- Fetch live and upcoming events from The Odds API
- Import spread, moneyline, and total markets with accurate odds
- Auto-update odds periodically to reflect line movements
- Fetch scores to enable automatic bet grading
- Track API usage to stay within quota limits
- Store API key securely (not in code)

## User Stories

### US-001: Create OddsAPIService
**Description:** As a developer, I need a service to communicate with The Odds API.

**Acceptance Criteria:**
- [ ] Create `OddsAPIService.swift` in `Booki/Services/`
- [ ] Base URL: `https://api.the-odds-api.com`
- [ ] Store API key in environment or secure storage (not hardcoded)
- [ ] Implement request method with proper headers and error handling
- [ ] Parse `x-requests-remaining` header to track quota
- [ ] Handle common errors: 401 (invalid key), 429 (rate limit), 500 (server error)
- [ ] Typecheck passes

### US-002: Fetch Available Sports
**Description:** As a bookie, I want to see which sports are available so I can choose what to offer.

**Acceptance Criteria:**
- [ ] Implement `GET /v4/sports/` endpoint
- [ ] Create `OddsSport` model matching API response: `key`, `group`, `title`, `description`, `active`, `hasOutrights`
- [ ] Filter to only active sports (`active: true`)
- [ ] Cache sports list locally (doesn't count against quota)
- [ ] Map sport keys to display names (e.g., `americanfootball_nfl` → "NFL")
- [ ] Typecheck passes

### US-003: Fetch Events with Odds
**Description:** As a bookie, I want to import events with betting lines from the API.

**Acceptance Criteria:**
- [ ] Implement `GET /v4/sports/{sport}/odds/` endpoint
- [ ] Parameters: `regions=us`, `markets=h2h,spreads,totals`, `oddsFormat=american`
- [ ] Create `OddsEvent` model: `id`, `sportKey`, `sportTitle`, `commenceTime`, `homeTeam`, `awayTeam`, `bookmakers`
- [ ] Create `OddsBookmaker` model: `key`, `title`, `lastUpdate`, `markets`
- [ ] Create `OddsMarket` model: `key`, `lastUpdate`, `outcomes` (with `name`, `price`, `point`)
- [ ] Use a single preferred bookmaker (configurable, default: `draftkings`)
- [ ] Typecheck passes

### US-004: Map API Events to App Models
**Description:** As a developer, I need to convert API responses to the app's Event and Market models.

**Acceptance Criteria:**
- [ ] Create `OddsAPIMapper` to convert `OddsEvent` → `Event`
- [ ] Map `commenceTime` → `startTime`
- [ ] Map `homeTeam`/`awayTeam` → `homeTeam`/`awayTeam`
- [ ] Map `sportKey` → `sport` and `league` (e.g., `americanfootball_nfl` → sport: "Football", league: "NFL")
- [ ] Convert `OddsMarket` outcomes to `Market` model with proper `sideA`/`sideB` labels
- [ ] Handle missing markets gracefully (some events may not have spreads)
- [ ] Set `event.externalId` to store the API event ID for updates
- [ ] Typecheck passes

### US-005: Add External ID to Event Model
**Description:** As a developer, I need to track which events came from the API for updates.

**Acceptance Criteria:**
- [ ] Add `externalId: String?` field to Event model
- [ ] Add `externalSource: String?` field (e.g., "the-odds-api")
- [ ] Add `lastOddsUpdate: Date?` field to track freshness
- [ ] Update Event initializer with new optional fields
- [ ] Typecheck passes

**Supabase Migration:**
```sql
ALTER TABLE events
ADD COLUMN IF NOT EXISTS external_id TEXT,
ADD COLUMN IF NOT EXISTS external_source TEXT,
ADD COLUMN IF NOT EXISTS last_odds_update TIMESTAMPTZ;
```

### US-006: Import Events UI
**Description:** As a bookie, I want a button to import events from the API.

**Acceptance Criteria:**
- [ ] Add "Import Events" button to EventsListView (or a new admin section)
- [ ] Show sport picker (from US-002 sports list)
- [ ] Show loading indicator during fetch
- [ ] Display count of events imported: "Imported 12 NFL games"
- [ ] Skip events that already exist (match by `externalId`)
- [ ] Show error alert if API call fails
- [ ] Typecheck passes

### US-007: Fetch Scores for Grading
**Description:** As a bookie, I want to fetch final scores to auto-grade bets.

**Acceptance Criteria:**
- [ ] Implement `GET /v4/sports/{sport}/scores/` endpoint
- [ ] Create `OddsScore` model: `id`, `sportKey`, `commenceTime`, `completed`, `homeTeam`, `awayTeam`, `scores` array
- [ ] Scores array contains: `name` (team), `score` (points)
- [ ] Only fetch for events with `completed: true`
- [ ] Parameter `daysFrom=1` to get recent completions
- [ ] Typecheck passes

### US-008: Auto-Grade Bets from Scores
**Description:** As a bookie, I want bets to be graded automatically when scores are available.

**Acceptance Criteria:**
- [ ] Match scores to events by `externalId`
- [ ] Update event with final scores: `homeScore`, `awayScore`
- [ ] Mark event status as `.completed`
- [ ] Trigger existing `GradingService` to grade bets for completed events
- [ ] Log grading results for audit
- [ ] Handle edge cases: postponed games, missing scores
- [ ] Typecheck passes

### US-009: Add Score Fields to Event Model
**Description:** As a developer, I need to store final scores on events.

**Acceptance Criteria:**
- [ ] Add `homeScore: Int?` field to Event model
- [ ] Add `awayScore: Int?` field to Event model
- [ ] Update Event initializer with new optional fields
- [ ] Typecheck passes

**Supabase Migration:**
```sql
ALTER TABLE events
ADD COLUMN IF NOT EXISTS home_score INTEGER,
ADD COLUMN IF NOT EXISTS away_score INTEGER;
```

### US-010: API Settings Screen
**Description:** As a bookie, I want to configure my API key and preferences.

**Acceptance Criteria:**
- [ ] Add "Odds API" section to SettingsView
- [ ] Secure text field for API key (stored in Keychain)
- [ ] Dropdown to select preferred bookmaker (DraftKings, FanDuel, BetMGM, etc.)
- [ ] Dropdown to select region (US, UK, EU, AU)
- [ ] Display current quota: "API Calls: 450/500 remaining"
- [ ] "Test Connection" button to validate API key
- [ ] Typecheck passes

### US-011: Store API Key Securely
**Description:** As a developer, I need to store the API key securely using Keychain.

**Acceptance Criteria:**
- [ ] Create `KeychainService.swift` for secure storage
- [ ] Methods: `save(key:value:)`, `get(key:)`, `delete(key:)`
- [ ] Store API key with key `"odds-api-key"`
- [ ] Never log or print the API key
- [ ] Typecheck passes

### US-012: Refresh Odds Periodically
**Description:** As a bookie, I want odds to stay current with line movements.

**Acceptance Criteria:**
- [ ] Add "Refresh Odds" button to GamesView
- [ ] Update existing events' markets with latest odds from API
- [ ] Only refresh events starting within next 24 hours (save API calls)
- [ ] Update `lastOddsUpdate` timestamp on refresh
- [ ] Show "Last updated: 5 min ago" indicator
- [ ] Typecheck passes

### US-013: Quota Tracking
**Description:** As a bookie, I want to see my API usage so I don't exceed limits.

**Acceptance Criteria:**
- [ ] Store quota info from response headers: `x-requests-remaining`, `x-requests-used`
- [ ] Persist quota locally (AppStorage or UserDefaults)
- [ ] Show warning when quota < 20%: "Low API quota - 95 calls remaining"
- [ ] Block API calls when quota = 0 with user-friendly message
- [ ] Quota resets monthly (show reset date if available)
- [ ] Typecheck passes

## Functional Requirements

- FR-1: OddsAPIService handles all API communication with proper error handling
- FR-2: API key stored in Keychain, never hardcoded or logged
- FR-3: Events imported from API are tagged with `externalId` and `externalSource`
- FR-4: Duplicate events (same `externalId`) are updated, not created again
- FR-5: Scores endpoint fetches completed games for auto-grading
- FR-6: GradingService uses final scores to determine spread/total/ML winners
- FR-7: Quota is tracked and displayed to prevent overages
- FR-8: User can configure preferred bookmaker and region

## Non-Goals

- No real-time WebSocket streaming (use polling)
- No player props (future enhancement)
- No futures/outrights markets initially
- No historical odds analysis
- No automated background refresh (manual trigger only for now)
- No odds comparison across multiple bookmakers (single source)

## Technical Considerations

### API Response Structure (Example)
```json
{
  "id": "e912304a-234b-5678-...",
  "sport_key": "basketball_nba",
  "sport_title": "NBA",
  "commence_time": "2026-01-25T00:00:00Z",
  "home_team": "Los Angeles Lakers",
  "away_team": "Boston Celtics",
  "bookmakers": [{
    "key": "draftkings",
    "title": "DraftKings",
    "markets": [{
      "key": "spreads",
      "outcomes": [
        {"name": "Los Angeles Lakers", "price": -110, "point": -3.5},
        {"name": "Boston Celtics", "price": -110, "point": 3.5}
      ]
    }]
  }]
}
```

### Sport Key Mapping
| API Key | Sport | League |
|---------|-------|--------|
| `americanfootball_nfl` | Football | NFL |
| `americanfootball_ncaaf` | Football | NCAAF |
| `basketball_nba` | Basketball | NBA |
| `basketball_ncaab` | Basketball | NCAAB |
| `baseball_mlb` | Baseball | MLB |
| `icehockey_nhl` | Hockey | NHL |
| `soccer_epl` | Soccer | EPL |
| `soccer_usa_mls` | Soccer | MLS |

### Quota Costs
| Endpoint | Cost |
|----------|------|
| `/sports/` | Free |
| `/events/` | Free |
| `/odds/` | 1 credit per market × region |
| `/scores/` | 1-2 credits |
| `/historical/` | 10 credits |

### Keychain Storage Keys
- `odds-api-key`: The Odds API key
- `odds-api-bookmaker`: Preferred bookmaker (default: draftkings)
- `odds-api-region`: Region (default: us)

## Supabase Migrations

Add to `SUPABASE_MIGRATIONS.md`:

```sql
-- The Odds API Integration
ALTER TABLE events
ADD COLUMN IF NOT EXISTS external_id TEXT,
ADD COLUMN IF NOT EXISTS external_source TEXT,
ADD COLUMN IF NOT EXISTS last_odds_update TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS home_score INTEGER,
ADD COLUMN IF NOT EXISTS away_score INTEGER;

-- Index for faster lookups by external_id
CREATE INDEX IF NOT EXISTS idx_events_external_id ON events(external_id);
```

## Success Metrics

- Events can be imported in under 5 seconds
- Imported events display correctly in GamesView
- Auto-grading works for 95%+ of completed events
- API quota stays under limit with typical usage
- No API key exposure in logs or code

## Open Questions

- Should we support multiple bookmakers for odds comparison?
- What's the refresh frequency that balances freshness vs quota?
- Should we auto-import events on a schedule or always manual?
- How to handle API downtime gracefully?
