# PRD Backlog — Running Items for Ralph

Items accumulate here. When ready, convert to `prd.json` for Ralph execution.

---

## 1. Downgrade Enforcement — Soft Lock on Invites

**Context**: When a Pro bookie cancels their subscription and drops to free tier, they may have more than 3 active members. We need to handle this gracefully.

**Behavior**:
- Existing members stay active — no one gets kicked, no data deleted, no betting restrictions
- New invites are blocked until active member count is at or below the free tier limit (3)
- `create_invite` edge function: count active members (`auth_user_id IS NOT NULL`) for the bookie, compare against tier limit, reject with `member_limit_reached` if over
- Members tab: show an inline banner when over capacity — "You have X members on the Free plan (limit: 3). Upgrade to Pro or archive members to invite more."
- Invite sheet: if over limit, show the same blocking message as hitting capacity on free tier (already specced in `prd-freemium.md` §1)

**Enforcement points**:
| Location | What happens |
|----------|-------------|
| `create_invite` edge function | Reject with `member_limit_reached` error |
| `InviteMemberSheet` UI | Show limit message + upgrade CTA |
| Members tab banner | Informational — "X of 3 members" when at/over capacity |

**What does NOT change on downgrade**:
- Betting (all members can still place singles)
- Grading and settlement (auto-pilot continues)
- Balance management (adjust, settle up)
- Member detail views
- Dashboard (reverts to free layout — summary cards only, blurred sport breakdown)

**Edge case**: Bookie has 10 members, downgrades, archives 8 → now at 2/3 → can invite again without upgrading.

---

## 2. Standardized Profile Editing — Players & Bookies

**Context**: Players currently have zero ability to edit their profile. Bookies can edit name/email but the profile status display is broken (shows `subscriptionStatus` instead of `tier`). We need a unified profile editing experience for both user types.

### Player Profile Editing

**Entry point**: CTA on AccountView profile section — pencil icon or "Edit Profile" tappable row next to name/email display.

**PlayerProfileEditView** (new view, mirrors bookie's EditProfileSheet pattern):
- **Name**: Editable text field. Player changes their own display name.
  - Syncs to Supabase `players.name` via a new edge function or direct update
  - **Bookie override**: Bookie can set a `display_name` on the player record (new column). This is only visible on the bookie side — used in Members list, member detail, picks, dashboard, etc. The player never sees it.
  - If `display_name` is set, bookie views show `display_name`. If null, bookie views fall back to `players.name` (player's self-chosen name).
  - Player always sees and edits `players.name` on their own side.
  - Bookie edits `display_name` from member detail (existing name edit flow). Player edits `name` from their profile page. No conflict — two separate fields.
- **Email**: Editable, but changing email requires Supabase email confirmation flow.
  - Use `supabase.auth.updateUser(email:)` which sends a confirmation to the new email
  - Show inline message: "A confirmation email has been sent to [new email]. Your email will update once confirmed."
  - Player's `players.email` updates after confirmation (via auth hook or next sync)
- **Read-only fields**: Organizer name, Member Since — displayed but not editable

**Player profile sync**:
- Currently NO upload mechanism for player changes to Supabase
- Need: direct Supabase update call from player side (RLS policy allowing players to update their own `name` on the `players` table, scoped to `auth.uid() = auth_user_id`)
- OR: new edge function `update_player_profile` that validates and applies changes

### Bookie Profile — Status Display Fix

**Bug**: `ProfileSettingsView` line 392 displays `bookie.subscriptionStatus.rawValue.capitalized` which shows "Free" even for Pro tier users who got Pro via direct DB update (not through Stripe).

**Fix**: The status row should check **both** `tier` and `subscriptionStatus`. User is Pro if **either** condition is true:
- `tier == .pro` (set via DB, debug toggle, or webhook)
- `subscriptionStatus` is `.active` or `.pro` (set via Stripe subscription)

Display "Pro" (teal) if either is true, "Free" (gray) only if both are free/inactive. This ensures users who got Pro through any path — Stripe, manual grant, promo — see the correct status.

This same logic should be used app-wide wherever `isPro` is checked (currently `BookieTier.isPro` only checks `tier`).

### Files to modify
| File | Change |
|------|--------|
| `Booki/Views/AccountView.swift` | Add Edit Profile CTA in profile section |
| `Booki/Views/PlayerProfileEditView.swift` | NEW: player profile edit view |
| `Booki/Views/SettingsView.swift` | Fix status row to use `tier` instead of `subscriptionStatus` |
| `Booki/Services/SyncService.swift` | Add player name upload capability |
| Supabase RLS or edge function | Allow players to update own name/email |

---

## 3. Picks Tab Filter Bar Redesign

**Context**: The bookie Picks tab currently shows player name chips for filtering. Replace with a more useful filter bar that supports member filtering via dropdown plus bet type filters.

**Current state**: Open/Past segmented picker at top, then player name chips (e.g., "Tyler") below.

**New filter bar** (horizontal row below Open/Past picker):

```
[👤 ▾]  [Singles]  [Multi-Pick]  [Futures]
```

1. **Member icon button** (first position, `person.fill` + chevron.down):
   - Tapping opens a dropdown/menu listing all members tied to the bookie
   - "All Members" option at top (default, no filter)
   - Selecting a member filters the list to only their picks
   - When a member is selected, the icon button shows their name instead of the generic icon (e.g., `[Tyler ▾]`)
   - Use a `.menu` picker or popover — not a full sheet

2. **Singles** chip — filters to single bets only (non-parlay, non-futures)
3. **Multi-Pick** chip — filters to parlays/multi-pick tickets only
4. **Futures** chip — filters to outright/futures bets only

**Behavior**:
- Filters are additive with the member dropdown — e.g., select "Tyler" + "Multi-Pick" = Tyler's multi-picks only
- Bet type chips are mutually exclusive (tap one to activate, tap again to deselect = show all types)
- Active chip gets `Theme.accent` background, inactive gets `Theme.elevatedBackground`
- All filters apply on top of the existing Open/Past segmented picker
- Filter state resets when switching between Open/Past

**Files to modify**:
| File | Change |
|------|--------|
| `Booki/Views/BookiePicksListView.swift` (or equivalent) | Replace player chips with new filter bar, add filtering logic |

---

## 4. Default User Experience — Solo Bet Tracker + "Be an Organizer" Upsell

**Context**: Users who download Booki without an invite currently land on the bookie (organizer) view by default. This is the wrong experience for most new users. Instead, uninvited users should get the **player view** as a standalone bet tracker with no stakes — purely tracking picks. An upsell path in Settings converts them to an organizer when they're ready.

### Routing Change

**Current**: `AuthGateView` routes `userRole == nil` → `ContentView` (bookie dashboard)
**New**: `userRole == nil` → `PlayerMainView` (player experience)

When a new user signs up without an invite:
- They land in the **player view** (Games, Search, Track, Account tabs)
- No bookie record is created until they opt in
- No player record with a bookie association exists — they're a standalone user
- `AuthManager` should recognize this state: authenticated but no bookie, no player-bookie link

### Standalone Bet Tracking

Solo users (no organizer) get a full betting experience:
- Browse all events/games/futures
- Add picks (singles, multi-picks, futures) to their slip
- **Enter stakes** — bet slip works normally with wager/to-win fields
- Track picks with outcomes (win/loss/push via auto-grading)
- View their record, win rate, ROI, performance on the Account tab
- **Default credit limit: $10,000** — gives them room to play
- **Open bet limit: 25** — prevents runaway activity without an organizer managing them
- **No parlay or tier restrictions** — full access to all bet types

What's different from a linked player:
- **Self-managed** — no organizer oversight, no settlement, no balance clearing
- **No "Organizer" row** in profile (or shows "None")
- **No settle up / adjust balance** actions (no one to settle with)
- **25 open bet cap** — enforced client-side and server-side. When at limit, bet slip shows "You've reached the open pick limit (25). Wait for picks to settle or grade before placing more."
- Credit bar on Account shows utilization against the $10,000 default

### "Be an Organizer" in Settings

**Location**: New row in `playerMenuSection` on AccountView, positioned above "About":
```
[crown.fill]  Be an Organizer  [chevron.right]
```
- Icon: `crown.fill` in `Theme.gold`
- Only shown for standalone users (no bookie record, `player.bookie == nil`)
- Hidden for players who are already linked to a bookie

**Tapping opens `BecomeOrganizerView`** — a full-screen upsell landing page:

#### Header
- "Ready to run your group?"
- Subtitle: "Turn your bet tracking into a full management platform."

#### Benefits Section (icon + title + subtitle rows)
| Icon | Title | Subtitle |
|------|-------|----------|
| `person.3.fill` | Invite Members | Add up to 3 members for free. They track picks under your book. |
| `chart.bar.fill` | Live Dashboard | See everyone's record, exposure, and performance at a glance. |
| `dollarsign.circle.fill` | Balance Management | Track who owes what. Settle up with one tap. |
| `gearshape.2.fill` | Full Control | Set credit limits, manage pick rules, adjust lines. |
| `bolt.fill` | Auto-Pilot | Picks auto-accepted, auto-graded, auto-settled. Zero manual work. |

#### Free Tier Callout
Highlighted card or banner:
- "Start free — no credit card required"
- "Free plan includes: 3 members, singles tracking, auto-grading, dashboard"
- "Upgrade to Pro anytime for unlimited members, multi-picks, and more"

#### CTA Button
- Primary teal button: **"Get Started"**
- Tapping this should:
  1. Create a bookie record for the user
  2. Switch `userRole` to `.bookie`
  3. Route to `ContentView` (bookie dashboard)
  4. Optionally show onboarding flow

### Auth Flow Consideration

**Sign Up**: New users sign up normally. After sign up:
- No bookie record created (currently it auto-creates one)
- User lands in player view as standalone tracker
- This means the sign-up flow needs to **stop auto-creating a bookie record**

**Invite deep link**: If a standalone user taps an invite link, they become a linked player under that bookie (existing flow).

**"Get Started" (become organizer)**: Creates bookie record + routes to bookie view. This is the only path to becoming an organizer from the standalone state.

### Files to Modify

| File | Change |
|------|--------|
| `Booki/Views/AuthGateView.swift` | Route `userRole == nil` → PlayerMainView instead of ContentView |
| `Booki/Managers/AuthManager.swift` | Stop auto-creating bookie record on sign-up; add `isStandaloneUser` computed property |
| `Booki/Views/AccountView.swift` | Add "Be an Organizer" row in menu section; hide credit/balance for standalone |
| `Booki/Views/BecomeOrganizerView.swift` | NEW: upsell landing page |
| `Booki/Views/Components/BetSlipSheet.swift` | Enforce 25 open bet limit for standalone users |
| `Booki/Views/PlayerMainView.swift` | Handle standalone state (no bookie data to sync) |
| `Booki/Views/SettingsView.swift` | Add "Step Down as Organizer" row with validation |
| `supabase/functions/submit_bets/index.ts` | Enforce 25 open bet limit for standalone users |
| `supabase/functions/submit_parlay/index.ts` | Same — 25 open bet limit enforcement |
| `supabase/functions/step_down_organizer/index.ts` | NEW: validate 0 members + 0 invites, delete bookie record |

### Remove Organizer Role

Organizers can revert to standalone user **if and only if**:
- **Zero active members** (no players with `bookie_id` pointing to them)
- **Zero open invites** (no unclaimed invite records)

**Location**: Row in bookie Settings (About or bottom of menu), styled as a destructive action:
```
[person.crop.circle.badge.minus]  Step Down as Organizer  (red text)
```

**Confirmation**: Alert — "Are you sure? Your organizer dashboard and settings will be removed. Your personal pick history will be preserved."

**On confirm**:
1. Server-side validation: verify 0 members + 0 open invites (edge function or RPC)
2. Delete the bookie record (or soft-delete / mark inactive)
3. Switch `userRole` back to `nil` → routes to PlayerMainView
4. User returns to standalone tracker with their pick history intact

**If conditions not met**: Show alert — "You still have active members or open invites. Archive all members and delete invites before stepping down."

### Edge Cases
- **Standalone user gets invited**: They accept invite → become linked player under bookie. "Be an Organizer" row disappears. Existing solo picks remain in their history.
- **Organizer reverts to standalone**: Bookie record removed, user returns to solo tracker. Pick history preserved. Can become organizer again later.
- **Standalone user hits 25 open bet cap**: Bet slip disabled with message. Picks settle via auto-grading to free up slots.
- **Sync for standalone users**: Only needs events/games. No bookie-specific data to sync.
- **Default credit**: $10,000 set on a virtual self-player record (or hardcoded client-side for standalone users — no real bookie to set it).

---

## 5. Block Pro Upgrade — "Coming Soon"

**Context**: Pro tier isn't ready for launch. Block the upgrade flow but keep the existing `ProUpgradeSheet` as a teaser. Users can still become free-tier organizers — just can't subscribe to Pro yet.

### Changes to ProUpgradeSheet

Keep the current layout (BookiPro logo, feature list in card) but replace the purchase flow with a "Coming Soon" state:

- **Remove** the price line (`"$49.99 / month"`) — replace with `"Coming Soon"` in `Theme.textSecondary`
- **Remove** the `NavigationLink` to `ProCheckoutView`
- **Replace CTA button** with a disabled/muted button: **"Coming Soon"** — `Theme.textMuted` text on `Theme.elevatedBackground`, no tap action
- **Optional**: Add a subtle note below the button — "We'll notify you when Booki Pro is available." in `Theme.textMuted`
- Keep the feature list exactly as-is — it still sells the vision
- Keep the context message (e.g., "You've reached the 3-member limit") — still useful to explain why they're seeing this

### All Upsell Entry Points

Every place that currently presents `ProUpgradeSheet` should continue to work — the sheet just shows "Coming Soon" instead of a checkout path. No changes needed at call sites.

Entry points to verify still work:
- Dashboard blurred sport breakdown tap
- Members tab capacity banner
- Invite sheet member limit
- Multi-pick restriction (player side)
- Any other `.sheet` presenting `ProUpgradeSheet`

### What to Leave Alone
- `ProCheckoutView.swift` — keep the file, just unreachable for now
- `SubscriptionManagementView.swift` — keep, unreachable since no one will be Pro
- `create_checkout_session` edge function — keep deployed, just not called
- `stripe_webhook` edge function — keep deployed
- Tier system in models/DB — fully intact, just no path to Pro from the UI

### Files to Modify
| File | Change |
|------|--------|
| `Booki/Views/ProUpgradeSheet.swift` | Replace price + CTA with "Coming Soon" state |

---

## 6. (next item goes here)

