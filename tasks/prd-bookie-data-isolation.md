# PRD: Fix Bookie Data Isolation

## Introduction

Critical bug: when a bookie logs in, they can see players (and potentially bets/ledger entries) from other bookie accounts. This happens because SwiftData stores data locally from previous logins and is never cleared on logout. All `@Query` declarations across 30+ views fetch unfiltered — returning every record in the local database regardless of which bookie it belongs to.

**Root cause chain:**
1. SyncService correctly downloads only the current bookie's data from Supabase (filtered by `bookie_id`)
2. Supabase RLS correctly prevents unauthorized server-side reads
3. **SwiftData is never cleared on logout** — old bookie's data persists
4. **`@Query` has no `bookieId` predicate** — returns all local records

**Impact:** A bookie sees another bookie's members, picks, and financial data after switching accounts on the same device.

## Goals

- Ensure complete data isolation between bookie accounts on a single device
- Clear all local data when switching accounts (logout or login as different user)
- Prevent any cross-bookie data leakage without modifying 60+ `@Query` declarations

## Approach: Clear Local Data on Auth Transitions

Rather than adding `bookieId` predicates to every `@Query` (60+ locations, high risk of missing one), the fix is:

1. **Clear all SwiftData on logout** — delete all Player, Bet, Event, LedgerEntry, etc. records
2. **Clear all SwiftData before sync on login** — ensure fresh start for the new bookie
3. SyncService then re-downloads only the current bookie's data

This is the correct approach because:
- The app is already "sync from cloud" — local data is a cache, not the source of truth
- Events are shared (no bookie_id) so they get re-downloaded regardless
- Adding predicates to 60+ queries is error-prone and creates ongoing maintenance burden
- A single clear-on-auth-change is simple, reliable, and covers all current and future queries

## User Stories

### US-001: Clear local SwiftData on logout
**Description:** As a bookie, when I log out, all locally cached data should be removed so the next user who logs in doesn't see my data.

**Acceptance Criteria:**
- [ ] When `AuthManager.signOut()` is called, all SwiftData entities are deleted before the auth session is cleared
- [ ] Entities to clear: Player, Bet, Event, Market, LedgerEntry, AcceptancePolicy, SettlementPeriod, PlayerSettlement, AuditEvent (all SwiftData @Model types)
- [ ] After logout, the local database is empty
- [ ] The logout flow still works correctly (user returns to login screen)
- [ ] Typecheck passes

### US-002: Clear local SwiftData before initial sync on login
**Description:** As a bookie logging into a device that may have another bookie's cached data, I need the local store wiped before my data syncs down.

**Acceptance Criteria:**
- [ ] SyncService (or AuthGateView) clears all local SwiftData entities before starting the first full sync
- [ ] This runs AFTER authentication succeeds but BEFORE downloadPlayers/downloadBets/etc.
- [ ] After sync completes, only the current bookie's data exists locally
- [ ] Events (shared, no bookie_id) are re-downloaded correctly
- [ ] Typecheck passes

### US-003: Verify isolation with account switching
**Description:** As a developer, I need to verify that switching between bookie accounts produces correct isolation.

**Acceptance Criteria:**
- [ ] Login as Bookie A → members list shows only Bookie A's members
- [ ] Logout → login as Bookie B → members list shows only Bookie B's members (no Bookie A data)
- [ ] Logout → login as Bookie A again → members list shows only Bookie A's members (re-synced)
- [ ] Dashboard metrics (exposure, pending picks, etc.) only reflect current bookie's data
- [ ] Picks list only shows current bookie's picks
- [ ] Typecheck passes

## Functional Requirements

- FR-1: `AuthManager.signOut()` must delete all records from every SwiftData entity before clearing the auth session
- FR-2: A `clearLocalData(context:)` utility function should exist that deletes all records from all SwiftData @Model types
- FR-3: This utility must be called on logout AND before the first sync after login
- FR-4: The clear must be synchronous (complete before next step) to prevent race conditions
- FR-5: `@AppStorage` preferences (odds format, credit limit, etc.) should NOT be cleared — they're device-level, not bookie-level

## Non-Goals

- Not adding `bookieId` predicates to individual `@Query` declarations (too many, too fragile)
- Not changing Supabase RLS policies (already correct)
- Not changing SyncService download logic (already correctly filters by bookie_id)
- Not implementing offline-first conflict resolution (cloud is source of truth)

## Technical Considerations

- **SwiftData deletion**: Use `modelContext.delete(model:)` in a loop or `try modelContext.delete(model: Player.self)` (batch delete)
- **All @Model types to clear**: Player, Bet, Event, Market, LedgerEntry, AcceptancePolicy, SettlementPeriod, PlayerSettlement, UserAgreement, AuditEvent
- **ModelContext access**: `AuthManager` doesn't currently have a `ModelContext` — it may need one passed in, or the clear can happen in `AuthGateView` which has access to `@Environment(\.modelContext)`
- **SyncService already has ModelContext**: The clear-before-sync can happen at the start of `performFullSync()`
- **Timing**: Clear must complete before any UI renders with stale data — do it before dismissing the loading screen

## Success Metrics

- Zero cross-bookie data leakage when switching accounts
- Sync completes correctly after clearing (all current bookie's data re-downloaded)
- No regression in normal app usage (single bookie, no account switching)

## Open Questions

- Should `Bookie` model itself be cleared? Probably yes — it gets re-downloaded during sync
- Should we show a brief "Loading your data..." indicator during the post-clear sync?
