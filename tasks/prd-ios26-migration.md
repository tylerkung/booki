# PRD: iOS 26 SDK Migration

## Introduction

Apple requires all App Store submissions to use the iOS 26 SDK (Xcode 26) starting April 28, 2026. Booki is currently built with the iOS 18.5 SDK. This migration covers building with the new SDK, embracing the Liquid Glass design language, cleaning up all deprecated APIs, raising the minimum deployment target to iOS 18, and modernizing the observation and concurrency patterns to align with Swift 6.2.

## Goals

- Build and submit Booki with the iOS 26 SDK before the April 28, 2026 deadline
- Embrace Liquid Glass design language while preserving the dark sports-betting brand identity
- Eliminate all deprecation warnings (`.foregroundColor`, `.cornerRadius`, `.tabItem`)
- Migrate 7 `ObservableObject` classes to `@Observable` macro
- Enable strict concurrency checking and resolve all warnings
- Raise minimum deployment target from iOS 17 to iOS 18

## User Stories

### Phase 1: Build System & Project Configuration

#### US-001: Update Xcode project settings for iOS 26 SDK
**Description:** As a developer, I need the project configured for Xcode 26 so the app compiles with the iOS 26 SDK.

**Acceptance Criteria:**
- [ ] Open project in Xcode 26 and resolve any immediate build errors
- [ ] Update deployment target from iOS 17.0 to iOS 18.0 in all 4 targets (`project.pbxproj` lines 788, 845, 926, 944)
- [ ] Update Swift language version from 5.0 to 6.0 in build settings (`project.pbxproj` lines 882, 914, 931, 949)
- [ ] Verify `supabase-swift` 2.40.0 compiles under Xcode 26 / Swift 6.2; update if needed
- [ ] App builds without errors (warnings acceptable at this stage)

---

### Phase 2: Liquid Glass Adaptation

#### US-002: Remove UIKit appearance proxies and embrace Liquid Glass
**Description:** As a user, I want the app to use the new Liquid Glass design so it feels native on iOS 26.

**Details:** The current `configureAppAppearance()` in `BookiApp.swift` (lines 62-90) forces opaque backgrounds on tab bar and navigation bar via `UITabBarAppearance` and `UINavigationBarAppearance`. This conflicts with Liquid Glass. Remove or guard these overrides so the system Liquid Glass styling applies.

**Acceptance Criteria:**
- [ ] Remove or wrap `configureAppAppearance()` in `BookiApp.swift` with `#unavailable(iOS 26)` guard
- [ ] Tab bar renders with Liquid Glass translucency on iOS 26
- [ ] Navigation bar renders with Liquid Glass translucency on iOS 26
- [ ] Tab bar selected/unselected colors still use `Theme.accent` / `Theme.textSecondary` (via SwiftUI `.tint()` and native modifiers, not UIKit appearance)
- [ ] Navigation bar title text still uses `Theme.textPrimary`
- [ ] App still looks correct on iOS 18 (opaque dark appearance preserved via `#unavailable` guard)

#### US-003: Update tab badge styling for Liquid Glass
**Description:** As a user, I want the tab badges to remain legible with the Liquid Glass tab bar.

**Details:** `ContentView.init()` currently configures `UITabBarItem.appearance().badgeColor` and `setBadgeTextAttributes` for brand teal + SpaceGrotesk. This UIKit approach may conflict with Liquid Glass. Test and adapt.

**Acceptance Criteria:**
- [ ] Picks tab badge displays correctly on Liquid Glass tab bar
- [ ] Members tab badge displays correctly on Liquid Glass tab bar
- [ ] Badge text remains legible (dark text on teal, or adapt to Liquid Glass defaults)
- [ ] Guard UIKit badge customization with `#unavailable(iOS 26)` if needed

#### US-004: Visual audit of all screens under Liquid Glass
**Description:** As a user, I want every screen to look polished with the new design language.

**Details:** Recompiling with iOS 26 SDK auto-applies Liquid Glass to standard components. Audit every tab and modal for visual issues — especially where our dark `Theme.background` and `Theme.cardBackground` meet translucent system chrome.

**Acceptance Criteria:**
- [ ] Audit all 6 bookie tabs: Dashboard, Picks, Members, Events, Grading, Settings
- [ ] Audit all 3 player tabs: Games, Track, Account
- [ ] Audit modals/sheets: BetSlipSheet, GradeEventSheet, OverrideGrade, ReverseSettlement
- [ ] Audit auth screens: Login, SignUp, ForgotPassword, PlayerClaim, Onboarding
- [ ] Fix any visual clashes (unreadable text, broken layouts, jarring transparency)
- [ ] Card backgrounds (`Theme.cardBackground`) remain opaque and readable
- [ ] Content in ScrollViews doesn't bleed through nav/tab bars incorrectly

---

### Phase 3: Deprecated API Cleanup

#### US-005: Replace `.foregroundColor()` with `.foregroundStyle()`
**Description:** As a developer, I want to eliminate deprecation warnings from `.foregroundColor()`.

**Details:** 59 occurrences across 8 files. Simple find-and-replace — the APIs are signature-compatible for single color values.

**Files:**
| File | Count |
|------|-------|
| `Views/GameCardView.swift` | 18 |
| `Views/GameDetailView.swift` | 16 |
| `Views/CompactGameRow.swift` | 12 |
| `Views/GamesView.swift` | 3 |
| `Views/EventsListView.swift` | 3 |
| `Views/CompactOddsButton.swift` | 3 |
| `Views/Components/PickCardCompact.swift` | 2 |
| `Theme.swift` | 2 |

**Acceptance Criteria:**
- [ ] Zero occurrences of `.foregroundColor(` in the codebase
- [ ] All replaced with `.foregroundStyle(`
- [ ] No visual regressions (colors render identically)
- [ ] App builds without warnings related to foregroundColor

#### US-006: Replace `.cornerRadius()` with `.clipShape()`
**Description:** As a developer, I want to eliminate deprecation warnings from `.cornerRadius()`.

**Details:** 70 occurrences across 23 files. Replace `.cornerRadius(X)` with `.clipShape(RoundedRectangle(cornerRadius: X))`.

**Files (top 10 by count):**
| File | Count |
|------|-------|
| `Views/GradeEventSheet.swift` | 7 |
| `Views/BetsListView.swift` | 7 |
| `Views/WeeklySettlementView.swift` | 6 |
| `Views/PlayerClaimView.swift` | 6 |
| `Views/UserAgreementView.swift` | 4 |
| `Views/SettlementSnapshotCard.swift` | 3 |
| `Views/PlayerLoginView.swift` | 3 |
| `Views/Auth/SignUpView.swift` | 3 |
| `Views/Auth/LoginView.swift` | 3 |
| + 13 more files | 28 |

**Acceptance Criteria:**
- [ ] Zero occurrences of `.cornerRadius(` in the codebase
- [ ] All replaced with `.clipShape(RoundedRectangle(cornerRadius:))`
- [ ] No visual regressions (corner radii render identically)
- [ ] App builds without warnings related to cornerRadius

#### US-007: Migrate TabView from `.tabItem` to `Tab` API
**Description:** As a developer, I want to use the modern Tab API so the app works optimally with Liquid Glass tab bars.

**Details:** 2 files use the deprecated `.tabItem {}` pattern:
- `ContentView.swift` — 6 bookie tabs
- `PlayerMainView.swift` — 3 player tabs

Replace with `Tab(title:systemImage:) { content }` syntax (available iOS 18+, which aligns with our new minimum target).

**Acceptance Criteria:**
- [ ] `ContentView.swift` uses `Tab` API for all 6 bookie tabs
- [ ] `PlayerMainView.swift` uses `Tab` API for all 3 player tabs
- [ ] `.badge()` still works on Picks and Members tabs
- [ ] Tab selection and navigation still function correctly
- [ ] Zero occurrences of `.tabItem {` in the codebase

---

### Phase 4: Observation Pattern Migration

#### US-008: Migrate AuthManager to @Observable
**Description:** As a developer, I want `AuthManager` to use `@Observable` for better performance and modern patterns.

**Details:** `AuthManager` has 10 `@Published` properties and is used via `@EnvironmentObject` in 20 files. Migration requires:
1. Replace `ObservableObject` protocol + `@Published` with `@Observable` macro
2. Change `@StateObject` to `@State` in `BookiApp.swift`
3. Change `@EnvironmentObject` to `@Environment` in all consuming views
4. Inject via `.environment()` instead of `.environmentObject()`

**Acceptance Criteria:**
- [ ] `AuthManager` uses `@Observable` macro, no `@Published` properties
- [ ] All views using `@EnvironmentObject var authManager` updated to `@Environment(AuthManager.self)`
- [ ] Auth flow works: login, logout, role detection, bookie/player routing
- [ ] App builds without observation-related warnings

#### US-009: Migrate SyncService to @Observable
**Description:** As a developer, I want `SyncService` to use `@Observable`.

**Details:** `SyncService` has 5 `@Published` properties. Used via `@EnvironmentObject` in multiple views.

**Acceptance Criteria:**
- [ ] `SyncService` uses `@Observable` macro
- [ ] All consuming views updated from `@EnvironmentObject` to `@Environment`
- [ ] Sync status, progress, and pending changes still display correctly
- [ ] Pull-to-refresh and manual sync still work

#### US-010: Migrate NetworkMonitor to @Observable
**Description:** As a developer, I want `NetworkMonitor` to use `@Observable`.

**Details:** `NetworkMonitor` has 3 `@Published` properties. Used for offline banner display.

**Acceptance Criteria:**
- [ ] `NetworkMonitor` uses `@Observable` macro
- [ ] Offline banner appears/disappears correctly when connectivity changes
- [ ] All consuming views updated

#### US-011: Migrate remaining ObservableObject classes to @Observable
**Description:** As a developer, I want all remaining services to use `@Observable`.

**Details:** 4 remaining classes:
- `BetSlipManager` (5 `@Published` properties)
- `OddsAPIService` (2 `@Published` properties)
- `RealtimeService` (2 `@Published` properties)
- `FavoritesManager` (1 `@Published` property)

**Acceptance Criteria:**
- [ ] All 4 classes use `@Observable` macro
- [ ] Zero `ObservableObject` conformances in the codebase
- [ ] Zero `@Published` properties in the codebase
- [ ] Zero `@StateObject` usages in the codebase
- [ ] Zero `@EnvironmentObject` usages in the codebase
- [ ] Bet slip, odds API quota display, realtime connection, and favorites all function correctly

---

### Phase 5: Swift Concurrency Compliance

#### US-012: Enable strict concurrency checking and fix warnings
**Description:** As a developer, I want strict concurrency checking enabled so the app is safe under Swift 6.

**Details:**
- Add `SWIFT_STRICT_CONCURRENCY = complete` to build settings
- Fix all warnings: add `@MainActor` annotations, mark `Sendable` conformances, fix isolation boundaries
- Key areas: `BetSlipManager` and `FavoritesManager` are NOT `@MainActor` but access `@Published`/`UserDefaults`
- Swift 6.2 behavior change: nonisolated async functions now run on caller's actor — audit `EdgeFunctionService`, `BetService`, `GradingService` for correctness

**Acceptance Criteria:**
- [ ] `SWIFT_STRICT_CONCURRENCY = complete` in build settings
- [ ] Zero concurrency warnings in build output
- [ ] All `@Observable` service classes have appropriate actor isolation (`@MainActor` for UI-bound services)
- [ ] Edge function calls, sync operations, and bet submission still work correctly
- [ ] No deadlocks or runtime concurrency crashes

---

### Phase 6: Final Verification

#### US-013: Full regression test and App Store submission readiness
**Description:** As a developer, I want to verify the entire app works correctly before submitting to the App Store.

**Acceptance Criteria:**
- [ ] App builds with zero errors and zero warnings under Xcode 26
- [ ] All bookie flows work: create player, place bet, grade, settle, reverse, override
- [ ] All player flows work: browse games, place pick, view track, view account
- [ ] Auth flows work: sign up, login, logout, player claim
- [ ] Sync works: pull-to-refresh, auto-sync, offline banner
- [ ] Liquid Glass looks polished on all screens
- [ ] App runs correctly on iOS 18 device/simulator (backward compat)
- [ ] Archive builds successfully for App Store distribution
- [ ] No ITMS warnings on upload to App Store Connect

---

## Functional Requirements

- FR-1: App must compile with Xcode 26 and iOS 26 SDK
- FR-2: Minimum deployment target must be iOS 18.0
- FR-3: Swift language version must be 6.0
- FR-4: All UIKit appearance proxy usage must be guarded with `#unavailable(iOS 26)` or removed
- FR-5: Liquid Glass must render on tab bars, navigation bars, and toolbars on iOS 26
- FR-6: All `.foregroundColor()` calls must be replaced with `.foregroundStyle()`
- FR-7: All `.cornerRadius()` calls must be replaced with `.clipShape(RoundedRectangle(cornerRadius:))`
- FR-8: All `TabView` + `.tabItem` patterns must be replaced with `Tab` API
- FR-9: All 7 `ObservableObject` classes must be migrated to `@Observable`
- FR-10: All `@StateObject`, `@EnvironmentObject`, `@Published` must be replaced with `@State`, `@Environment`, and `@Observable` properties
- FR-11: Strict concurrency checking must be enabled with zero warnings
- FR-12: All existing functionality must work without regression

## Non-Goals

- No new features — this is purely a migration/modernization effort
- No redesign of custom UI components (cards, pills, chips) — only system chrome adopts Liquid Glass
- No migration to SwiftData model inheritance (iOS 26 feature — keep existing flat model structure)
- No adoption of new iOS 26-only APIs (WebView, Chart3D, etc.) — keep iOS 18 minimum
- No changes to Supabase Edge Functions or backend

## Technical Considerations

- **Liquid Glass + dark theme**: The translucent glass effect on tab/nav bars will show content behind them. Ensure `ScrollView` content has proper `safeAreaInset` or `contentMargins` so text doesn't render under glass chrome
- **`@Observable` migration order**: Start with `AuthManager` (most widely used) to establish the pattern, then propagate to remaining services
- **`#unavailable(iOS 26)` guard pattern**: Use this to maintain iOS 18 backward compatibility for appearance code
- **Swift 6.2 async behavior change**: Nonisolated async functions now inherit caller's isolation. This means `EdgeFunctionService.callFunction()` and similar may now run on `@MainActor` if called from a view. Verify network calls aren't accidentally blocking the main thread
- **Incremental approach**: Each phase can be committed independently. Phase 1 must pass before others begin. Phases 3-5 can run in parallel

## Success Metrics

- Zero build errors and zero warnings under Xcode 26
- App accepted by App Store Connect without ITMS warnings
- No user-facing regressions from the migration
- All deprecated API usage eliminated from codebase

## Open Questions

- Will `supabase-swift` 2.40.0 compile cleanly under Swift 6.2, or do we need to update to a newer version?
- Does the Liquid Glass tab bar support custom badge colors, or do we need to accept system defaults?
- Are there any SwiftData behavioral changes in iOS 26 that affect our model layer (reported iOS 26.1 loading issue)?
