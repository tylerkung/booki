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

## 4. (next item goes here)

