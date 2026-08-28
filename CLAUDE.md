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
- **Platform**: iOS 18.0+ / Swift 6.0 / SwiftUI (strict concurrency enabled)
- **Local persistence**: SwiftData
- **Cloud backend**: Supabase (Postgres + Auth + Realtime + Edge Functions)
- **Payments**: Stripe (checkout sessions, customer portal, webhooks)
- **Transactional email**: Resend (SMTP relay for Supabase auth emails via `noreply@bookisports.com`)
- **Architecture**: MVVM with Services layer
- **Edge Functions**: Deno/TypeScript, deployed to Supabase with `--no-verify-jwt`
- **Landing page**: Static HTML/CSS/JS in `landing/` directory
- **Domain**: bookisports.com (DNS via GoDaddy)

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
- `StoreKitService.swift` - Apple IAP subscription management (StoreKit 2)
- `landing/dashboard/` - Web dashboard SPA (Alpine.js + Supabase JS)

## Odds API Integration

- **Automated via cron** - Auto-refresh hourly, live scores every 30 min, sync_games twice daily. Odds API paid tier (20,000 calls/month)
- **OddsAPIService.shared** - Singleton with @Published quota tracking
- **API key stored in @AppStorage** - Settings > Odds API section
- **Event.externalId** - Links imported events to API for score updates
- **Supabase migration required** - See SUPABASE_MIGRATIONS.md for events table columns

## Build & Test

- Xcode command line tools don't support full builds - use Xcode IDE
- Delete app from Simulator when SwiftData schema changes
- **Stress tests**: `cd tests && ./run.sh` — 15 suites, 142 assertions against live Supabase. Requires `SUPABASE_URL`, `SUPABASE_SERVICE_KEY`, `SUPABASE_ANON_KEY` env vars. Keys retrievable via `supabase projects api-keys --project-ref vstfauqufwpdytmvjyfz`.

## Edge Functions

All critical betting operations are server-authoritative via Supabase Edge Functions:

- **Location**: `supabase/functions/`
- **Shared helpers**: `_shared/cors.ts`, `_shared/supabase.ts`, `_shared/idempotency.ts`, `_shared/audit.ts`, `_shared/grading.ts`
- **Functions**: `submit_bet`, `accept_bet`, `grade_bet`, `settle_bet`, `adjust_balance`, `reverse_settlement`, `override_grade`, `auto_refresh_games`, `claim_player`
- **Deploy**: `supabase functions deploy <function-name> --no-verify-jwt --project-ref vstfauqufwpdytmvjyfz`
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
| Settlement | Settlement / Settle Up (balance clearing), Settled (pick resolved) |
| Exposure | Open Activity |
| Payout | Potential Return |
| Profit/Loss | Performance |
| Wager | Stake |

- **Invite page was decorative, and migration 010 was the reason**: `landing/invite.html` had zero Supabase calls — it read the last path segment and validated only its SHAPE (`/^[A-Z0-9]{6,12}$/`), so `/invite` rendered the literal word **INVITE** as a copyable code and `/invite/NOTACODE` looked real. A shape test can never tell a code from a word. The reason it was written that way is migration 010's `CREATE POLICY invites_select_by_code ON invites FOR SELECT USING (true)`, commented "safe because invite codes are randomly generated" — **the policy never requires the caller to supply a code**. RLS is row-level and cannot see the WHERE clause, so `USING (true)` hands every row to anyone with the anon key who omits the `invite_code` filter: every open code, every `bookie_id`, every invitee email. Migration 052 replaces it with `get_invite(p_code)` — SECURITY DEFINER, throttled per forwarded IP, code as an *argument* (which IS enforceable), returning a display projection that never includes `bookie_id` or the invitee email. The 010 policy is NOT dropped yet: `InviteClaimView.swift:951` still reads the table directly with the anon key pre-login, so dropping it breaks every shipped iOS build. Tracked as B9 in `tasks/ios-pending.md`; step 3 there is the actual fix.
- **Invite code now reaches signup**: GET STARTED was a bare `/dashboard/` link, so nothing ever redeemed a bearer invite — `claim_invite` was only ever called with `auth_user_id`, which matches *addressed* invites by email and finds bearer codes (`email IS NULL`) never. The page now links `/dashboard/login.html?invite=CODE`; both `login.html` and `dashboard.js` stash it in `localStorage` under `booki_pending_invite` and strip it from the URL, because signup requires email verification and the invitee returns through a link carrying none of the original query string. Cleared only once `claim_invite` succeeds.
- **Deploy order matters for the invite page**: migration 052 must be applied BEFORE `landing/` is pushed. The page treats an unreachable RPC as "we couldn't check this invite" (deliberately — asserting validity on a network error would re-create the exact bug being fixed), so shipping the page first makes every invite show the degraded state.

- **Post-signup questionnaire removed; referral asked on the signup form**: the `#/onboarding` questionnaire (role intent, use case, group size, referral) is deleted. It rendered only on the bookie auto-create branch of `detectUserRole`, so members joining by invite never saw it — and from 3 Mar to 25 Aug the Alpine double-init race meant a new web signup usually lost a `bookies.auth_user_id` UNIQUE collision, hit the `catch`, and was routed to standalone instead. Sixteen organizers in that window produced two answers. "How did you hear about Booki?" now lives on the signup form, so every signup is asked. There is no session at signup, so the answer rides as `user_metadata` on `auth.signUp` and `recordReferral()` persists it on first authenticated load — metadata travels with the account and survives verifying in another browser, which localStorage would not. `onboarding_responses` is kept as the referral store (`role_intent`/`use_case`/`group_size` are now always null); migration 054 gives it `UNIQUE(auth_user_id)` because `attribution_overview` LEFT JOINs it without aggregating, so a duplicate row would silently double that user in every /admin tally. **`send_welcome_email` used to fire from the questionnaire's submit and skip handlers**, so organizers who never saw it never got one; it now fires from `finishOrganizerSetup()` when the organizer record is created.
- **Deleting an auth user was impossible, and it broke member account deletion**: `audit_events.actor_user_id` is `REFERENCES auth.users(id) ON DELETE SET NULL`, but migration 015's `prevent_mutation` trigger blocks every UPDATE on the table — so the FK's own SET NULL could never run and `deleteUser` failed with `P0001: Mutation of audit_events is not allowed`. Organizer deletion worked and hid this, because `delete_account` calls `delete_bookie_data()` first and that RPC disables the triggers and clears the audit rows. A member has no bookie, nothing clears their rows, and `claim_invite` emits an audit event for every member at join — so **Delete Account returned "Failed to delete account" for every member**, on a flow the App Store requires. Migration 053 permits exactly one mutation: `actor_user_id` value → NULL with all other columns byte-identical (compared via `to_jsonb(NEW) - 'actor_user_id'`). Any other edit, a change to a different actor, re-populating a NULL, and all DELETEs still raise; `ledger_entries` and `settlement_events` share the function and keep the absolute prohibition because their hash chain depends on it.

- **`onboarding_responses` answer columns were NOT NULL on the live table but nullable in migration 051**: added out of band and never brought back into a migration, so the repo did not describe the database — the same trap as the two dashboard-created `markets` policies in 046/047. Found by probing inserts against a bogus FK (NOT NULL is checked at tuple formation, before FK triggers, so the probe surfaces every required column and commits nothing), not by reading the schema file. It silently broke two things: **the skip path had never once written a row** — `skipOnboarding()` → `saveOnboarding(false)` sends all-null answers → 23502 → swallowed by a `console.error` catch, so a skip and a never-asked were still indistinguishable despite 051 claiming otherwise (the table held two rows, both fully answered, zero skips) — and the new signup-form referral write, which sets `referral_source` alone. Migration 055 drops the four NOT NULLs. **When a write to this table silently does nothing, suspect live-vs-repo schema drift before suspecting the code.**

- **Member first-run welcome**: organizers got a whole `#/organizer-welcome` route after signup while members got nothing — no confirmation the invite had worked, no explanation of the balance, and no statement that Booki never touches money. A modal now shows once on a new member's first dashboard load: who they joined, that money never moves through Booki, their real credit and win limits, how picks auto-grade, and that everything is recorded. Dismissal persists in `user_metadata.member_welcomed` via `auth.updateUser` — **not localStorage**, which would re-show it on their phone and lose it when storage is cleared. The gate is `no flag && playerBets.length === 0`, which excludes every existing member with no cutoff date or backfill. It is evaluated at the END of `loadPlayerHome()`, the first point `playerBets` is guaranteed populated: checking on role detection would repeat the `loadPlayerTrack` race and drop a welcome modal over an established member's own history. A null session bails rather than defaulting to "not welcomed".

- **Game row is one definition, expanded into both lists**: the Games page and the sport page each had their own copy of the row markup and had already drifted — the sport page was missing both the "More lines" link and the lock overlay. Alpine has no partials, so the canonical row lives in `<template id="tpl-game-row">` and a **plain, non-deferred** script clones it into every `[data-game-row]` slot. The ordering is load-bearing: Alpine is loaded with `defer`, so the expander finishes during parsing and Alpine then binds ordinary markup — no `x-html`, no HTML strings, no escaping of team names. The expander must recurse into `template.content`, because the slots sit inside `<template x-for>` blocks whose contents are DocumentFragments outside the document tree. **Edit the row in one place now; there is no second copy to keep in sync.**
- **Odds button stacks line over price**: `.pg-odds-btn` is `flex-direction: column`, with `.pg-odds-stack` holding the line above the price. Parentheses are gone and `.pg-odds-btn .pg-odds-val` carries `--accent` — scoped to the button so the game-detail board, which uses the same control, matches. The selected state still wins because `.pg-odds-btn.pg-odds-active .pg-odds-val` is more specific. Time and "MORE LINES ›" now share one `.pg-game-head` row, space-between.

- **Board loads markets for every rendered row, not the first two sports**: `loadPlayerGames` used to call `ensureMarketsForSport` on `groupedPlayerEvents.slice(0, 2)`, so every sport below the second showed `—` in all three columns while that sport's own page — which loads its own markets — showed full lines. `ensureMarketsForVisibleEvents()` now collects the ids the board actually draws (at most `BOARD_ROWS_PER_LEAGUE` = 3 games per league, plus each league's outrights) and fetches those, so the work stays bounded regardless of how many sports are listed.
- **Futures get their own board presentation**: an outright event has no away team and no spread or total, so it rendered as a game row reading "Outright" against "NFL Super Bowl Winner" with six em-dashes. `groupedPlayerEvents` now splits each league into `games` and `outrights`; outrights render as a `.pg-futures` block showing the `BOARD_OUTRIGHT_PREVIEW` (8) shortest prices in two columns with "View all N", because the full market is every team in the league. Outright markets are `type = 'outright'` (singular) and are kept in `boardOutrightMarkets` rather than `playerMarkets`, because `playerMarketsByEvent` keys by `event_id` → `type` and would collapse 32 outright rows into one.

- **`--odds-height: 40px` standardises every bet CTA**: applied as `min-height` on `.pg-odds-btn`, which `.gd-cell` and `.gd-side` also carry, so board columns, futures outcomes and the game-detail ladder are all one height. `min-height` rather than `height` so a stacked spread can still grow. Before this a one-line moneyline and a two-line spread were different heights wherever they were not in the same flex row.

- **MLB props: priced and shown, never bettable (yet)**: The Odds API quotes 39 MLB markets (measured 2026-08-28, Reds @ Cubs — 21 of them player props, `batter_total_bases` and `pitcher_strikeouts` at 6 books each), but **balldontlie's `/mlb/v1/stats` returns 401 on the current plan** while `/nfl/v1/stats` and `/nba/v1/stats` return 200. No statline means nothing to settle against, so MLB props are written with `markets.bettable = false` (migration 057): displayed for reference, refused by `submit_bet`, `submit_bets` and `submit_parlay`, and disabled in the UI. Flip `settleable` in `_shared/sport_config.ts` when the plan covers MLB and the next ingest makes them bettable.
- **balldontlie ids are per-sport and they collide**: NFL uses team ids 1..33, MLB 1..30, and **29 of the 30 MLB ids are already an NFL team** — id 1 is New England for NFL and Arizona for MLB. `bdl_teams.bdl_team_id` and `bdl_players.bdl_player_id` were single-column primary keys, so seeding MLB would have quietly rewritten NFL rows and broken the identity resolution that currently works. Migration 056 makes both keys `(sport, id)` and adds `markets.subject_sport` so the FK stays a real constraint. **Every read of these tables must filter by sport** — `resolveSubject` and `resolveBdlGame` now take one.
- **The Odds API calls them "Athletics", balldontlie says "Oakland Athletics"** — 29 of 30 MLB names match exactly and that is the one exception, which is precisely what `bdl_teams.odds_api_name` exists for.

## Current State (March 4, 2026)

- **Branch**: `ralph/web-dashboard-hardening`
- **Swift version**: 6.0 with `SWIFT_STRICT_CONCURRENCY = complete`
- **Deployment target**: iOS 18.0
- **Phases complete**: 1-20 (Core, Player Experience, Auth, Sync, Invites, Odds API, Server Authority, Auto-Pilot, Games Filtering, Acceptance Policy, Grading Improvements, Betting Experience Overhaul, Bookie Analytics v2, Compliance Language Overhaul, Pick Instance Refactor, Alternate Lines, iOS 26 SDK Migration, Default UX & Organizer Upsell, API Optimization & Live Scores, Apple IAP & Web Dashboard, Push Notifications)
- **Supabase migrations**: All applied through 029 (see SUPABASE_MIGRATIONS.md)
- **Edge Functions**: 15+ functions for server-authoritative operations (including `submit_bets`, `submit_parlay`, `sync_games`, `claim_player`, `create_invite`, `claim_invite`, `refresh_live_scores`, `delete_account`, `apple_iap_webhook`)
- **Bookie Events tab**: Player-style compact card layout with sport tabs, search, sticky headers, muted odds buttons (`isViewOnly` mode)
- **Settings**: Streamlined — removed Odds API config, sample data, and sync button
- **Auto-pilot mode**: Singles and parlays auto-accepted, auto-graded, and auto-settled (ledger entries created automatically). Parlays graded per-leg then settled as ticket with combined odds.
- **Auto-refresh**: Processes up to 50 games per run, catch-up grading for missed events, auto-void for stale pending bets, `force` flag for manual triggers
- **Cron jobs**: Auto-refresh hourly (16 runs/day), live scores every 30 min, sync_games twice daily
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
- **Terminology overhaul**: "Reconciliation" replaced with "Settlement" (balance clearing) and "Graded" (bet resolution) across all user-facing strings. Reliability section tracks only `paymentLogged` entries, not auto-grading settlements.
- **Parlay display**: Suppressed "Partial (X/Y)" badge and "will lose" warning when parlay already has a losing leg — shows normal Lost appearance
- **Player bookie RLS**: Migration 013 adds `get_player_bookie_id()` SECURITY DEFINER function + RLS policy so players can read their bookie's settings
- **Golf sport page**: League tabs render outrights directly (no separate Futures tab), "Updated X ago" in section headers, all outcomes shown without show more
- **Auto-refresh**: Hourly (16 runs/day), 50 games per run, hourly idempotency keys so each run executes
- **Live scores**: `refresh_live_scores` runs every 5 min — estimates game end times by sport, only calls API when games are in finishing window (last 30 min of estimated duration). Most runs = 0 API calls. Auto-grades on finalization, settles parlays.
- **Member management polish**: Settle Up (one-tap confirmation), Adjust Balance (custom NumericKeypadView), editable names, credit utilization display, "Owes $X"/"You owe $X"/"Settled" balance labels
- **Members tab**: Search bar + filter chips (All, Attention needed, Overdue, High exposure, Big winners, Big losers), expanded cards with metrics + attention tags
- **Attention tags**: Picks Pending, Overdue, On Heater, Cold Streak, Whale, Degen, Parlay Demon — tappable with explainer modal
- **Recent Activity (detail)**: Merged bets + ledger entries chronologically with View All/Show Less toggle
- **adjust_balance edge function**: Optional `type` param (`paymentLogged` for settle ups, `adjustment` default), optional `reason`
- **Ledger V2**: Atomic settlement RPCs (`settle_bet_tx`, `reverse_settlement_tx`, `override_grade_tx`), tamper-evident hash chain on ledger_entries, immutability triggers, `settlement_events` audit table, canonical `player_balances_view` + `get_player_balance` RPC. Migrations 015-019.
- **Parlay auto-settlement**: `autoSettleParlays()` in auto_refresh_games grades legs to `'graded'`, then settles fully-graded tickets with combined odds and single ledger entry
- **Spurious bookie cleanup**: `cleanUpSpuriousBookieRecord()` in AuthManager auto-deletes leftover bookie records when player is detected, fixing RLS `get_user_bookie_id()` COALESCE issue
- **Invite UX**: Pending invite rows tappable (opens sheet with code), inline copy-code icon next to code, separate Copy Code / Copy Link actions
- **Settings restructure**: Menu page with navigable rows (Profile, Balance Alerts, Pick Management, Export Data, About), all detail pages use ScrollView + `.cardStyle()`, Log Out fixed to bottom
- **Subscription tiers**: Free/Pro/Ultra (replacing active/inactive/trial), legacy cases preserved
- **Events tab cleanup**: Removed plus CTA button and Upcoming/Past segmented picker, sport categories as individual cards
- **Sync status dev-only**: `SyncStatusIndicator` hidden for all accounts except `tylerbkung@gmail.com`
- **Player Account menu**: Activity and About rows in `.cardStyle()` card, `PlayerActivityView` with filter chips
- **Activity row polish**: `UnevenRoundedRectangle` flush-left color indicators, compact row padding, trailing badge spacing
- **SEO foundation**: sitemap.xml, robots.txt, OG/Twitter/canonical tags on all pages, 3 SEO landing pages (PPH alternative, run your own sportsbook, bookie ledger software), blog with 4 posts, JSON-LD schema markup, internal linking pass
- **Landing blog**: `landing/blog/` with index + 4 articles, blog nav link on all pages, Article schema markup
- **iOS 26 app icon**: Liquid glass icon for iOS 26+ with legacy fallback via asset catalog `minimum-system-version`
- **Welcome screen**: Pulsing ring animation behind logo (`TimelineView`), flat teal CTA, "Be The House" (no period)
- **Player tab headers**: `AppHeaderView` with optional centered title + showBalance toggle; all 4 tabs show titles
- **Change Password**: `ChangePasswordView` using Supabase auth update, available in both bookie Settings and player Account
- **About page links**: Website, Terms of Service, Privacy Policy, Twitter with `openURL`
- **Terms of Service redesign**: Icon-based key points summary, "Back" button for sign-out
- **Bookie Settings Log Out**: Inline row in card (matching player Account style), no longer fixed bottom button
- **Tier source of truth**: All views read `bookies.first?.tier` from SwiftData `@Query`, not `@AppStorage`. Debug toggle writes to SwiftData `Bookie.tier`.
- **Duplicate ledger fix**: Removed optimistic local inserts from SettleUpSheet, AdjustBalanceSheet, GradingService. After edge function success, triggers `syncService.syncTable(.ledgerEntries)` to pull server entry immediately.
- **Dashboard PnL**: Ledger-entry-based net balance excluding `paymentLogged` entries (settle ups don't affect PnL)
- **Change Password**: Requires current password re-authentication before update, disabled button matches login CTA gradient styling
- **Landing animations**: Scroll-reveal via IntersectionObserver (`.reveal`, `.reveal-scale`, `.reveal-stagger`), section divider fade-in, `prefers-reduced-motion` respected
- **Landing pricing**: Free ($0) + Pro ($49.99) + faded Traditional PPH (~$10/head/week) comparison column
- **Pro tier spec**: `docs/pro-tier-spec.md` — pricing, feature gates, enforcement, upgrade flows, payment plan
- **sync_games markets**: Uses `h2h,spreads,totals` only (alternate markets require paid Odds API tier)
- **Stripe integration**: `create_checkout_session`, `create_customer_portal`, `stripe_webhook` edge functions for Pro subscription ($49.99/mo). Webhook handles `checkout.session.completed` and `customer.subscription.updated/deleted` to sync tier.
- **Account deletion**: `delete_account` edge function cancels Stripe subscription, deletes all bookie data in FK order, unlinks player records, deletes auth user. Two-step confirmation UI on both bookie Settings and player Account.
- **Privacy manifest**: `PrivacyInfo.xcprivacy` declares email, name, userID, purchase history collection + UserDefaults API access (CA92.1)
- **Age gate**: SignUpView requires 18+ confirmation checkbox before account creation
- **Email verification**: Supabase email confirmations enabled, sent via Resend SMTP from `noreply@bookisports.com` (custom domain verified with SPF/DKIM/DMARC)
- **Dashboard time selector**: 1D/1W/1M/All tabs filter headline PnL number, label updates dynamically
- **Player pick history**: `PlayerPickHistoryView` + `PlayerPicksListView` with open/graded toggle, max 5 shown on member detail with "See All"
- **Member detail restructure**: Recent Activity as single navigable row, picks section with open/graded filter below
- **Settings reorder**: Profile, Change Password, Subscription, Pick Management, About, Log Out (removed Balance Alerts + Export Data)
- **ProUpgradeSheet**: Non-scrolling layout — enlarged logo with accent glow, feature list fades out via gradient mask, sticky CTA bottom area
- **Primary button style**: `.primaryButtonStyle()` modifier in Theme.swift — subtle skeuomorphic shadow, applied to all CTA buttons
- **Terms/Privacy updates**: Subscription billing section, Stripe references, pro-rated refund clause, payment data handling
- **Verification pending screen**: Full-screen post-signup view with email display, resend button, back-to-login CTA (replaces alert)
- **Invite emails via Resend**: `create_invite` sends branded HTML email via Resend API when email provided — no more iOS native mail composer
- **Email templates**: `landing/email-confirm.html` (verification), `landing/email-invite.html` (invite) — dark theme, Booki branding
- **Verify landing page**: `landing/verify.html` handles email confirmation token, branded loading/success states, "Open Booki" deep link
- **Delete Account UI**: Separated from main settings card, standalone muted text button at page bottom
- **Member Settings**: `MemberSettingsView` — bookies set `default_credit_limit` for new invitees, `claim_invite` reads it (fallback 1000). Migration 022.
- **Credit limit editing**: Tappable credit line + overflow menu on member detail, saves to Supabase + SwiftData
- **Dashboard credit fix**: Uses `BalanceService.playerSummary()` (includes open stakes) instead of raw ledger sums
- **BetSlip navigation**: Up/down arrows for navigating singles fields, quick stakes +$1/+$5/+$25 with equal width
- **OG image**: All landing pages use `bookie-og.jpg` for og:image and twitter:image
- **Player profile editing**: `PlayerProfileEditView` — players edit name (Supabase RLS) and email (auth confirmation flow), CTA on AccountView
- **Bookie display_name**: `display_name` column on players table — bookie-only override, `bookieDisplayName` computed property falls back to player's name
- **isPro unified logic**: `Bookie.isPro` checks both `tier == .pro` and `subscriptionStatus in [.active, .pro]`
- **Picks tab filters**: Member dropdown (`.menu` picker) + Singles/Multi-Pick/Futures type chips, replacing player name chips
- **Downgrade enforcement**: `create_invite` checks active member count vs tier limit (3 free / 50 pro), returns `member_limit_reached`
- **Member limit UI**: Capacity banner on Members tab, blocking message in invite sheet when at limit
- **Email change template**: `landing/email-change.html` — branded Supabase email change confirmation
- **Debug tier toggle removed**: Triple-tap on version number no longer toggles tier
- **Dashboard balance fix**: Shows `balanceOwed` (ledger only) not credit used (which included open stakes)
- **Default standalone UX**: New users route to PlayerMainView (no bookie record), synthetic player with $10K credit and 25 open bet limit
- **Organizer upsell**: `BecomeOrganizerView` in Account menu, creates bookie record on tap
- **Step down organizer**: `step_down_organizer` edge function, available in Settings when no active members/invites
- **Apple IAP**: StoreKitService (StoreKit 2), `apple_iap_webhook` edge function, `subscription_source` column prevents cross-platform conflicts, ProUpgradeSheet uses live IAP ($59.99/mo), ProCheckoutView deleted
- **Web Dashboard**: `landing/dashboard/` — Alpine.js SPA with auth, dashboard, members, picks, subscription views. Stripe checkout ($49.99/mo) for web users. Hash-based routing, dark theme CSS, responsive sidebar.
- **Delete bookie data RPC**: Migration 025, `delete_bookie_data()` SECURITY DEFINER atomically disables immutability triggers and deletes in FK order
- **Hourly auto-refresh**: Cron runs every hour (was 2h), 50 game cap (was 25)
- **Smart live scores**: `refresh_live_scores` edge function every 5 min, sport duration estimation, only fetches when games near ending
- **Odds API**: Upgraded to 20,000 calls/month paid tier
- **Market bookie_id fix**: `auto_refresh_games` now always sets `bookie_id: null` on shared markets (was incorrectly stamping bookie_id from bets)
- **Bookie activity navigation**: `PlayerPickHistoryView` rows are tappable — bets → `BetDetailView`, ledger → `BookieTransactionDetailView`. Settlement entries consolidated into bet rows.
- **Override simplified**: Removed "Reverse Settlement" button (terminology conflict with settle up). "Override Grade" renamed to "Override" — handles reversal + re-grading in one step.
- **Member detail picks**: Shows only open picks (removed Open/Graded segmented picker)
- **Members list credit fix**: Shows actual credit used (including open stakes) instead of just balance owed
- **IBM Plex Sans global font**: Fixed font files (were HTML, re-downloaded as real TTF binaries), fixed PostScript name mismatches (`IBMPlexSans` not `-Regular`, `IBMPlexSans-Medm` not `-Medium`), set as global default via `.font(Theme.body)` on root view. Nav bar titles use Space Grotesk Bold via UIKit appearance.
- **Expired invites auto-delete**: PlayersListView cleans up expired invites from Supabase + SwiftData on appear
- **Subscription member count fix**: `upsertPlayer` now syncs `authUserId` from server; `activeMemberCount` uses `status != .archived`
- **Features page redesign**: Mixed layouts (hero feature, 3-card grid, wide splits with mock UI, teal platform strip), scroll reveal animations, no more repetitive zig-zag
- **Dashboard login polish**: Radial gradient bg, teal glow card, gradient CTA, `isOrganizer()` auth hardening
- **Blog scheduling**: `data-publish` attribute hides future-dated posts on blog index until publish date
- **Bottom-funnel blog posts**: 4 new posts (how-to-be-a-bookie-for-friends, wagerlab-vs-booki, best-bookie-software-small-books, best-pph-software-small-bookies), FAQPage schema on 2 posts, staggered publish dates (2/week)
- **Nav login link**: "Log In" → `/dashboard/` added to all 16 landing pages (desktop `nav-actions` wrapper + mobile nav-link)
- **Nav CTA fix**: `.btn-nav` overflow fixed with `justify-self: end; width: fit-content`
- **Tweet bank**: `tweets.json` with 100 pre-written tweets, `/tweet` skill for random pick + remove
- **Push notifications**: APNs HTTP/2 direct delivery via `_shared/notifications.ts`, `send_notification` edge function, `NotificationService.swift` (permission, token registration, badge, deep link routing), `device_tokens` + `notification_preferences` tables (migration 028), notification integrations in auto_refresh_games/adjust_balance/claim_invite/submit_bet/submit_bets/decline_bet, member + organizer notification preferences UI
- **NotificationService pattern**: `@unchecked Sendable` with per-property `@MainActor` isolation — `@MainActor` on the whole class crashes because UNUserNotificationCenterDelegate methods are called on a private serial queue
- **APNs auth**: Token-based `.p8` key, ES256 JWT cached 50 min, secrets: `APNS_KEY_P8`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_ENVIRONMENT`
- **Multi-Pick card layout fix**: Chevron inline with title/status pill, leg dots inline with stake/profit line
- **Bet slip UX**: Available credit shown as "max" instead of balance/limit, Multi auto-switches to Singles when selections drop below 2, Multi button disabled with 1 selection
- **Confirmation messages**: 25 singles + 9 multi-pick messages randomized on submission, displayed in BetSlipSheet success view
- **Loading screen**: Spinner removed, just centered Booki logo with accent glow
- **Notification hardening**: APNs 10s fetch timeout, expanded stale token cleanup (6 error reasons), deferred token registration with `retryPendingToken()` after auth ready, logout captures userId before clearing auth
- **Deep link fix**: PlayerMainView now handles `booki://bet/` links (was missing), cold-start guard prevents navigation before player data loads
- **Smart odds refresh**: `auto_refresh_games` uses 15-min idempotency windows (was hourly), only refreshes odds for games starting within 4 hours (sync_games handles the rest)
- **Final scores on picks**: Singles show final score (away-home) inline with stake/profit on both TrackView list cards and TicketDetailView, baseline-aligned
- **Web-first repositioning**: All ~16 landing pages updated from iOS-first to web-first messaging, `#waitlist` CTAs replaced with `/dashboard/` "Get Started Free" links, removed app-specific language
- **Become an Organizer flow**: Standalone users see CTA on Account page + sidebar, detail page explains benefits/how it works, `becomeOrganizer()` creates bookie record, success page with next steps before dashboard
- **step_down_organizer**: Redeployed for CORS fix
- **Web bet slip sidebar**: Desktop gets persistent right sidebar (340px, `--betslip-width`) instead of floating bar + modal. Slides in/out with selections, main content reflows. Mobile keeps existing floating bar + modal. `hasBetSlip` computed getter drives visibility.
- **Web bet slip bidirectional staking**: Side-by-side Stake/Potential fields with reverse calculation (`calcStakeFromToWin`). `sanitizeMoney()` enforces 2 decimal max. Focus tracking (`betSlipActiveField`) prevents `:value` overwriting during typing. Summary section (pick count, total stake, total return) in footer.
- **Web odds button styling**: Selected state = solid teal bg + dark text; hover = teal text on dark bg. Spread/total show line in secondary color, odds in primary with parentheses `(odds)`. `::after` nbsp spacing between line and value.
- **Web futures 2-column grid**: Outright markets render in `grid-template-columns: 1fr 1fr` layout. Fixed Alpine `:style` string overwriting inline `display:flex` — use object syntax instead.
- **Web bet submission fix**: `side` field now sends `side_indicator` ('a'/'b') to edge functions instead of display name
- **Win limit**: Per-member win limit (`win_limit` + `win_limit_action` on players table) caps net winnings. `block` = picks suspended, `require_approval` = picks go pending. Server-enforced in `submit_bets`/`submit_parlay` via ledger balance check. Bookie defaults on bookies table (`default_win_limit`/`default_win_limit_action`), applied via `claim_invite`. iOS: editable on member detail + MemberSettingsView defaults + bet slip warning/block. Web: inline editing on member detail + bet slip validation. Migration 029.
- **Web member detail tooltips**: Styled tooltips on Credit Limit, Win Limit, and Active/Pending badge using existing `showTagTooltip`/`hideTagTooltip` system
- **Settlement table fix**: Removed last-row bottom border, fixed `settlementMarkPaid()` to check `response.error` from `callEdgeFunction`
- **Stress tests**: 15-suite Node.js test suite in `tests/` — 142 assertions against live Supabase covering auth, bets, parlays, idempotency, grading, settlement, overrides, balance adjustments, ledger integrity, concurrency, invites, accept/decline, credit/win limits. Known bug: `settle_bet_tx` RPC column mismatch.
- **Lifecycle emails**: `lifecycle_emails` table (one row per user+type, unique constraint prevents double sends) + `get_dormant_organizers()` RPC + daily cron at 17:00 UTC. First use: `send_followup_email` edge function emails organizers 10+ days old with zero invites and zero members, 50 per run. Migration 030.
- **Email architecture note**: Two separate systems. (1) Supabase Auth emails (confirm/reset/email-change) — templates in Supabase Dashboard, delivered over Resend SMTP as `noreply@bookisports.com`. (2) Direct Resend API calls from edge functions (`send_welcome_email`, `create_invite`, `send_followup_email`) — HTML inlined in the function as a TS template literal, sent as `tyler@bookisports.com`. The `landing/email-*.html` files are browser-previewable copies only and are NOT read at send time, so edits must be made in both places.
- **bookies.email fix**: Both `dashboard.js` bookie-creation paths (auto-create on first login ~line 821, `becomeOrganizer()` ~line 1492) omitted the `email` column, leaving it NULL for every web-created organizer — iOS (`BookieService.swift:172`) always set it. Both sites now pass `this.session.user.email`. Migration 031 backfills existing rows from `auth.users` (27 rows corrected; auth.users is the source of truth, so it syncs stale values too, not just NULLs).
- **Follow-up email LIVE** (unpaused 2026-08-26): `send_followup_email` has `PAUSED = false`. The daily 17:00 UTC cron sends to dormant organizers — 10+ days old, zero invites, zero members, 50 per run. Verified before unpausing: 15 candidates, all real addresses, no `test_stress` or `example.com` accounts reaching the list, so the 13 suppression rows in `lifecycle_emails` are holding; every link in the email body returns 200. The count moved from the previously recorded 12 because three more organizers crossed the 10-day threshold — intended behaviour, not drift. **A fresh `tests/run.sh` run still creates NEW `test_stress_*` auth users that are not suppressed**, so re-check the dry run (`{"dry_run": true}` reports candidates without writing) after running the suite. To pause: flip `PAUSED` to true and redeploy; while true the run is a no-op and writes no `lifecycle_emails` rows, so nobody is burned.
- **Invite code display fix**: `create_invite` returns `invite_code`, but `dashboard.js` `createInvite()` read `response.code` — always `undefined`, so the success block (`x-show="inviteCode"`) never rendered and the modal looked like it failed. The invite was created correctly every time; only the web display was broken (iOS reads `response.inviteCode`, unaffected). Also fixed `copyInviteLink()`, which copied "Download Booki and use invite code: X" instead of the actual `https://bookisports.com/invite/{code}` URL.
- **Pending Invites table fix**: Same `invite_code` vs `code` mismatch in `landing/dashboard/index.html` — the CODE cell (line 956), Copy Code (961), and Copy Link (964) all read `inv.code` from a `select('*')` that returns `invite_code`. Code column rendered blank and both copy buttons produced `undefined`.
- **Invite credit limit removed**: The invite modal's Credit Limit input was dead — `create_invite` never read the param, `invites` has no such column, and `claim_invite` always applies the bookie's `default_credit_limit`. Field removed; modal now states which default will apply, and the Pending Invites table shows `bookie.default_credit_limit` instead of a hardcoded `|| 1000` fallback. Per-invite limits would need a `credit_limit` column on `invites` plus create/claim wiring.
- **Invite page redesign**: `landing/invite.html` rendered completely unstyled at `/invite/{CODE}` — it linked `styles.css` relatively, which the Netlify rewrite answered with HTML, and `X-Content-Type-Options: nosniff` made the browser refuse it. Rewritten self-contained (inline CSS + own variables, no `styles.css` dependency, absolute asset paths) so the rewrite can't break it again. Adds dark card + radial teal glow, copy-code button with toast, `Space Grotesk` via Google Fonts, a graceful "link incomplete" state for `/invite.html` with no code (previously rendered the filename as the code), `?code=` query fallback, and `noindex`.
- **PostgREST 1000-row cap (critical)**: An unbounded `.select()` silently returns at most 1000 rows — no error, no warning. This caused mass event duplication: `sync_games` used a plain `.in('external_id', ids)` to decide which events already existed, so once matches exceeded 1000, everything past the cap looked new and was re-inserted every run (25,133 rows for 5,964 real games; one game duplicated 41×). Duplicates also got no markets, so odds rendered as "—". Fixed via `_shared/pagination.ts` `selectAllIn()`, which chunks the IN list AND pages each chunk. Use it for any query whose result set can exceed 1000 rows. Still unpaginated: `refresh_live_scores:141`, several selects in `auto_refresh_games`.
- **sync_games 150s timeout fix**: Forced runs were failing at Supabase's 150s edge-function ceiling. Root cause was per-row market UPDATEs (one request each, ~1,450 per run) — masked initially because the first post-dedupe run inserted every market (`markets_updated: 0`) and never hit that loop. Now batched via chunked `upsert(chunk, {onConflict:'id'})`. Also: events existence check uses one paged read instead of a chunked IN, the second full table read was replaced by merging the upsert's returned rows, Odds API fetches run at concurrency 5 (25 sequential feeds before), and unchanged events are skipped. Change detection compares `start_time` with `Date.parse` — the Odds API returns `...Z` and PostgREST returns `...+00:00`, so a string compare marked every event changed and silently disabled the skip. Runtime 150s+ (fail) → 79.4s.
- **Phase 3 odds lifecycle**: `sync_games` no longer stores markets for non-outright games starting >7 days out (`ODDS_STORAGE_WINDOW_MS`), and sweeps markets for ALL final games on every run. Outrights exempt from both — futures are long-dated and a start-time rule would delete them all. One-time sweep removed 18,480 markets (19,813 → 1,333). Verified the window holds: a following sync inserted 0 and left the count at 1,333. Sync payload 9.8 MB → ~4.5 MB, projected egress ~2.9 GB/mo → ~1.4 GB. Phase 4 (client sync date filter) deferred — no longer needed, and it only reaches users via an App Store build.
- **Market prune is a sweep, not a hook**: Three code paths mark a game final — `sync_games`' cutoff step, `refresh_live_scores:233`, and `auto_refresh_games:1607`. Hooking only the first missed games finalized by a real result landing, i.e. exactly the games people bet on, so their odds would accumulate forever. The prune now reads the (small) markets table, asks which of those events are final, and deletes the non-outright matches — covering all three paths. Runs outside the `skipOddsSync` branch, so it must not reference anything scoped inside it.
- **48h member display window**: Members see games starting within 48 hours; outrights are exempt so futures (Super Bowl, championship winners) stay bettable all season. Web: `ODDS_DISPLAY_WINDOW_MS` + `oddsDisplayFilter()` in `dashboard.js`, applied as `.or('start_time.lte.<cutoff>,away_team.eq.Outright')` in `loadPlayerGames()` and `loadSportPage()` — the outright arm is essential, since futures come from the same events array and a plain upper bound hides all 9 live ones. iOS: `Event.displayWindow` / `Event.isWithinDisplayWindow(now:)` / `Event.isOutrightEvent`, used by GamesView, SearchView and SportPageView's player branch; the old duplicated 14-day `upcomingHorizon` was removed from the two player views. `EventsListView` is bookie-facing and keeps its 14-day horizon.
- **Odds API quota logging**: `_shared/odds_quota.ts` records `x-requests-last/used/remaining` from every Odds API response across all 7 call sites in `sync_games`, `auto_refresh_games`, `refresh_live_scores`. Each function returns a `quota: {run_cost, calls, used, remaining}` block, so usage is visible from a normal invocation. `resetQuota()` MUST be called at handler entry — isolates are reused between invocations and the counters would otherwise accumulate across unrelated runs. Measured 2026-08-18: full `sync_games` run = 30 credits / 27 calls; `auto_refresh_games` = 1 credit per distinct sport key among games with open bets (outrights each have their own futures key, so they don't consolidate). Period usage 3,798 of 20,000.
- **Tiered odds refresh**: `auto_refresh_games` cron moves to every 30 min (migration 033) and the function filters per game: within 4h refreshed every run for NFL/NBA/MLB and hourly for other leagues (`HIGH_FREQUENCY_LEAGUES`), 4–48h every 2 hours (even UTC hours, `:00`), outrights once daily (12:00 UTC), beyond 48h never (sync_games handles it). Cron fires at the FASTEST tier and the function filters down — changing the schedule silently changes the near-tier cadence. Migration 033 unschedules every `auto-refresh%` job by loop rather than by name, since naming drifted across migrations 008/014 and a leftover job would double spend. Doubling cadence does not double cost: outrights each carry their own futures key and were previously re-priced hourly, which is where most of the spend was going.
- **Organizer events horizon**: `EventsListView` now uses `Event.organizerHorizon` (6 days) instead of a hardcoded 14. Deliberately a day inside `sync_games`' 7-day odds storage window — sync runs twice daily, so a game that just crossed into storage can be priceless for up to 12h; 6 days guarantees two syncs have covered anything shown. Before: 42 games visible, 9 without odds. After: 33 visible, 0 without odds.
- **Price guardrail (phase 1)**: `submit_bets`, `submit_bet` and `submit_parlay` previously stored `odds` verbatim from the request body and never read `odds_a`/`odds_b`, so ANY price could be submitted (a coin flip at +5000 would have been accepted and paid). All three now load the stored price and reject when the submitted price is BETTER for the member than the one on offer, compared via `americanToDecimal`. Deliberately one-sided: a line moving against a member still goes through, so this ships without client changes. Symmetric validation and the "line has changed, confirm the new price" flow are phase 2 — see `tasks/prd-line-change-guardrails.md`.
- **Superseded line rejection**: Market rows are keyed `event + type + LINE VALUE` (`sync_games:913`), so a spread moving -3 → -3.5 INSERTS a new row and never updates the old one. The -3 row lingers, still bettable, frozen at its old price — and it passes a pure odds comparison because its odds genuinely are what that row says. All three submit endpoints now reject a market whose `updated_at` trails its event's `last_odds_update` by more than 15 minutes, which is how a no-longer-offered line identifies itself without any client change.
- **Parlay guards must run BEFORE `body.legs.map()`**: returning a `Response` from inside a map callback puts the Response object into the inserts array instead of aborting the request. Validation for legs lives in a separate `for` loop ahead of the map.
- **Line change confirmation (phase 2)**: A moved line now returns `error: 'line_changed'` with `market_id`, `submitted_odds`, `current_odds`, `current_side` from all three submit endpoints. Web bet slip renders a confirmation showing old → new price; confirming is an ordinary resubmission that runs the same validation again, so there is no honoured-price window. A line moving IN the member's favour is auto-upgraded to the better price on singles (not on parlays — combined odds are computed client-side, so silently changing a leg would desync the ticket). No capability flag was needed: phase 1 already rejected this exact case, so phase 2 only changed the response shape. **iOS bet slip still needs this** — it will show a generic error until updated.
- **Odds refresh cadence (current)**: `auto_refresh_games` runs every 30 min and filters per game — NFL/NBA/MLB inside 4h refresh every 2 hours, everything else in the 48h window every 4 hours, futures daily, beyond 48h never (sync_games covers it). Refresh is bet-agnostic: games with no picks are included, since one odds call covers a whole sport and costs the same either way. Projected ~17% of the Odds API allowance today, ~50% at peak season overlap. The earlier 30-min cadence priced out at ~139% at peak. An odds call costs 3 credits (h2h+spreads+totals × one region); an outrights or scores call costs 1.
- **Admin dashboard**: `landing/admin/` — read-only platform browser at `/admin/`, gated by the `ADMIN_EMAILS` secret on the `admin_query` edge function (non-admins get 404, never 403). Views: overview, users (every auth user with resolved role — organizer / member / unlinked), organizers, members, pending invites, outstanding picks, balances. Foreign keys render as names, not UUIDs. Reuses `dashboard.css`; `landing/admin/admin.css` adds only what's missing. Read-only on purpose — writes must go through the existing edge functions or they bypass idempotency, audit and the ledger hash chain. Spec: `tasks/prd-admin-dashboard.md` (US-005 global search, US-006 SQL runner, US-007 data-quality checks still unbuilt).
- **Admin SQL runner (US-006)**: `admin_query`'s `sql` view opens its own Postgres connection (`SUPABASE_DB_URL`) and runs `BEGIN READ ONLY`, because `transaction_read_only` **cannot be set inside a plpgsql function** — Postgres rejects it as both `SET LOCAL` and a function-level `SET` clause ("cannot be set locally in functions"). Two enforced controls, no keyword matching: the query is wrapped as a `FROM` subquery (blocks DML, DDL, data-modifying CTEs — Postgres requires those at the top level) and the read-only transaction blocks writes reached via a function call. That second control is the one that matters here: 17 of 20 public functions are `SECURITY DEFINER`, including `delete_bookie_data`, so a read-only *role* would not have helped — SECURITY DEFINER runs as its owner, while the read-only check is in the executor and role-independent. Verified with `nextval()` on a sequence the connection can write: `25006 cannot execute nextval() in a read-only transaction`. Also: int8 arrives as a JS `BigInt` which `JSON.stringify` throws on, so `count(*)` broke the whole response until `toJsonSafe()` was added; a multi-statement string kills the driver's isolate rather than erroring, so a structural single-statement guard runs first; and Supabase's gateway WAF blocks the literal `; drop table` signature before it ever reaches the function.
- **Alpine double-init trap**: Alpine 3 automatically calls a method named `init()` on the `x-data` object, so `<body x-data="app()" x-init="init()">` runs it **twice**. Both `landing/dashboard/index.html` and `landing/admin/index.html` had this. Symptom that surfaced it: copying an id in the admin dashboard raised two toasts, because the `[data-copy]` click listener was bound twice. On the dashboard the same bug ran `detectUserRole()` (which auto-creates a bookie record for a new user), `subscribeToRealtime()` and a `hashchange` listener twice on every load. Fixed by removing `x-init` — the auto-call is the one to keep. Verified: one synthetic click on a `data-copy` element produced two toasts before, one after, and the dashboard now holds a single realtime channel.
- **Migrations are NOT atomic in the Supabase SQL editor**: it does not wrap a script in a single transaction, so each statement commits on its own. Migration 046 proved this — its `ALTER TABLE ... ENABLE ROW LEVEL SECURITY` and `CREATE POLICY` committed while its closing assertion raised, leaving a partially-applied migration. A `DO $$ ... RAISE EXCEPTION` block at the end catches a bad end-state but does **not** undo the statements before it. Write migrations so a partial application is safe, and prefer idempotent statements (`IF NOT EXISTS`, `DROP ... IF EXISTS` then `CREATE`) so a re-run after a failure is harmless.
- **Cron wrappers must write the edge-function URL out in full**: `call_*` wrappers built their target as `current_setting('app.edge_function_base_url', true) || '/name'`, and that setting is **not set** on this database. `current_setting(..., true)` returns NULL instead of raising, and `NULL || text` is NULL, so the job posted to a null url and died on a not-null constraint. Nothing surfaces — the edge function is never invoked, so there are no function logs, only a row in `cron.job_run_details`. Three jobs had been failing every run this way (`grade-player-props`, `sync-player-props`, `send-followup-email`). It went unnoticed because `call_auto_refresh_games` works: the **live copy does not match migration 008**, someone replaced it with the URL written out, and that fix never came back into a migration — so the repo's pattern looked proven and migrations 030 and 049 both copied a version that had never run. Migration 050 fixes all three and asserts none still reads the setting. **Check `cron.job_run_details` after scheduling anything**; a cron job that errors is completely silent otherwise.

- **`markets` had unenforced RLS until migration 046/047**: `markets_select` existed from migration 011 but nothing ran `ENABLE ROW LEVEL SECURITY`, so it was inert. Enabling it then revealed **two more policies created via the dashboard and absent from this repo** — `"Bookies can read their own or shared markets"` and `"Bookies can manage their own markets"` — which compared `bookie_id` (a `bookies.id`) against `auth.uid()` (an auth user id), two id spaces that never match. Only their `bookie_id IS NULL` arm ever did anything, and because PERMISSIVE policies are OR'd, it granted every shared market and overrode the restriction in `markets_select`. **When a policy change appears to have no effect, list every policy on the table** — the repo is not a complete record of what exists.
