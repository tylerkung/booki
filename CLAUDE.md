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

## Odds API Integration

- **Manual triggers only** - Import/Fetch/Refresh are manual to conserve API quota (500 free calls/month)
- **OddsAPIService.shared** - Singleton with @Published quota tracking
- **API key stored in @AppStorage** - Settings > Odds API section
- **Event.externalId** - Links imported events to API for score updates
- **Supabase migration required** - See SUPABASE_MIGRATIONS.md for events table columns

## Build & Test

- Xcode command line tools don't support full builds - use Xcode IDE
- Delete app from Simulator when SwiftData schema changes

## Documentation

See `README.md` for comprehensive app documentation including:
- What the app does
- How it's organized
- All models, views, and services explained
- Key concepts (balances, bets, auth, sync)
- What's been implemented (Phases 1-6)

## Current State (January 25, 2026)

- **Branch**: `ralph/games-density-v1`
- **Phases complete**: 1-6 (Core, Player Experience, Auth, Sync, Invites, Odds API)
- **Supabase migrations**: All applied (see SUPABASE_MIGRATIONS.md)
- **Odds API key**: Configured in Settings (free tier, 500 calls/month)
