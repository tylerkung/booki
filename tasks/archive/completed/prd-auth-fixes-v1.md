# PRD: Auth Fixes & Player Management Improvements

## Introduction

Fix critical issues with the player invite/claim authentication flow and improve player management UX. Currently, when a player claims an invite, the system incorrectly registers them as a new bookie instead of linking their auth credentials to the existing player record.

## Goals

- Fix player invite/claim flow to properly authenticate players (not create bookies)
- Allow bookies to delete players for easier debugging/management
- Improve settings UX by making logout more accessible
- Add interstitial screen for future monetization (purchase seats)

## User Stories

### US-001: Fix player claim flow - validate invite and link auth user
**Description:** As a player claiming an invite, I want my auth credentials linked to my existing player record so that I can log in as a player (not a bookie).

**Acceptance Criteria:**
- [ ] PlayerClaimView validates invite code and finds existing player record
- [ ] After Supabase auth signup, the player's `auth_user_id` is updated with the new auth user ID
- [ ] Player record's `bookie_id` is preserved (already set when bookie created the player)
- [ ] AuthManager sets `userRole = .player` after successful claim
- [ ] User is routed to PlayerMainView, not ContentView (bookie view)
- [ ] Typecheck passes

### US-002: Move logout CTA to settings initial screen
**Description:** As a user, I want to see the logout button on the main settings screen so I don't have to navigate to find it.

**Acceptance Criteria:**
- [ ] Logout button is visible on the first screen of SettingsView
- [ ] Logout button uses Theme.danger color styling
- [ ] Confirmation dialog appears before logout
- [ ] Works for both bookie and player roles
- [ ] Typecheck passes

### US-003: Add delete player functionality
**Description:** As a bookie, I want to delete a player from my roster so I can clean up test data or remove inactive players.

**Acceptance Criteria:**
- [ ] Delete option available in PlayerDetailView (swipe action or button)
- [ ] Confirmation dialog before deletion
- [ ] Player is removed from local SwiftData
- [ ] Player deletion syncs to Supabase
- [ ] Associated bets and ledger entries are handled (cascade or prevent if has history)
- [ ] Typecheck passes

### US-004: Add player interstitial screen
**Description:** As a bookie, I want to see options when adding a player so I can either add directly or purchase additional seats in the future.

**Acceptance Criteria:**
- [ ] Interstitial screen appears when tapping "Add Player" button
- [ ] Two options displayed: "Add Player" and "Purchase Seats"
- [ ] "Add Player" proceeds to current AddPlayerSheet flow
- [ ] "Purchase Seats" shows placeholder/coming soon message
- [ ] Consistent with app Theme styling
- [ ] Typecheck passes

## Functional Requirements

- FR-1: PlayerClaimView must call an Edge Function or update Supabase directly to set `auth_user_id` on the player record
- FR-2: AuthManager must check if the authenticated user is a player (has player record with matching auth_user_id) and set role accordingly
- FR-3: Logout button must be in SettingsView body, not in a sub-view like AccountView
- FR-4: Delete player must trigger sync to remove from Supabase
- FR-5: Interstitial uses NavigationStack for proper flow

## Non-Goals

- Actual payment processing for "Purchase Seats" (placeholder only)
- Cascade deletion of bets/ledger entries (prevent deletion if player has history, or archive instead)
- Player self-deletion

## Technical Considerations

- PlayerClaimView currently may be calling bookie creation logic - needs to be separated
- Check AuthManager.swift for where user role is determined after login
- SyncService already has upload triggers - reuse for delete sync
- Edge Function `claim_player_invite` may need updates or creation

## Success Metrics

- Players can successfully claim invites and log in as players
- Bookies can delete test players without going to Supabase dashboard
- Logout is accessible within 1 tap from settings
