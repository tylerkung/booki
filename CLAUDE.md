# Booki - Development Guidelines

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
- **Shared helpers**: `_shared/cors.ts`, `_shared/supabase.ts`, `_shared/idempotency.ts`, `_shared/audit.ts`
- **Functions**: `submit_bet`, `accept_bet`, `grade_bet`, `settle_bet`, `adjust_balance`, `reverse_settlement`, `override_grade`
- **Deploy**: `supabase functions deploy <function-name>`

All functions:
1. Validate JWT authorization
2. Check idempotency key (prevent duplicates)
3. Validate business rules
4. Emit audit events
5. Return cached response on duplicate requests

## Documentation

See `README.md` for comprehensive app documentation including:
- What the app does
- How it's organized
- All models, views, and services explained
- Key concepts (balances, bets, auth, sync)
- What's been implemented (Phases 1-7)

## Current State (January 29, 2026)

- **Branch**: `ralph/server-authority-legal`
- **Phases complete**: 1-7 (Core, Player Experience, Auth, Sync, Invites, Odds API, Server Authority)
- **Supabase migrations**: All applied (see SUPABASE_MIGRATIONS.md)
- **Edge Functions**: 7 functions for server-authoritative operations
- **Odds API key**: Configured in Settings (free tier, 500 calls/month)
