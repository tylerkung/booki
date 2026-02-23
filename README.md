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
| **UserAgreement** | Record of a user accepting Terms of Service |
| **AuditEvent** | A logged action for audit trail (bet changes, settlements) |

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
| **UserAgreementView** | Terms of Service acceptance screen |
| **BetHistoryView** | Timeline of all changes to a bet (audit trail) |

### Services (The Logic)

These handle the business rules and calculations:

| Service | What it Does |
|---------|-------------|
| **BalanceService** | Calculates player balances from ledger entries |
| **LiabilityService** | Calculates potential payouts on bets |
| **ExposureService** | Calculates bookie's risk exposure |
| **BetService** | Creates and manages bets |
| **GradingService** | Grades and settles single bets |
| **ParlayGradingService** | Calculates parlay outcomes with push/void policy support |
| **PlayerService** | Manages player accounts |
| **AuthManager** | Handles login/logout and user sessions |
| **SyncService** | Syncs data between device and cloud |
| **RealtimeService** | Receives live updates from other devices |
| **InviteCodeService** | Generates and validates player invite codes |
| **OddsAPIService** | Fetches sports, odds, and scores from The Odds API |
| **OddsAPIMapper** | Converts API responses to app models |
| **AgreementService** | Checks and submits Terms of Service acceptance |
| **EdgeFunctionService** | Calls Supabase Edge Functions with auth and retry logic |
| **AuditService** | Fetches audit history for bets and entities |
| **BetSlipManager** | Manages bet slip state (selections, stake, parlay mode) |

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

**Auto-Pilot Mode (Default):**
1. **Accepted** - Bet is submitted and auto-accepted immediately
2. **Graded** - When game finalizes, bet is auto-graded as win/loss/push
3. **Settled** - Bookie settles the bet (payout/loss recorded in ledger)

**Manual Mode (Opt-in):**
1. **Pending** - Bet is submitted, waiting for bookie to review
2. **Accepted/Declined** - Bookie approves or rejects the bet
3. **Ready to Grade** - Event is over, bet needs manual grading
4. **Graded** - Bookie marks bet as win/loss/push
5. **Settled** - Payout/loss recorded in ledger

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

### Phase 6: Odds API Integration
- The Odds API service for fetching sports data
- Import events from API by sport (NBA, NFL, MLB, etc.)
- Fetch scores for completed games
- Auto-update events with final scores
- Refresh odds for upcoming events (line movements)
- API quota tracking and persistence
- Settings UI for API key and bookmaker preference
- Manual import triggers (quota-conscious design)

### Phase 7: Server Authority & Legal Acknowledgment
- **Terms of Service Flow**
  - Required legal acknowledgment before using the app
  - Version tracking for ToS updates (force re-acceptance when terms change)
  - Immutable audit trail of all acceptances
  - Integrated into both bookie signup and player claim flows

- **Server-Authoritative Edge Functions**
  - All critical betting operations run server-side (not client)
  - `submit_bet` - Player bet submission with event lock validation
  - `accept_bet` - Bookie bet acceptance with ownership validation
  - `grade_bet` - Bookie grading with status validation
  - `settle_bet` - Atomic settlement with ledger entry creation
  - `adjust_balance` - Manual balance adjustments with required reason
  - `reverse_settlement` - Undo settlements for mistake correction
  - `override_grade` - Change grades with auto-reversal if settled

- **Idempotency & Retry Safety**
  - All Edge Functions use idempotency keys to prevent duplicates
  - iOS app retries network failures with exponential backoff (1s, 2s, 4s)
  - Same idempotency key returns cached response on retry

- **Audit Trail & Dispute Resolution**
  - Every bet action logged with actor, timestamp, before/after state
  - BetHistoryView shows complete timeline of bet changes
  - Bookies can override grades with required reason
  - Bookies can reverse settlements with required reason
  - All corrections create audit records for accountability

### Phase 8: Auto-Pilot Mode & Shared Events
- **Auto-Accept Bets**
  - Bets are accepted immediately by default (no manual approval needed)
  - Bookies can opt-in to manual approval via Settings toggle
  - Audit events logged for auto-accepted bets

- **Auto-Grade Bets**
  - When games finalize, bets are automatically graded
  - Supports moneyline (winner), spread (point differential), and totals (over/under)
  - Bookies can opt-in to manual grading via Settings toggle
  - Grade results stored and displayed (e.g., "Final: 110-105")

- **Shared Events Architecture**
  - Events/games are shared across all bookies (no bookie_id)
  - All bookies see the same games and scores from Odds API
  - Players and bets remain bookie-specific
  - Simplifies multi-bookie deployments

- **Settings UI for Manual Modes**
  - "Require manual bet approval" toggle
  - "Grade bets manually" toggle
  - Both default to OFF (auto-pilot mode)

### Phase 9: Games Filtering & Data Management
- **Smart Games View Filtering**
  - Bookie sees "Upcoming" (default) or "Past" events via toggle
  - Upcoming: Active events + recently finished (last 48 hours)
  - Past: Completed events older than 48 hours
  - Events sorted appropriately (upcoming by soonest, past by most recent)

- **Player Game Filtering**
  - Players only see events they can actually bet on
  - Hides past events, locked events, and canceled events
  - Clean betting experience focused on available games

- **Historical Data Preservation**
  - All events kept in database permanently
  - Bet history maintains full event context (teams, scores)
  - No data loss - filtering is UI-only

- **UUID Case Sensitivity Fix**
  - Fixed event lookups across 9 view files
  - Case-insensitive comparison for iOS/PostgreSQL compatibility

### Phase 10: Acceptance Policy Enforcement
- **Server-Side Policy Evaluation**
  - `submit_bet` and `submit_parlay` Edge Functions enforce acceptance policies
  - Stake threshold validation (auto-accept limit, require-approval threshold)
  - New player review (bets from players below bet count threshold require approval)
  - Policy violations stored in `policy_violation_reason` column

- **Parlay-Specific Rules**
  - `auto_accept_parlays` setting to require manual approval for parlays
  - `parlay_max_legs` limit enforcement
  - Parlay legs inherit stake and new-player checks from single bets

- **Policy Violation Display**
  - Bookie sees why a bet requires review (e.g., "Stake exceeds limit", "New player")
  - Violations shown in BetsListView for pending bets
  - Multiple violations combined with comma separator

- **Parlay Grading & Settlement**
  - `ParlayGradingService` calculates combined parlay outcomes
  - Push/void policy support: "Treat as Push" or "Reduce Legs & Reprice"
  - Single ledger entry for entire parlay (not per-leg)
  - Projected payout display during grading

### Phase 11: Grading Improvements
- **Server-Finalized Event Support**
  - GradingView now shows `accepted` bets whose events are `final`
  - Fixes issue where server-side finalization (via auto_refresh_games) didn't surface bets for grading
  - Bets transition to grading list automatically when events sync as final

### Phase 12: Betting Experience Overhaul
- **Parlay Submission Endpoint**
  - New `submit_parlay` Edge Function for atomic parlay submission
  - Single network call creates all legs with shared ticket_id
  - Locked event validation rejects entire parlay if any leg is locked
  - Swift types (ParlayLeg, SubmitParlayRequest/Response) in BetService

- **Enhanced Bet Slip**
  - Parlay mode uses dedicated endpoint instead of per-leg singles calls
  - Per-item stakes auto-initialized when mode switches from parlay to singles
  - Mode switch explanation banner shown to player
  - Same-game parlay advisory warning (non-blocking)
  - Parlay-specific loading state ("Submitting parlay..." vs "Submitting 1 of N...")
  - Locked event error display with highlighting and removal button
  - All inputs disabled during submission

- **Bet Model Enrichment**
  - Added `eventDescription`, `sportLeague`, `sideIndicator`, `marketId` fields to Bet
  - Offline fallback: bet rows show stored event context when event not cached
  - Sport league abbreviation (e.g., "NBA") shown in bet list rows
  - Consistent `MarketType.displayName` for title-case market labels

### Phase 16: Alternate Lines
- **Alternate Spreads & Totals**
  - Fetches alternate_spreads and alternate_totals from The Odds API (same endpoint, no extra API cost)
  - Groups outcomes by point value into paired markets (home/away for spreads, over/under for totals)
  - New MarketType cases: `alternateSpread`, `alternateTotal`, `teamTotal`
  - Composite market upsert key supports multiple markets per type per event
  - Grading reuses existing spread/total logic for alternate lines

- **GameDetailView Alternate Lines Tab**
  - "Alternate Lines" tab now populated with alt spreads and alt totals
  - Markets sorted by line value for easy browsing
  - "All Markets" tab filtered to main lines only (no alternate clutter)
  - Alternate markets selectable and addable to bet slip

### Branding & Design System
- **App Icon**: Custom Booki wordmark on electric cyan background (1024x1024)
- **Launch Screen**: Electric cyan background → SwiftUI loading view with logo and spinner
- **In-App Logo**: `Image("BookiLogo")` available via asset catalog
- **Design System**: `Booki/DESIGN_SYSTEM.md` — colors, typography, spacing, components
- **Primary Accent**: Electric cyan `#00F5D4`
- **Font**: System (SF Pro), monospaced digits for odds

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
- `bookies` - Bookie accounts (linked to auth.users), includes `manual_bet_acceptance` and `manual_bet_grading` toggles
- `players` - Player records (belong to a bookie)
- `events` - Sporting events (shared across bookies when `bookie_id` is NULL)
- `markets` - Betting lines on events
- `bets` - All bets placed, includes `policy_violation_reason` for review queue
- `ledger_entries` - Financial transactions
- `acceptance_policies` - Bet acceptance rules (stake limits, parlay rules, new player thresholds)
- `user_agreements` - Terms of Service acceptances (immutable)
- `idempotency_keys` - Deduplication for Edge Functions
- `audit_events` - Audit trail for all bet actions

Most tables have `bookie_id` for multi-tenant isolation. Exception: `events` table has nullable `bookie_id` - shared events (NULL) are visible to all bookies.

### Edge Functions

Server-authoritative functions running on Supabase (Deno/TypeScript):

| Function | Purpose |
|----------|---------|
| `submit_bet` | Player submits a single bet (validates event, applies acceptance policy) |
| `submit_parlay` | Player submits a parlay bet (validates all legs, applies parlay policy) |
| `accept_bet` | Bookie accepts a pending bet (when manual mode enabled) |
| `grade_bet` | Bookie grades bet as win/loss/push/void (manual grading) |
| `settle_bet` | Bookie settles bet (creates ledger entry atomically) |
| `adjust_balance` | Bookie adjusts player balance with reason |
| `reverse_settlement` | Bookie undoes a settlement (creates reversal entry) |
| `override_grade` | Bookie changes a grade (auto-reverses if settled) |
| `auto_refresh_games` | Cron job: fetches scores and auto-grades bets when games finalize |
| `sync_games` | Fetches odds/events from The Odds API, updates markets |

All functions validate JWT auth, check idempotency, and emit audit events.

---

## Saved for Future

### Enhanced Features
- Push notifications for line movements
- Batch settlement for multiple players
- Player notifications when bets grade
- Settlement reminders and scheduling

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

*Last updated: February 23, 2026 - Tab bar styling polish, OG meta tags for landing page*
