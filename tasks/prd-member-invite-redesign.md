# PRD: Member Invite Flow Redesign

## Introduction

The current member management flow is clunky and over-engineered. Bookies must manually create player records (name, email, username, credit limit), then separately generate invite codes, then manually share them. The UI uses iOS-native List styling that doesn't match the app's dark theme. The "Add to Group" interstitial with a "Purchase Seats" option adds friction for zero value.

This redesign simplifies inviting to a single action: generate a link or share via email. No player data is collected upfront — the member provides everything when they claim the invite. The Members list gets restyled to match the app's card-based dark theme.

## Goals

- Reduce invite flow from 4+ steps to 1 tap (generate link) or 2 taps (email)
- Remove all upfront player data entry (name, email, username, credit limit)
- Keep the member list clean — only show claimed/active members
- Show pending invites separately with expiration countdown
- Restyle the Members tab to match the app's dark card-based theme
- Support three claim paths: new user signup, existing user join, existing user rejection (already in a group)

## User Stories

### US-001: Create Invite model and database table
**Description:** As a developer, I need a lightweight `Invite` model to track invite lifecycle without creating premature player records.

**Acceptance Criteria:**
- [ ] New `Invite` SwiftData model with fields: `id` (UUID), `bookieId` (UUID), `inviteCode` (String, 8-char), `email` (String?, optional), `createdAt` (Date), `expiresAt` (Date, 24hr from creation), `claimedAt` (Date?), `claimedByPlayerId` (UUID?), `needsSync` (Bool), `version` (Int)
- [ ] Supabase migration: `invites` table with matching columns, RLS policies (bookie can read/create own invites, service role for claims)
- [ ] `Invite` added to SwiftData `ModelContainer` schema
- [ ] Typecheck passes

### US-002: Create `create_invite` edge function
**Description:** As a bookie, I want invite creation to be server-authoritative so codes are unique and secure.

**Acceptance Criteria:**
- [ ] New edge function `create_invite` at `supabase/functions/create_invite/index.ts`
- [ ] Request body: `{ email?: string }` (email is optional)
- [ ] Validates JWT — caller must be a bookie (`is_bookie()` check)
- [ ] Generates unique 8-char invite code (same charset as existing: A-Z, 2-9, excluding 0/O/1/I/L)
- [ ] Sets `expires_at` to 24 hours from now
- [ ] Stores invite record in `invites` table with `bookie_id` from auth
- [ ] Returns `{ success: true, invite_id, invite_code, invite_url, expires_at }`
- [ ] `invite_url` format: `booki://invite/{code}`
- [ ] Idempotency key support (matches existing edge function pattern)
- [ ] Emits audit event
- [ ] Deployed with `--no-verify-jwt` (matches existing pattern, validates JWT in code)

### US-003: Create `claim_invite` edge function
**Description:** As a player, I need a server-authoritative way to claim an invite that creates my player record and links me to the bookie.

**Acceptance Criteria:**
- [ ] New edge function `claim_invite` at `supabase/functions/claim_invite/index.ts`
- [ ] Request body: `{ invite_code: string, auth_user_id: string }`
- [ ] Validates invite code exists, is not expired, is not already claimed
- [ ] Verifies auth user exists via `admin.getUserById()`
- [ ] Checks auth user is not already linked to a bookie (query `players` table for `auth_user_id` with `claimed_at IS NOT NULL`)
- [ ] If already linked: returns 409 with `{ error: "already_in_group", message: "You're already a member of another organizer's group." }`
- [ ] Creates new `Player` record: `name` from auth user email prefix (before @), `status: active`, `auth_user_id`, `bookie_id` from invite, `claimed_at: now`, `credit_limit: 10000` (default)
- [ ] Updates invite: `claimed_at = now`, `claimed_by_player_id = new player ID`
- [ ] Auto-confirms email on auth user (invite code serves as verification)
- [ ] Returns `{ success: true, player_id, bookie_id, player_name }`
- [ ] Emits audit event
- [ ] Idempotency key support

### US-004: Restyle Members list to match app theme
**Description:** As a bookie, I want the Members tab to use the same dark card-based styling as the rest of the app instead of iOS-native List styling.

**Acceptance Criteria:**
- [ ] Replace `List { Section { ... } }` with `ScrollView { VStack }` layout on `Theme.background`
- [ ] Each member row uses `Theme.cardBackground` with rounded corners (`Theme.cornerRadiusSmall`)
- [ ] Row shows: player name (bold), status badge (teal capsule), balance (green/red), credit limit, utilization percentage
- [ ] Remove the grouped container/section chrome
- [ ] Remove the `+` nav bar button
- [ ] Remove the filter and layout toggle icons from the top bar
- [ ] Replace NavigationStack toolbar with custom inline "Members" header (matching Dashboard style with `BookiWordmark` leading, `SyncStatusIndicator` trailing)
- [ ] Verify in Xcode Simulator

### US-005: Add Pending Invites section
**Description:** As a bookie, I want to see my outstanding invites so I know who hasn't joined yet.

**Acceptance Criteria:**
- [ ] "PENDING INVITES" section header appears above the member list (only if pending invites exist)
- [ ] Each pending invite row shows: email (if provided) or "Link invite", invite code (monospaced), expiration countdown ("Expires in 23h 14m" or "Expired")
- [ ] Muted visual treatment: `Theme.textSecondary` text, dashed or subtle border instead of solid card
- [ ] Expired invites show in red with "Expired" label
- [ ] Swipe-to-delete or tap to revoke an invite
- [ ] Revoking deletes the invite record (or marks it revoked)
- [ ] Section uses `@Query` filtering on `invites` where `claimedAt == nil`
- [ ] Verify in Xcode Simulator

### US-006: Invite Member sheet (Generate Link)
**Description:** As a bookie, I want to generate an invite link with one tap so I can share it however I want.

**Acceptance Criteria:**
- [ ] "Invite Member" button at the bottom of the member list (full-width, teal accent, `Theme.accent` background)
- [ ] Tapping opens a `.sheet` styled with `Theme.background` (not iOS default)
- [ ] Sheet title: "Invite Member"
- [ ] Two sections: "Share Link" (default/top) and "Send via Email" (bottom)
- [ ] "Share Link" section: tap "Generate Link" → calls `create_invite` edge function → shows the invite URL
- [ ] After generation: displays invite code (large, monospaced), Copy button (copies `booki://invite/{code}` to clipboard with haptic), Share button (opens iOS `ShareLink` / `UIActivityViewController` with the URL)
- [ ] Shows "Expires in 24 hours" below the code
- [ ] Sheet dismisses on "Done" button — invite appears in Pending Invites section
- [ ] Verify in Xcode Simulator

### US-007: Invite Member sheet (Email option)
**Description:** As a bookie, I want to send an invite to a specific email so the member gets it directly.

**Acceptance Criteria:**
- [ ] "Send via Email" section in the invite sheet with a single email text field
- [ ] Email field: dark themed (`Theme.elevatedBackground`), placeholder "Enter email address"
- [ ] "Send Invite" button: calls `create_invite` with the email, then opens iOS Mail compose (`MFMailComposeViewController`) pre-filled with:
  - To: entered email
  - Subject: "You've been invited to join Booki"
  - Body: "You've been invited to join [Bookie Name]'s group on Booki. Open this link to get started: booki://invite/{code}\n\nThis invite expires in 24 hours."
- [ ] If Mail is not available (no mail account configured), fall back to copying the link + showing an alert: "Link copied! Mail is not configured — share the link manually."
- [ ] After sending/copying: shows confirmation "Invite sent!" with checkmark animation
- [ ] Invite appears in Pending Invites section
- [ ] Verify in Xcode Simulator

### US-008: Player claim flow — invite landing screen
**Description:** As an invited user, I want to see who invited me and have clear options to join.

**Acceptance Criteria:**
- [ ] New `InviteClaimView` replaces existing `PlayerClaimView`
- [ ] Handles `booki://invite/{code}` deep link (parse code from URL)
- [ ] Also supports manual code entry (text field with same 8-char formatting as current)
- [ ] After code validation, shows: Booki logo, "You've been invited to join **[Bookie Name]**'s group", bookie name fetched from invite → bookie lookup
- [ ] Two CTA buttons: "Get Started" (primary, teal) and "Already have an account?" (text link below)
- [ ] If code is invalid/expired: error state with "This invite has expired or is invalid" message
- [ ] Styled with `Theme.background`, matching existing auth screens
- [ ] Verify in Xcode Simulator

### US-009: Player claim flow — new user signup path
**Description:** As a new user accepting an invite, I want to create an account and automatically join the bookie's group.

**Acceptance Criteria:**
- [ ] "Get Started" → account creation screen: email field + password field (min 6 chars) + confirm password
- [ ] Styled to match existing auth screens (dark theme)
- [ ] On submit: `supabase.auth.signUp(email, password)` → calls `claim_invite` edge function with invite code + auth user ID
- [ ] On success: shows agreement acceptance screen (existing `submitPlayerAgreement()` flow)
- [ ] After agreement: completes login, player is linked, app routes to player main view
- [ ] Error handling: duplicate email, weak password, network failure — all shown as inline alerts
- [ ] Verify in Xcode Simulator

### US-010: Player claim flow — existing user login path
**Description:** As an existing user, I want to log in and join a bookie's group using my invite link.

**Acceptance Criteria:**
- [ ] "Already have an account?" → login screen (email + password)
- [ ] On successful login: calls `claim_invite` edge function
- [ ] If user has no bookie: shows confirmation screen — "Join **[Bookie Name]**'s group?" with Confirm/Cancel buttons
- [ ] On confirm: `claim_invite` creates player record, links user, routes to player main view
- [ ] If user already has a bookie: shows error — "You're already a member of another organizer's group. You cannot join multiple groups." with a "Back" button
- [ ] Verify in Xcode Simulator

### US-011: Register `booki://` URL scheme for deep linking
**Description:** As a developer, I need the app to handle `booki://invite/{code}` URLs so invite links open directly in the app.

**Acceptance Criteria:**
- [ ] Register `booki` URL scheme in `Info.plist` (CFBundleURLSchemes)
- [ ] Handle incoming URL in app entry point (`onOpenURL` modifier on root view)
- [ ] Parse invite code from URL path: `booki://invite/{code}` → extract `{code}`
- [ ] Route to `InviteClaimView` with the parsed code
- [ ] If app is not authenticated (no session): show `InviteClaimView` directly
- [ ] If app is authenticated as a player: show "Already have an account?" path directly
- [ ] If app is authenticated as a bookie: show alert "Switch to a member account to accept invites"
- [ ] Verify deep link works from Safari and Messages in Simulator

### US-012: Remove old Add Member flow
**Description:** As a developer, I want to clean up the old manual player creation flow that's no longer needed.

**Acceptance Criteria:**
- [ ] Remove `AddPlayerInterstitialSheet` (the "Add to Group" choice sheet)
- [ ] Remove `AddPlayerSheet` (the manual name/email/username/limit form)
- [ ] Remove the `+` toolbar button that triggered the old flow
- [ ] Keep `PlayerService.addPlayer()` for programmatic use (used by `claim_invite`)
- [ ] Keep existing `InviteCodeService` methods that are still referenced
- [ ] Remove old `PlayerClaimView` (replaced by `InviteClaimView` in US-008)
- [ ] No dead code remaining
- [ ] Typecheck passes

### US-013: Sync invites with Supabase
**Description:** As a developer, I need invites to sync between the device and Supabase so pending invites appear correctly.

**Acceptance Criteria:**
- [ ] Add `Invite` to `SyncService` download cycle — fetch invites where `bookie_id` matches current bookie
- [ ] Invites created via edge function are downloaded on next sync
- [ ] Claimed invites update locally (show `claimedAt` and `claimedByPlayerId`)
- [ ] Expired invites are retained for display (filtered in UI, not deleted)
- [ ] Sync uses same version/conflict resolution pattern as other models

## Functional Requirements

- FR-1: Invite codes are 8 characters, uppercase alphanumeric (excluding 0/O/1/I/L), generated server-side
- FR-2: All invites expire 24 hours after creation — no configurable expiration
- FR-3: Invite URLs use custom scheme: `booki://invite/{code}`
- FR-4: Player records are never created until an invite is claimed — member list only shows real members
- FR-5: A user can only belong to one bookie group — `claim_invite` enforces this server-side
- FR-6: Claiming an invite auto-creates a player with: name (email prefix), status active, default credit limit ($10,000), linked auth_user_id and bookie_id
- FR-7: The bookie can revoke pending invites (deletes or marks revoked)
- FR-8: The Members list uses `ScrollView` + `VStack` with `Theme.cardBackground` rows — no iOS List/Section
- FR-9: Existing manually-created players are unaffected — no migration
- FR-10: All edge functions follow existing patterns: JWT validation in code, idempotency keys, audit events
- FR-11: All user-facing strings use compliance language: "Organizer" (not Bookie), "Member" (not Player)

## Non-Goals (Out of Scope)

- No Universal Links / AASA file setup (using custom URL scheme only)
- No server-sent emails (using iOS Mail compose instead)
- No migration of existing players to new Invite model
- No "Purchase Seats" or tier-gated member limits (future feature)
- No bulk invite generation
- No invite resend functionality (bookie generates a new one)
- No player-initiated "find a group" / discovery
- No changes to player detail view (credit limit, status, etc. — bookie edits after claim)
- No changes to the existing `claim_player` edge function (kept for backward compat)

## Design Considerations

- **Members list**: Match `AnalyticsDashboardView` styling — `ScrollView`, `Theme.background`, card rows with `Theme.cardBackground`
- **Inline header**: Use `BookiWordmark` leading + `SyncStatusIndicator` trailing (same as Dashboard)
- **Invite sheet**: Dark themed `.sheet` with `Theme.background`, not system default. Two sections stacked vertically.
- **Pending invite rows**: Subtler than active member rows — use `Theme.textSecondary`, perhaps a dashed border or lower opacity to distinguish from real members
- **Invite Member button**: Full-width, `Theme.accent` background, white text, positioned after the last member row
- **Claim flow screens**: Match existing auth screen styling (centered content, dark background, teal CTAs)
- **Reuse `SummaryCard` pattern** for any card-like elements in the invite sheet
- **Haptic feedback**: On copy-to-clipboard (matching existing pattern in `InviteCodeService`)

## Technical Considerations

- **SwiftData schema change**: Adding `Invite` model requires deleting app from Simulator
- **Edge function shared helpers**: Reuse `_shared/cors.ts`, `_shared/supabase.ts`, `_shared/idempotency.ts`, `_shared/audit.ts`
- **RLS policies**: Bookies can `SELECT`/`INSERT` own invites. Service role needed for `claim_invite` (creates player, updates invite)
- **Deep link handling**: `onOpenURL` in app root, parse with `URLComponents`
- **MFMailComposeViewController**: Requires `import MessageUI` and `UIViewControllerRepresentable` wrapper for SwiftUI
- **Concurrency**: All edge function calls through `EdgeFunctionService` (existing retry logic). Mark relevant functions `@MainActor` for SwiftData writes.
- **Invite code uniqueness**: Edge function should retry generation if code collides (unlikely but possible with 8-char space)

## Success Metrics

- Invite flow completes in ≤ 2 taps (generate link) or ≤ 3 taps (email)
- Zero player records created before claim
- Members list visually matches Dashboard/Picks tab styling
- All three claim paths work: new signup, existing join, existing rejection

## Open Questions

- Should expired invites auto-delete after some period (e.g., 7 days), or persist indefinitely in the Pending section?
- What should the default credit limit be for auto-created players? (Currently set to $10,000 to match existing default)
- Should the bookie receive a push notification when an invite is claimed?
