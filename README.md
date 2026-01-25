# Booki - iOS Sports Betting Management App

## What is Booki?

Booki is an iOS app for managing a small-scale sports betting operation. It has two types of users:

1. **Bookies** - The operators who manage players, accept bets, track balances, and settle accounts
2. **Players** - People who place bets with the bookie and track their own activity

Think of it like a personal bookkeeping app for friendly sports betting among a group of friends or a small community.

---

## App Overview

### For Bookies (Main Users)
- **Dashboard**: See today's action, total exposure, pending bets, and alerts
- **Games**: Browse upcoming sporting events and their betting lines (spreads, moneylines, totals)
- **Bets**: View all bets across all players, filter by status
- **Players**: Manage player accounts, credit limits, balances, and collection status
- **Grading**: Grade completed events and settle bets
- **Settings**: Configure acceptance rules, export data, manage account

### For Players
- **View Balance**: See what they owe or are owed
- **View Bets**: See their active and settled bets
- **View Activity**: See their transaction history (deposits, withdrawals, settlements)

---

## How the App is Organized

The app follows a clear folder structure:

```
Booki/
├── BookiApp.swift          # App entry point - sets up the app
├── ContentView.swift       # Main navigation (tab bar for bookies)
├── Models/                 # Data structures (what the app stores)
├── Views/                  # User interface screens
├── ViewModels/             # Logic for views (currently minimal)
├── Services/               # Business logic and utilities
└── Info.plist              # App configuration
```

### Models (The Data)

These define what information the app stores:

| Model | What it Stores |
|-------|---------------|
| **Bookie** | The operator's profile (name, email, subscription status) |
| **Player** | A bettor's info (name, credit limit, balance, invite code, status) |
| **Event** | A sporting event (teams, sport, start time, status) |
| **Market** | A betting line on an event (spread, moneyline, or total) |
| **Bet** | A wager placed by a player (stake, odds, selection, status) |
| **LedgerEntry** | A financial transaction (settlements, adjustments, payments) |
| **AcceptancePolicy** | Rules for auto-accepting bets |
| **SettlementPeriod** | A weekly settlement window |
| **PlayerSettlement** | A player's settlement within a period |

### Views (The Screens)

These are what users see and interact with:

| View | Purpose |
|------|---------|
| **AuthGateView** | Login/signup screen - routes users to bookie or player view |
| **DashboardView** | Bookie's home screen with key metrics |
| **GamesView** | Browse events and place bets |
| **BetsListView** | All bets with filtering |
| **PlayersListView** | Player management |
| **PlayerDetailView** | Individual player details and actions |
| **GradingView** | Grade events and settle bets |
| **SettingsView** | App settings and account |
| **PlayerMainView** | Player's read-only view of their account |
| **PlayerClaimView** | Where players claim their account with invite code |

### Services (The Logic)

These handle the business rules and calculations:

| Service | What it Does |
|---------|-------------|
| **BalanceService** | Calculates player balances from ledger entries |
| **LiabilityService** | Calculates potential payouts on bets |
| **ExposureService** | Calculates bookie's risk exposure |
| **BetService** | Creates and manages bets |
| **GradingService** | Grades bets as win/loss/push |
| **PlayerService** | Manages player accounts |
| **AuthManager** | Handles login/logout and user sessions |
| **SyncService** | Syncs data between device and cloud |
| **RealtimeService** | Receives live updates from other devices |
| **InviteCodeService** | Generates and validates player invite codes |

---

## Key Concepts Explained

### How Balances Work

The app uses a **ledger system** - every financial change is recorded as a transaction:
- When a bet settles, a ledger entry is created
- When a bookie adjusts a balance, a ledger entry is created
- When a payment is logged, a ledger entry is created

The player's balance is calculated by adding up all their ledger entries. This creates an audit trail where you can always see how a balance was reached.

**Balance Convention:**
- Positive balance = player owes the bookie money
- Negative balance = bookie owes the player money (player is winning)

### How Bets Flow

1. **Pending** - Bet is submitted, waiting for bookie to review
2. **Accepted** - Bookie approved the bet
3. **Declined** - Bookie rejected the bet
4. **Ready to Grade** - Event is over, bet needs grading
5. **Graded** - Bet marked as win/loss/push
6. **Settled** - Payout/loss recorded in ledger

### How Authentication Works

The app uses **Supabase** for user accounts:
- Bookies sign up with email/password or Apple Sign-In
- Players are invited by bookies via an **invite code**
- When a player enters their code, they create their own login
- The app knows if you're a bookie or player and shows the right interface

### How Data Syncs

The app is **local-first** with cloud sync:
1. All data is stored locally on the device (works offline)
2. Changes sync to Supabase cloud when online
3. Other devices receive updates in real-time
4. If there's a conflict, the first write wins

**Row Level Security (RLS)** ensures:
- Each bookie only sees their own data
- Players only see their own bets and balances
- No one can access another bookie's players

---

## What's Been Implemented

### Phase 1: Core Betting Platform
- Event and market management
- Bet placement and tracking
- Player management with credit limits
- Balance calculations and ledger system
- Liability and exposure calculations
- Bet grading (win/loss/push)
- Parlay betting support
- Dark sports-betting theme

### Phase 2: Player Experience
- Player-facing views
- Bet history grouped by ticket
- Collection status tracking (reminded, promised, overdue)
- Weekly settlement workflow

### Phase 3: Authentication & Multi-Tenancy
- Supabase authentication (email/password + Apple Sign-In)
- Bookie signup and login
- Multi-tenant database with Row Level Security
- Each bookie's data is completely isolated

### Phase 4: Sync & Real-time
- Bidirectional sync between device and cloud
- Real-time updates across devices
- Offline support with sync-when-online
- Conflict detection and resolution
- Network status monitoring

### Phase 5: Player Invites & Accounts
- Bookie logout functionality
- Invite code generation for players
- Player account claiming flow
- Player login and authentication
- Read-only player view (PlayerMainView)
- Role-based routing (bookie vs player)

---

## Technical Details

### Tech Stack
- **Platform**: iOS 17+
- **Language**: Swift 5.9+
- **UI Framework**: SwiftUI
- **Local Storage**: SwiftData
- **Cloud Backend**: Supabase (Postgres + Auth + Realtime)
- **Architecture**: MVVM with Services layer

### Styling System

All colors come from `Theme.swift`:
```swift
Theme.background       // Dark background
Theme.cardBackground   // Slightly lighter cards
Theme.accent          // Gold/yellow accent color
Theme.textPrimary     // White text
Theme.textSecondary   // Gray text
Theme.success         // Green (wins)
Theme.danger          // Red (losses)
Theme.warning         // Orange (alerts)
```

### Database Schema

The Supabase database has these tables:
- `bookies` - Bookie accounts (linked to auth.users)
- `players` - Player records (belong to a bookie)
- `events` - Sporting events
- `bets` - All bets placed
- `ledger_entries` - Financial transactions
- `acceptance_policies` - Bet acceptance rules

All tables have `bookie_id` for multi-tenant isolation.

---

## Saved for Future

### Odds & Results Ingestion (API Integration)
- Integrate with The Odds API for live odds
- Auto-populate events from API
- Fetch final scores and auto-grade bets
- Background jobs for automatic updates
- *Waiting for API keys*

---

## Quick Reference

### Key Files to Know
| File | Purpose |
|------|---------|
| `BookiApp.swift` | App setup, dependency injection |
| `ContentView.swift` | Main tab navigation |
| `AuthGateView.swift` | Login routing |
| `Theme.swift` | All colors and styling |
| `AuthManager.swift` | Login/logout state |
| `SyncService.swift` | Cloud sync coordinator |

---

*Last updated: January 24, 2026 - Phase 5 (Player Invites & Accounts) completed*
