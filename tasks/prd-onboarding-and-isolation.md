# PRD: Simplify Onboarding, Fix Data Isolation & Dashboard Polish

## Introduction

Two related issues affecting the new bookie experience:

1. **Onboarding is too complex.** The current 5-step wizard (Welcome → Configure → Add Members → Import Games → Success) creates unnecessary friction. New bookies should see a welcome screen and go straight to the dashboard with sensible defaults.

2. **Critical data isolation bug.** A player named "Jeff" (belonging to another bookie) appears for every bookie account, including brand new ones. This happens because SwiftData is never cleared on logout, and all 60+ `@Query` declarations are unfiltered — returning every record in the local database regardless of which bookie it belongs to.

**Root cause of isolation bug:**
- SyncService correctly downloads only the current bookie's data (filtered by `bookie_id`)
- Supabase RLS correctly prevents unauthorized server-side reads
- **SwiftData is never cleared on logout** — old bookie's data persists locally
- **`@Query` has no `bookieId` predicate** — returns all local records from all past logins

## Goals

- Reduce onboarding to a single welcome screen → dashboard
- Apply sensible defaults without requiring user input
- Ensure complete data isolation between bookie accounts on a single device
- Clear all local data when switching accounts (logout or login as different user)

## User Stories

### US-001: Clear local SwiftData on logout
**Description:** As a bookie, when I log out, all locally cached data should be removed so the next user who logs in doesn't see my data.

**Acceptance Criteria:**
- [ ] Create a `clearLocalData(context:)` utility that deletes all records from every SwiftData @Model type
- [ ] @Model types to clear: Player, Bet, Event, Market, LedgerEntry, AcceptancePolicy, SettlementPeriod, PlayerSettlement, UserAgreement, AuditEvent, Bookie
- [ ] Call `clearLocalData` when `AuthManager.signOut()` is invoked, before the auth session is cleared
- [ ] AuthManager needs access to ModelContext (pass it in or call from AuthGateView which has `@Environment(\.modelContext)`)
- [ ] After logout, the local database is empty and user returns to login screen
- [ ] `@AppStorage` preferences (odds format, credit limit, etc.) are NOT cleared — they're device-level settings
- [ ] Typecheck passes

### US-002: Clear local SwiftData before initial sync on login
**Description:** As a bookie logging into a device that may have another bookie's cached data, I need the local store wiped before my data syncs down.

**Acceptance Criteria:**
- [ ] SyncService (or AuthGateView) clears all local SwiftData entities before starting the first full sync
- [ ] This runs AFTER authentication succeeds but BEFORE downloadPlayers/downloadBets/etc.
- [ ] Reuse the `clearLocalData(context:)` utility from US-001
- [ ] After sync completes, only the current bookie's data exists locally
- [ ] Events (shared, no bookie_id) are re-downloaded correctly
- [ ] Typecheck passes

### US-003: Strip onboarding to welcome-only flow
**Description:** As a new bookie, I want to get to the dashboard immediately after signing up so I can start exploring the app without a multi-step wizard.

**Acceptance Criteria:**
- [ ] OnboardingContainerView only shows the Welcome step, then dismisses onboarding
- [ ] The "Set Up Your Group" button on OnboardingWelcomeView marks onboarding complete and goes to dashboard
- [ ] The "Skip for now" button also marks onboarding complete and goes to dashboard
- [ ] No Configure, Add Members, Import Games, or Success screens are shown
- [ ] Progress dots / "Step X of 3" header is removed (only one screen, no steps needed)
- [ ] Typecheck passes

### US-004: Apply sensible defaults on account creation
**Description:** As a new bookie, I want the app to use good defaults so everything works without manual configuration during onboarding.

**Acceptance Criteria:**
- [ ] Auto-accept picks defaults to ON (bookie.manualBetAcceptance = false) — verify this is the existing default
- [ ] Auto-grade picks defaults to ON (bookie.manualBetGrading = false) — verify this is the existing default
- [ ] Default credit limit is set to $500 via @AppStorage("default_credit_limit") if not already set
- [ ] Reconciliation frequency defaults to "weekly" — verify this is the existing default
- [ ] All defaults are applied without user interaction during onboarding
- [ ] Typecheck passes

### US-005: Clean up unused onboarding files
**Description:** As a developer, I want to remove dead onboarding code so the codebase stays clean.

**Acceptance Criteria:**
- [ ] OnboardingConfigureView.swift is deleted
- [ ] OnboardingAddPlayersView.swift is deleted
- [ ] OnboardingImportGamesView.swift is deleted
- [ ] OnboardingSuccessView.swift is deleted
- [ ] OnboardingStep enum is simplified — only needs `.welcome` or can be removed entirely
- [ ] OnboardingManager is simplified — `markStepComplete()` and per-step tracking removed, only `isOnboardingComplete` / `markAllComplete()` needed
- [ ] All references to removed files/types are cleaned up
- [ ] No compiler warnings about unused code
- [ ] Typecheck passes

### US-006: Verify player bet visibility after sync
**Description:** As a player, all my bets should be visible on my Track tab regardless of bet status or event status. Bets that have been placed on games that have since started should show as "pending grading" — they should never disappear.

**Acceptance Criteria:**
- [ ] After a player logs in and sync completes, ALL of their bets appear on the Track tab (accepted, readyToGrade, graded, settled, pending — every status)
- [ ] Bets on games that have started but not been graded show with an appropriate status (e.g. "Awaiting Result" or the existing StatusPill)
- [ ] The `bet.player` relationship is correctly established during sync — verify `upsertBet` in SyncService links the Bet to the correct Player SwiftData object
- [ ] TrackView's `playerBets` filter (`$0.player?.id == player.id`) correctly matches after a fresh sync (no nil player references)
- [ ] If `clearLocalData` runs before sync (from US-002), the fresh sync correctly re-establishes all Player↔Bet relationships
- [ ] Typecheck passes

### US-007: Smooth earnings chart animation when switching time ranges
**Description:** As a bookie, when I tap between time ranges (1W, 1M, 3M, 1Y, ALL) on the earnings chart, the line should animate smoothly instead of jumping or looking jagged.

**Acceptance Criteria:**
- [ ] When switching time ranges, the chart line morphs smoothly between states
- [ ] Use a fixed number of data points (e.g. always resample to 30 points) regardless of time range, so Swift Charts can interpolate between matching x-positions
- [ ] The `EarningsChart` in `AnalyticsDashboardView.swift` normalizes `dataPoints` to a fixed count before rendering
- [ ] The `.animation` modifier on the Chart produces a smooth line morph (not a jump cut)
- [ ] `.interpolationMethod(.catmullRom)` is preserved for smooth curves
- [ ] Typecheck passes

### US-008: Auth flow visual consistency
**Description:** As a user, I want the login, signup, and launch screens to feel like one cohesive flow with consistent backgrounds, logo placement, and smooth transitions — no jarring jumps between screens.

**Acceptance Criteria:**
- [ ] All auth screens (LoginView welcome, LoginView sign-in, SignUpView, ForgotPasswordView, PlayerClaimView) use `Theme.backgroundGradient` as the background
- [ ] BookiLogo appears on every auth screen at a consistent size (180pt width) with the same accent glow (`shadow(color: Theme.accent.opacity(0.3), radius: 40)`)
- [ ] SignUpView and ForgotPasswordView add the BookiLogo above their form content (currently missing)
- [ ] PlayerClaimView adds the BookiLogo above its claim code form (currently missing)
- [ ] Logo size is consistent across welcome (currently 220pt), sign-in (currently 160pt), loading (currently 200pt) — standardize to 180pt
- [ ] Transitions between auth screens use `.opacity` only (no `.move` transitions that cause jumping)
- [ ] AppleSignInButton uses Theme colors instead of hardcoded `Color.black`
- [ ] Typecheck passes

## Functional Requirements

- FR-1: A `clearLocalData(context:)` function deletes all records from all SwiftData @Model types
- FR-2: `clearLocalData` is called on logout (before clearing auth session) AND before first sync on login
- FR-3: New bookies see only the Welcome screen during onboarding, then go to dashboard
- FR-4: Both "Set Up Your Group" and "Skip for now" buttons complete onboarding identically
- FR-5: Sensible defaults are applied automatically (auto-accept ON, auto-grade ON, $500 credit limit, weekly reconciliation)
- FR-6: All configuration previously in onboarding remains accessible in Settings
- FR-7: All member management previously in onboarding remains accessible in the Members tab
- FR-8: All game import functionality previously in onboarding remains accessible in the Games tab
- FR-9: All auth screens share consistent background, logo placement, and transition style

## Non-Goals

- Not adding `bookieId` predicates to individual `@Query` declarations (too many locations, the clear-on-auth-change approach is simpler and more reliable)
- Not changing Supabase RLS policies (already correct server-side)
- Not changing SyncService download queries (already correctly filter by bookie_id)
- Not changing Settings view — all configure options already exist there
- Not changing Members tab — invite/add functionality already exists there
- Not changing Games tab — import functionality already exists there
- Not investigating specific "Jeff" player record origin (will be cleared by the data isolation fix)
- Not changing bet status transitions — the issue is visibility, not status logic

## Technical Considerations

- **SwiftData batch delete**: Use `try modelContext.delete(model: Player.self)` for each @Model type — more efficient than looping
- **All @Model types**: Player, Bet, Event, Market, LedgerEntry, AcceptancePolicy, SettlementPeriod, PlayerSettlement, UserAgreement, AuditEvent, Bookie
- **ModelContext access**: AuthManager doesn't currently have a ModelContext — either pass it in, add it as a property, or trigger the clear from AuthGateView/BookiApp which have `@Environment(\.modelContext)`
- **Timing**: Clear must complete before any UI renders with stale data — do it before dismissing the loading screen
- **OnboardingManager** uses `@AppStorage` keys for step completion — simplify to a single `isOnboardingComplete` flag
- **Existing bookies** who already completed onboarding are unaffected (`isOnboardingComplete` is already `true`)
- **Deleted view files** need to be removed from the Xcode project file (`project.pbxproj`) as well

## Success Metrics

- Zero cross-bookie data leakage when switching accounts on same device
- New bookie goes from sign-up to dashboard in 1 tap (down from 4+ screens)
- 4 fewer Swift files in the codebase
- Sync completes correctly after clearing (all current bookie's data re-downloaded)

## Open Questions

- None — scope is clear
