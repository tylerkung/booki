# PRD: Identity, Tenancy, and Sync

## Introduction

This PRD defines the foundational systems required to move Booki from a local prototype to a real, multi-user, production-safe application. It covers authentication, multi-tenant data isolation, and sync/offline behavior using Supabase as the backend platform.

These systems are prerequisites for connecting a real database and supporting multiple bookies with their own isolated player pools.

## Goals

- Securely identify bookies and players using Supabase Auth
- Support multi-device usage with consistent data
- Enable account recovery without data loss
- Isolate each bookie's data using Row Level Security (RLS)
- Sync local SwiftData with Supabase in realtime when online
- Support basic offline viewing (online required for writes)
- Handle conflicts with first-write-wins and user notification

## Non-Goals

- Social features or public discovery
- Player-to-player interaction
- Full offline write capability (defer to future)
- Complex merge-based conflict resolution
- Push notifications (separate PRD)

## User Types

### Bookie Account
- Primary account owner
- Pays subscription (future)
- Owns all data within a "book"
- Can create/manage players, events, bets

### Player Account
- Belongs to exactly one bookie
- Can only submit/view their own bets
- Cannot exist without a bookie
- Created via invite (not self-serve)

## User Stories

### US-001: Add Supabase SDK and Configuration
**Description:** As a developer, I need the Supabase Swift SDK integrated so I can use auth and database services.

**Acceptance Criteria:**
- [ ] Add Supabase Swift SDK via Swift Package Manager
- [ ] Create `SupabaseConfig.swift` with URL and anon key (from environment/config)
- [ ] Create `SupabaseClient.swift` singleton for shared client access
- [ ] Client initializes successfully on app launch
- [ ] Add `.xcconfig` or similar for managing Supabase credentials (not hardcoded)
- [ ] Project builds and runs in Simulator

---

### US-002: Create Auth State Manager
**Description:** As a developer, I need a centralized auth state manager to track login status and current user.

**Acceptance Criteria:**
- [ ] Create `AuthManager.swift` as an ObservableObject
- [ ] Properties: `isAuthenticated: Bool`, `currentUser: User?`, `userRole: UserRole` (bookie/player)
- [ ] Listen to Supabase auth state changes
- [ ] Persist session in Keychain automatically (Supabase SDK handles this)
- [ ] Expose `signOut()` method that clears session
- [ ] Add `@EnvironmentObject` setup in BookiApp.swift
- [ ] Project builds and runs in Simulator

---

### US-003: Create Bookie Signup Flow (Email/Password)
**Description:** As a new bookie, I want to create an account with email and password so I can start using the app.

**Acceptance Criteria:**
- [ ] Create `SignUpView.swift` with email, password, confirm password fields
- [ ] Validate: email format, password min 8 chars, passwords match
- [ ] Call Supabase `auth.signUp(email:password:)`
- [ ] On success, create bookie record in `bookies` table
- [ ] Show email verification required message
- [ ] Handle errors: email taken, weak password, network error
- [ ] Navigate to main app on successful verification
- [ ] Project builds and runs in Simulator

---

### US-004: Create Bookie Login Flow
**Description:** As a returning bookie, I want to log in with my credentials so I can access my book.

**Acceptance Criteria:**
- [ ] Create `LoginView.swift` with email and password fields
- [ ] Call Supabase `auth.signIn(email:password:)`
- [ ] On success, fetch bookie record and update AuthManager
- [ ] Handle errors: invalid credentials, unverified email, network error
- [ ] Add "Forgot Password" link (navigates to password reset)
- [ ] Add "Sign Up" link for new users
- [ ] Navigate to main app on success
- [ ] Project builds and runs in Simulator

---

### US-005: Add Sign in with Apple
**Description:** As a bookie, I want to sign in with Apple for faster, more secure authentication.

**Acceptance Criteria:**
- [ ] Add "Sign in with Apple" capability in Xcode
- [ ] Create Apple Sign-In button on LoginView and SignUpView
- [ ] Implement Apple authentication flow with ASAuthorizationController
- [ ] Exchange Apple credential for Supabase session
- [ ] Create bookie record if new user
- [ ] Handle errors: user cancelled, failed, network error
- [ ] Project builds and runs in Simulator

---

### US-006: Implement Password Reset Flow
**Description:** As a bookie, I want to reset my password if I forget it so I can regain access.

**Acceptance Criteria:**
- [ ] Create `ForgotPasswordView.swift` with email field
- [ ] Call Supabase `auth.resetPasswordForEmail()`
- [ ] Show success message: "Check your email for reset link"
- [ ] Handle deep link from email to open password reset in app
- [ ] Create `ResetPasswordView.swift` with new password fields
- [ ] Call Supabase `auth.updateUser(password:)`
- [ ] Navigate to login on success
- [ ] Project builds and runs in Simulator

---

### US-007: Create Auth Gate and Navigation
**Description:** As a developer, I need the app to show login/signup when unauthenticated and main app when authenticated.

**Acceptance Criteria:**
- [ ] Create `AuthGateView.swift` that checks AuthManager.isAuthenticated
- [ ] If not authenticated: show `AuthNavigationView` (login/signup flow)
- [ ] If authenticated: show `MainTabView` (existing app)
- [ ] Update `BookiApp.swift` to use AuthGateView as root
- [ ] Handle loading state while checking auth status
- [ ] Automatic navigation on auth state change
- [ ] Project builds and runs in Simulator

---

### US-008: Create Player Invite System - Bookie Side
**Description:** As a bookie, I want to generate invite codes for players so they can create accounts linked to my book.

**Acceptance Criteria:**
- [ ] Add `inviteCode: String?` and `inviteExpiresAt: Date?` fields to Player model
- [ ] Create `generateInviteCode()` function (8-char alphanumeric)
- [ ] Add "Invite Player" button in PlayerDetailView
- [ ] Generate code, set expiry (7 days), save to player
- [ ] Show invite code with copy button and share sheet
- [ ] Show expiry date and "Regenerate" option if expired
- [ ] Project builds and runs in Simulator

---

### US-009: Create Player Claim Flow
**Description:** As an invited player, I want to claim my invite and create an account so I can place bets.

**Acceptance Criteria:**
- [ ] Create `PlayerClaimView.swift` with invite code input
- [ ] Validate invite code against `players` table
- [ ] Check code not expired and not already claimed
- [ ] If valid: show email/password signup form
- [ ] On signup: create auth user, link to existing player record
- [ ] Set `inviteCode = nil` and `authUserId = user.id` on player
- [ ] Handle errors: invalid code, expired, already claimed
- [ ] Project builds and runs in Simulator

---

### US-010: Create Player Login Flow
**Description:** As a returning player, I want to log in to view my bets and place new ones.

**Acceptance Criteria:**
- [ ] Reuse LoginView with role detection after login
- [ ] After auth, check if user is bookie or player
- [ ] If player: fetch player record, set userRole = .player
- [ ] Navigate to player-specific UI (PlayerMainView)
- [ ] Player cannot access bookie features (grading, settings, etc.)
- [ ] Project builds and runs in Simulator

---

### US-011: Create Database Schema for Multi-Tenancy
**Description:** As a developer, I need the Supabase database schema to support multi-tenant isolation.

**Acceptance Criteria:**
- [ ] Create SQL migration file in `supabase/migrations/`
- [ ] Tables: `bookies`, `players`, `events`, `bets`, `ledger_entries`, `acceptance_policies`
- [ ] All tenant tables have `bookie_id` foreign key
- [ ] `players` table has `auth_user_id` nullable (set on claim)
- [ ] `bookies` table has `auth_user_id` (set on signup)
- [ ] Add indexes on `bookie_id` for all tables
- [ ] Document schema in `supabase/schema.md`
- [ ] Migration runs successfully

---

### US-012: Implement Row Level Security Policies
**Description:** As a developer, I need RLS policies so bookies only see their own data and players only see their own bets.

**Acceptance Criteria:**
- [ ] Enable RLS on all tenant tables
- [ ] Bookie policy: `auth.uid() = bookie.auth_user_id` for full access to own data
- [ ] Player policy: `auth.uid() = player.auth_user_id` for own player record
- [ ] Player can read events from their bookie
- [ ] Player can read/write only their own bets
- [ ] Player cannot access other players' data
- [ ] Test policies with different user tokens
- [ ] Document policies in `supabase/rls-policies.md`

---

### US-013: Create Sync Service Infrastructure
**Description:** As a developer, I need a sync service to coordinate data between SwiftData and Supabase.

**Acceptance Criteria:**
- [ ] Create `SyncService.swift` as ObservableObject
- [ ] Properties: `syncStatus: SyncStatus` (idle, syncing, error), `lastSyncedAt: Date?`
- [ ] Method: `sync()` to trigger full sync
- [ ] Method: `syncTable(_ table: String)` for targeted sync
- [ ] Track pending changes count
- [ ] Add to environment in BookiApp.swift
- [ ] Project builds and runs in Simulator

---

### US-014: Implement Download Sync (Server to Local)
**Description:** As a bookie, I want data from the server to sync to my device so I see the latest state.

**Acceptance Criteria:**
- [ ] On app launch (if authenticated), fetch data from Supabase
- [ ] Download: players, events, bets, ledger entries, policies
- [ ] Upsert into local SwiftData based on `id`
- [ ] Use `updatedAt` timestamp to detect newer records
- [ ] Handle pagination for large datasets
- [ ] Show sync progress indicator
- [ ] Project builds and runs in Simulator

---

### US-015: Implement Upload Sync (Local to Server)
**Description:** As a bookie, I want my local changes to upload to the server so other devices see them.

**Acceptance Criteria:**
- [ ] Track local changes with `needsSync: Bool` flag on models
- [ ] On sync: find all records where `needsSync = true`
- [ ] Upload to Supabase via upsert
- [ ] On success: set `needsSync = false`, update `syncedAt`
- [ ] Handle upload errors (network, RLS rejection)
- [ ] Queue failed uploads for retry
- [ ] Project builds and runs in Simulator

---

### US-016: Implement Realtime Subscriptions
**Description:** As a bookie, I want changes from other devices to appear automatically without manual refresh.

**Acceptance Criteria:**
- [ ] Subscribe to Supabase Realtime channels on login
- [ ] Listen for INSERT, UPDATE, DELETE on tenant tables
- [ ] Filter by `bookie_id` in subscription
- [ ] On receive: upsert/delete in local SwiftData
- [ ] Unsubscribe on logout
- [ ] Handle reconnection after network loss
- [ ] Project builds and runs in Simulator

---

### US-017: Implement First-Write-Wins Conflict Resolution
**Description:** As a bookie, I want to be notified if my change was rejected due to a conflict so I can review the current state.

**Acceptance Criteria:**
- [ ] Add `version: Int` field to syncable models
- [ ] On upload: include version in request
- [ ] Server check: if server version > client version, reject
- [ ] On rejection: fetch latest from server, show conflict alert
- [ ] Alert: "This record was modified on another device. Your changes were not saved."
- [ ] Option to view current state and retry edit
- [ ] Log conflicts for debugging
- [ ] Project builds and runs in Simulator

---

### US-018: Add Offline Mode Indicator and Behavior
**Description:** As a bookie, I want to know when I'm offline and understand what actions are limited.

**Acceptance Criteria:**
- [ ] Create `NetworkMonitor.swift` using NWPathMonitor
- [ ] Add offline banner to main views when disconnected
- [ ] In offline mode: allow viewing all local data
- [ ] In offline mode: disable write actions (show "Requires connection" message)
- [ ] Auto-hide banner and re-enable writes when connection restored
- [ ] Trigger sync on reconnection
- [ ] Project builds and runs in Simulator

---

### US-019: Implement Account States for Bookie
**Description:** As a developer, I need to handle bookie account states (active, suspended, closed).

**Acceptance Criteria:**
- [ ] Add `status: BookieStatus` field to Bookie model (active, suspended, closed)
- [ ] On login: check bookie status
- [ ] If suspended: show message with reason, block app access
- [ ] If closed: show message, block access, offer data export option
- [ ] Admin can update status via Supabase dashboard (manual for now)
- [ ] Project builds and runs in Simulator

---

### US-020: Implement Account States for Player
**Description:** As a bookie, I want to archive or ban players to control their access.

**Acceptance Criteria:**
- [ ] Add `accountStatus: PlayerAccountStatus` to Player (active, archived, banned)
- [ ] Archived: player can log in, view history, cannot place bets
- [ ] Banned: player cannot log in (show "Account suspended" message)
- [ ] Add status controls to PlayerDetailView for bookie
- [ ] Sync status changes to server immediately
- [ ] Project builds and runs in Simulator

---

## Functional Requirements

- FR-1: Bookies authenticate via email/password or Sign in with Apple
- FR-2: Players authenticate via invite code claim, then email/password
- FR-3: All tenant data includes `bookie_id` foreign key
- FR-4: RLS policies enforce data isolation at database level
- FR-5: Local SwiftData syncs with Supabase on app launch and in realtime
- FR-6: Sync uses version numbers for conflict detection
- FR-7: First-write-wins: later writes rejected with notification
- FR-8: Offline mode allows read-only access to local data
- FR-9: Account states (suspended, banned) block appropriate access

## Technical Considerations

- **Supabase Swift SDK**: Use official SDK for auth and database
- **Keychain**: SDK handles token storage in Keychain automatically
- **SwiftData**: Existing models need `bookie_id`, `needsSync`, `version` fields
- **RLS**: All queries automatically filtered by auth context
- **Realtime**: Use Supabase Realtime for instant cross-device sync
- **Network Monitor**: NWPathMonitor for connectivity status
- **Deep Links**: Handle password reset links opening in app

## Success Metrics

- Bookie can log in on two devices and see consistent data within 5 seconds
- Player cannot access data from another bookie (RLS enforced)
- Conflict resolution notifies user 100% of the time (no silent data loss)
- Offline banner appears within 2 seconds of losing connection
- Account state changes take effect on next app launch/sync

## Open Questions

- Should we support biometric login (Face ID/Touch ID) as convenience?
- What's the invite code format preference? (8-char alphanumeric suggested)
- Should archived players be able to see their full history or just recent?
- Do we need admin dashboard for bookie management, or Supabase dashboard sufficient for now?

## Deferred: Deep Link Setup (Production)

Email verification and password reset links currently fail on mobile because no deep link handling is configured. For production:

1. **iOS App Configuration:**
   - Add custom URL scheme (`booki://`) in Info.plist
   - Implement `onOpenURL` handler in SwiftUI to catch auth callbacks
   - Parse the tokens from the URL and complete auth flow

2. **Supabase Configuration:**
   - Set Site URL to `booki://`
   - Add `booki://auth/callback` to Redirect URLs

3. **Universal Links (optional but recommended):**
   - Set up Associated Domains for `applinks:yourdomain.com`
   - Host `.well-known/apple-app-site-association` file

This should be a separate user story in a future "Production Readiness" PRD.
