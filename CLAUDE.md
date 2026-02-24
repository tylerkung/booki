# Booki - Development Guidelines

## Documentation Updates (Required)

**After completing any feature or significant change, update these files:**

1. **CLAUDE.md** (this file)
   - Update "Current State" section with date and branch
   - Add new sections for major features (e.g., new Edge Functions, architectural patterns)
   - Update "Key Files" if new important files were added

2. **README.md**
   - Add new phase section under "What's Been Implemented"
   - Update relevant sections (Edge Functions table, Database Schema, etc.)
   - Update "Last updated" line at the bottom

This keeps documentation in sync with the codebase for future development.

## PRD Guidelines

When creating PRDs for this project:
- **Always build on top of the existing codebase** - modify and extend, don't rebuild
- Maintain current styling and patterns unless explicitly told to change them
- Do not start from scratch unless explicitly requested
- Reference existing files to modify rather than creating new ones when possible

## Tech Stack
- iOS 17+ / Swift 5.9+ / SwiftUI
- SwiftData for local persistence + Supabase for cloud
- MVVM with Services layer

## Styling

- **Always use Theme.swift** for colors and styling - never use default iOS colors
- Dark sports-betting theme throughout
- Key Theme properties: `Theme.background`, `Theme.cardBackground`, `Theme.accent`, `Theme.textPrimary`, `Theme.textSecondary`, `Theme.success`, `Theme.danger`, `Theme.warning`

### Dark Theme Lists/Forms
```swift
List {
    Section { ... }
        .listRowBackground(Theme.cardBackground)
}
.scrollContentBackground(.hidden)
.background(Theme.background)
```

## Balance Display Convention

- **Internal (BalanceService)**: positive = player owes bookie, negative = bookie owes player
- **Player-facing display**: Negate the internal value so positive = credit (green), negative = debt (red)
- Bookie-facing views use internal convention directly (no negation)

## Key Files

- `ContentView.swift` - Main app structure, tab navigation
- `AuthGateView.swift` - Routes bookie vs player after login
- `Theme.swift` - All colors and styling constants
- `AuthManager.swift` - Login/logout and user role state
- `SyncService.swift` - Cloud sync coordinator
- `OddsAPIService.swift` - The Odds API communication (singleton)
- `OddsAPIMapper.swift` - Maps API responses to Event/Market models
- `EdgeFunctionService.swift` - Calls Supabase Edge Functions with retry logic
- `AgreementService.swift` - ToS acceptance checking and submission
- `AuditService.swift` - Fetches audit trail history

## Odds API Integration

- **Manual triggers only** - Import/Fetch/Refresh are manual to conserve API quota (500 free calls/month)
- **OddsAPIService.shared** - Singleton with @Published quota tracking
- **API key stored in @AppStorage** - Settings > Odds API section
- **Event.externalId** - Links imported events to API for score updates
- **Supabase migration required** - See SUPABASE_MIGRATIONS.md for events table columns

## Build & Test

- Xcode command line tools don't support full builds - use Xcode IDE
- Delete app from Simulator when SwiftData schema changes

## Edge Functions

All critical betting operations are server-authoritative via Supabase Edge Functions:

- **Location**: `supabase/functions/`
- **Shared helpers**: `_shared/cors.ts`, `_shared/supabase.ts`, `_shared/idempotency.ts`, `_shared/audit.ts`, `_shared/grading.ts`
- **Functions**: `submit_bet`, `accept_bet`, `grade_bet`, `settle_bet`, `adjust_balance`, `reverse_settlement`, `override_grade`, `auto_refresh_games`, `claim_player`
- **Deploy**: `npx supabase functions deploy <function-name> --no-verify-jwt --project-ref vstfauqufwpdytmvjyfz`
- **JWT note**: All functions deployed with `--no-verify-jwt` (Supabase gateway ES256 incompatibility). Function code still validates auth via `getUserIdFromAuthHeader` → `getUser()`.

All functions:
1. Validate JWT authorization (in function code, not gateway)
2. Check idempotency key (prevent duplicates)
3. Validate business rules
4. Emit audit events
5. Return cached response on duplicate requests

## Auto-Pilot Mode (Default)

Bets are auto-accepted and auto-graded by default:

- **Auto-accept**: `submit_bet` creates bets with status `'accepted'` immediately
- **Auto-grade + settle**: `auto_refresh_games` grades bets when events reach `'final'` status and immediately creates ledger entries (accepted → settled in one step)
- **Grading logic**: Moneyline (winner), Spread (point differential), Totals (over/under)
- **Opt-in manual modes**: Bookies can enable `manual_bet_acceptance` or `manual_bet_grading` in Settings

## Shared Events Architecture

Events/games are shared across all bookies (`bookie_id = NULL`):

- **Events**: Shared - available to all bookies (imported from Odds API)
- **Players**: Bookie-specific - each bookie has their own players
- **Bets**: Bookie-specific - tied to player and bookie
- **SyncService**: Downloads events where `bookie_id IS NULL OR bookie_id = <bookie_id>`

## UUID Case Sensitivity

iOS and PostgreSQL handle UUID casing differently:

- **iOS**: `UUID.uuidString` returns UPPERCASE (e.g., `F3AD0FA1-...`)
- **PostgreSQL**: Stores lowercase (e.g., `f3ad0fa1-...`)
- **Always normalize**: Use `.lowercased()` in Swift, `.toLowerCase()` in TypeScript before comparisons

## Documentation

See `README.md` for comprehensive app documentation including:
- What the app does
- How it's organized
- All models, views, and services explained
- Key concepts (balances, bets, auth, sync)
- What's been implemented (all phases)

## Games Filtering

Events are filtered in the UI while all data is preserved in the database:

- **GamesView (Bookie)**: Toggle between "Upcoming" and "Past" events
  - Upcoming: Non-final events + final events from last 48 hours
  - Past: Final events older than 48 hours (sorted newest first)
- **Player View**: Only shows bettable events (future start time, not locked/final/canceled)
- **Historical Data**: All events kept forever for bet history references
- **Event Lookups**: Use case-insensitive UUID comparison (`.lowercased()`) due to iOS/PostgreSQL casing differences

## Compliance Language

All user-facing strings use App Store compliant vocabulary. Internal Swift types/variables keep original names.

| Old Term | New Term |
|----------|----------|
| Bookie | Organizer |
| Player | Member |
| Bet/Bets | Pick/Picks |
| Parlay | Multi-Pick |
| Settlement | Reconciliation |
| Exposure | Open Activity |
| Payout | Potential Return |
| Profit/Loss | Performance |
| Wager | Stake |

## Current State (February 24, 2026)

- **Branch**: `ralph/sport-hub-pages`
- **Swift version**: 6.0 with `SWIFT_STRICT_CONCURRENCY = complete`
- **Deployment target**: iOS 18.0
- **Phases complete**: 1-17 (Core, Player Experience, Auth, Sync, Invites, Odds API, Server Authority, Auto-Pilot, Games Filtering, Acceptance Policy, Grading Improvements, Betting Experience Overhaul, Bookie Analytics v2, Compliance Language Overhaul, Pick Instance Refactor, Alternate Lines, iOS 26 SDK Migration)
- **Supabase migrations**: All applied (see SUPABASE_MIGRATIONS.md)
- **Edge Functions**: 12 functions for server-authoritative operations (including `submit_bets`, `submit_parlay`, `sync_games`, `claim_player`, `create_invite`, `claim_invite`)
- **Bookie Events tab**: Player-style compact card layout with sport tabs, search, sticky headers, muted odds buttons (`isViewOnly` mode)
- **Settings**: Streamlined — removed Odds API config, sample data, and sync button
- **Auto-pilot mode**: Picks auto-accepted, auto-graded, and auto-settled (ledger entries created automatically)
- **Auto-refresh**: Processes up to 10 games per run, catch-up grading for missed events, auto-void for stale pending bets, `force` flag for manual triggers
- **Cron jobs**: Auto-refresh runs twice daily (9 AM PT, 1 PM PT)
- **Branding**: App icon and in-app logo (`BookiLogo` image set), dark launch screen, `DESIGN_SYSTEM.md` restored
- **Landing page**: `landing/` directory with 8-section homepage (Hero, Positioning, Pillars, Product, Comparison, Pricing, Compliance, Final CTA), Features page with 6 alternating sections + capabilities grid, fixed top nav bar across all pages
- **Compliance**: All user-facing strings use approved vocabulary; disclaimers on auth and pick entry screens
- **TicketDetailView**: 4-card layout (Hero, Financials, Odds Breakdown, Activity) with odds format preference support
- **AccountView**: Condensed — Profile+Preferences merged, Performance card (Record + stats + credit bar), no My Picks (Track tab), History with enriched descriptions and player-facing amounts
- **Branding**: Slogan "Be The House." on login and landing page
- **Bookie Picks tab**: Badge showing open bet count (1-9+) in brand teal, Open/Past filter with player chips, card-based BetDetailView matching TicketDetailView
- **Batch singles**: `submit_bets` edge function batches all singles into one network call with partial success model
- **Member management**: Overflow menu on player detail with Archive/Remove; Remove severs bookie link (NULLs bookie_id + auth_user_id) preserving history
- **Members list**: Navigates to `PlayerAnalyticsDetailView` (same as dashboard), not old `PlayerDetailView`
- **Invite management**: Create/copy/delete invites from Members tab, permanent delete with `@AppStorage` fallback
- **Nav bar standardization**: All bookie tabs use centered inline title with wordmark on Dashboard/Members
- **Dashboard skeleton**: Shimmer placeholders during initial sync, dismissed on @Query data arrival, skipped when SwiftData has cache
- **Player games skeleton**: Shimmer on odds buttons while events+markets sync, dismissed on sync completion, branded splash replaces "Loading your account"
- **Tab bar styling**: Teal badge (Space Grotesk), all-caps labels for main tabs, badge set on UITabBarAppearance layouts
- **Auth UI polish**: Standardized back buttons (top-left gray overlay), unified CTA styling, removed feature pills, larger logo with glow
- **Search tab**: Dedicated SEARCH tab (2nd position) with full-screen search by team name, results as CompactGameRows grouped by sport/league; removed inline search from Games tab
- **Landing redesign**: 8-section homepage (Hero, Positioning, Pillars, Product toggle, Comparison, Gated Pricing, Compliance, Final CTA), dedicated Features page with 6 alternating feature sections + capabilities grid + stats, fixed glassmorphism nav bar with hamburger mobile menu
- **Wave background**: `WaveBackground` asset overlaid at 10% opacity on bet list cards (PickCardCompact, TicketCardView) and as page-level background on detail screens (TicketDetailView, BetDetailView)
- **Sport hub pages**: `SportCategory` enum + `SportPageView` with league sub-tabs (text + accent underline), tappable sport headers in Search/Games/Events, date-based section headers, team abbreviation lookup fix
- **Futures/outrights**: Full futures market support across all sports — `.outright` MarketType, futures tab on sport pages, outright markets synced via `sync_games`, odds refreshed via `auto_refresh_games`, manual grading only
- **Bookie futures parlay setting**: `allow_futures_parlays` on bookies table, toggle in Settings, enforced in BetSlipSheet for player accounts (Multi-Pick disabled with alert)
- **Logout stability**: Removed `clearLocalData` from logout paths — data cleared on next sync via `hasCompletedInitialSync` reset, prevents SwiftData model invalidation crashes
- **Player bookie RLS**: Migration 013 adds `get_player_bookie_id()` SECURITY DEFINER function + RLS policy so players can read their bookie's settings
