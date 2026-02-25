# PRD: Freemium Tier System

## Overview

Gate Booki features into Free and Pro tiers to create a sustainable revenue model. Free users get the complete core betting loop with natural limits. Pro users unlock scale, analytics, control, and power features. Upsell placements are strategic and respectful — never blocking core functionality. Blurred overlays and skeleton blockers are used sparingly where they feel intentional and create genuine curiosity (e.g., a blurred chart teasing real data), but never so much that the screen feels locked down.

**Pricing**: Pro at $49.99/month via StoreKit 2 in-app subscription.

---

## Tier Definitions

### Free Tier

The complete betting experience for a small group. Nothing feels broken — it just has boundaries.

| Category | Limit |
|----------|-------|
| Active members | 3 |
| Multi-picks (parlays) | Disabled for players |
| Dashboard | Summary cards only (no sport breakdown, no activity feed, no futures tracking) |
| Member filters | "All" only (no smart filters or attention tags) |
| Transaction history | Last 30 entries |
| Settings | Auto-pilot only (no manual modes, no acceptance rules) |
| Overrides | None (no reverse settlement, no override grade) |
| Export | None |
| Futures in multi-picks | N/A (multi-picks disabled) |

### Pro Tier — $49.99/month

Everything in Free, plus scale and power.

| Category | Limit |
|----------|-------|
| Active members | 50 |
| Multi-picks | Enabled |
| Dashboard | Full: performance by sport, futures tracking, recent activity |
| Member filters | All smart filters + attention tags + search |
| Transaction history | Unlimited |
| Settings | Manual approval, manual grading, acceptance rules, futures in multi-picks toggle |
| Overrides | Reverse settlement, override grade |
| Export | CSV export (picks + ledger) |

---

## Gating Implementation

### 1. Member Limit (3 Free / 50 Pro)

**Where it's enforced**: Invite creation flow.

- When a free bookie tries to create a 4th invite (or has 3 active members), block the invite creation
- Show an inline upgrade prompt in the `InviteMemberSheet`:
  - "You've reached the 3-member limit on the Free plan."
  - "Upgrade to Pro to invite up to 50 members."
  - [Upgrade to Pro] CTA button
- The "Invite Member" button on the Members tab should still be visible and tappable — the gate happens inside the sheet, not before it
- Archived/removed members do NOT count toward the limit — only active members with a `bookie_id` link
- Edge function `create_invite` should also enforce the limit server-side as a safety check

**Upsell placement**: On the Members tab, if at capacity, show a subtle banner below the last member card:
- Small card with `Theme.elevatedBackground`: "3 of 3 members · Upgrade for more"
- Tappable → opens Pro upgrade sheet
- NOT a skeleton/blur — just an informational card

---

### 2. Multi-Pick Restriction (Free: Disabled)

**Where it's enforced**: Player-side `BetSlipSheet` mode selector. This is a player-facing gate — it creates friction that incentivizes the bookie to upgrade.

- Free tier: The "Multi-Pick" tab in the bet slip mode selector is visible but disabled (grayed out)
- Tapping it shows a brief inline message below the selector: "Multi-Picks aren't available yet. Ask your organizer to upgrade."
- This is intentionally player-facing friction — players will ask their bookie "why can't I do multi-picks?", which drives bookie upgrades
- Singles mode works identically on both tiers
- Edge function `submit_parlay` should reject submissions from free-tier bookies as a server-side guard

**Key detail**: The restriction is based on the bookie's tier, not the player's account. The player's `BetSlipSheet` checks the bookie's tier (available via the player's linked bookie record). When a bookie upgrades to Pro, all their players instantly get multi-pick access — no app update or player action needed.

---

### 3. Dashboard Gating

**What free users see**:
- The 4 summary metric cards (Net Exposure, Pending Picks, Top Risk, Outstanding) — fully functional
- The members list section — fully functional (but without smart filters/tags, see #4)

**What's hidden on free**:

**Performance by Sport** — BLURRED TEASER (the one place a blur feels intentional):
- Render the `SportPerformanceCard` with sample/placeholder data, blurred with `.blur(radius: 8)` and `allowsHitTesting(false)`
- Overlay a frosted card centered on the blur:
  - Small chart.bar icon + "Sport Breakdown"
  - "See which sports are winning for you"
  - [Unlock with Pro] teal text button → opens Pro upgrade sheet
- The blur signals "this is real, you're just not there yet" — creates curiosity, not frustration
- This is the ONLY blurred section on the dashboard. One is intentional. Two or more feels punishing.

**Futures Tracking Card**: Completely hidden.

**Recent Activity Feed**: Completely hidden.

The dashboard should feel clean and complete on free — just simpler. The blurred sport breakdown is the single visual hook that more exists. Everything else is either fully functional or cleanly absent.

---

### 4. Smart Filters & Attention Tags (Pro Only)

**Members tab on free**:
- Member cards show: name, balance, record, credit utilization
- NO attention tags (On Heater, Whale, Degen, etc.)
- NO filter chips bar (All, Attention needed, Overdue, etc.)
- Search bar is hidden
- The list just shows all members sorted by name

**Members tab on pro**:
- Full filter chips bar appears
- Attention tags render on member cards
- Search bar visible
- Tag explainer modal works

**No upsell placement here** — the filters simply don't appear. This is a "discover it when you upgrade" feature, not a teased one.

---

### 5. Transaction History Limit (Free: 30 entries)

**Where it's enforced**: `PlayerActivityView` and the inline History section in `AccountView`.

- Free tier: Show the 30 most recent entries, then a footer row:
  - "Showing last 30 transactions"
  - "Upgrade to Pro for full history" — small teal link
- Pro tier: Show all entries, no footer

This is a soft gate — the most recent data is always visible. Users only hit it when scrolling deep into history.

---

### 6. Settings Gating

**Pick Management section on free**:
- "Require Manual Pick Approval" toggle: Hidden
- "Grade Picks Manually" toggle: Hidden
- "Allow Futures in Multi-Picks" toggle: Hidden
- "Acceptance Rules" navigation link: Hidden
- Instead show a single row: "Pick Management · Pro" with a lock icon and brief description
  - Tappable → opens Pro upgrade sheet with feature list

**Export Data on free**:
- Row visible but tapped shows: "Export your data with Pro" inline message
- OR: Hide entirely and show in Pro upgrade sheet feature list
- Recommend: Hide entirely. Cleaner settings, less noise.

**Balance Alerts on free**: Available (this is core functionality for managing a book)

**Change Password / About / Logout**: Available on all tiers.

---

### 7. Override Actions (Pro Only)

**BetDetailView (bookie) on free**:
- "Reverse Settlement" button: Hidden
- "Override Grade" button: Hidden
- The Actions card section is completely hidden if no actions are available
- No upsell here — these are power features that free users don't need to see

**On pro**: Actions card appears with all available actions based on bet state.

---

## Screens & Flows

### Screen 1: Pro Upgrade Sheet (`ProUpgradeSheet`)

A single, reusable sheet presented from every upsell entry point. This is the primary conversion screen.

**Presentation**: `.sheet` with `presentationDetents: [.large]`

```
┌─────────────────────────────────────┐
│                                     │
│            [Booki Logo]             │
│                                     │
│               PRO                   │  ← Theme.accent, large bold
│          $49.99 / month             │  ← Theme.textSecondary
│                                     │
│  ┌─────────────────────────────┐    │
│  │                             │    │
│  │  ✦  Up to 50 members       │    │  ← Feature list, left-aligned
│  │  ✦  Multi-Pick betting     │    │     Icon (checkmark.circle.fill)
│  │  ✦  Performance by sport   │    │     in Theme.accent for each
│  │  ✦  Futures tracking       │    │
│  │  ✦  Recent activity feed   │    │
│  │  ✦  Smart filters & tags   │    │
│  │  ✦  Manual approval        │    │
│  │  ✦  Acceptance rules       │    │
│  │  ✦  Override & reverse     │    │
│  │  ✦  CSV data export        │    │
│  │  ✦  Full history           │    │
│  │                             │    │
│  └─────────────────────────────┘    │  ← Theme.cardBackground rounded card
│                                     │
│  ┌─────────────────────────────┐    │
│  │    Subscribe — $49.99/mo    │    │  ← Full-width, Theme.accent bg
│  └─────────────────────────────┘    │
│                                     │
│     Already Pro? Restore Purchase   │  ← Theme.textMuted, tappable
│                                     │
│   Terms of Service · Privacy Policy │  ← Theme.textMuted links
│                                     │
└─────────────────────────────────────┘
```

**Behavior**:
- "Subscribe" button → navigates to `ProCheckoutView` (Screen 2)
- "Restore Purchase" → calls Stripe to check existing subscription status, updates tier if found
- Dismiss via swipe-down or X button (top-right)
- Optional `contextMessage` parameter: when opened from a specific gate, shows a brief line above the feature list (e.g., "Multi-Picks require Pro" or "You've reached 3 members")

**Entry Points** (all present this same sheet):

| # | Trigger | Context Message |
|---|---------|-----------------|
| 1 | Members tab capacity banner | "You've reached the 3-member limit" |
| 2 | Invite sheet at capacity | "You've reached the 3-member limit" |
| 3 | Bet slip Multi-Pick tab (player) | "Multi-Picks require Pro" |
| 4 | Dashboard sport breakdown blur | "Unlock analytics" |
| 5 | Settings "Pick Management · Pro" row | nil (no context needed) |
| 6 | Transaction history footer | "See your full history" |
| 7 | Settings → Subscription row | nil |

---

### Screen 2: Pro Checkout View (`ProCheckoutView`)

Pushed from the Pro Upgrade Sheet after tapping "Subscribe". Handles payment via Stripe.

```
┌─────────────────────────────────────┐
│  ← Back          Checkout           │
│                                     │
│  ┌─────────────────────────────┐    │
│  │  SUMMARY                    │    │
│  │                             │    │
│  │  Booki Pro          $49.99  │    │
│  │  Billed monthly             │    │
│  │                             │    │
│  │  ─────────────────────────  │    │
│  │                             │    │
│  │  Today's charge     $49.99  │    │  ← Theme.textPrimary, bold
│  │  Next renewal    Mar 25, 26 │    │  ← Theme.textSecondary
│  │                             │    │
│  └─────────────────────────────┘    │
│                                     │
│  ┌─────────────────────────────┐    │
│  │                             │    │
│  │   [Stripe Payment Element]  │    │  ← Stripe SDK placeholder
│  │                             │    │  ← Card input, Apple Pay, etc.
│  │   Placeholder for Stripe    │    │
│  │   integration. Shows        │    │
│  │   "Payment coming soon"     │    │
│  │   message in this sprint.   │    │
│  │                             │    │
│  └─────────────────────────────┘    │
│                                     │
│  ┌─────────────────────────────┐    │
│  │      Pay $49.99 / month     │    │  ← Theme.accent, full-width
│  └─────────────────────────────┘    │  ← Disabled until Stripe wired
│                                     │
│  Cancel anytime from Settings.      │  ← Theme.textMuted
│  Terms of Service · Privacy Policy  │
│                                     │
└─────────────────────────────────────┘
```

**Stripe Placeholder (this sprint)**:
- The payment area shows a `Theme.cardBackground` card with:
  - Lock icon + "Secure payment powered by Stripe"
  - "Payment integration coming soon"
  - The "Pay" button is present but disabled with `.opacity(0.5)`
- This lets us build and ship the entire tier gating system now, and wire Stripe in the next sprint without touching any UI
- When Stripe is connected, this area will embed `STPPaymentSheet` or Stripe's prebuilt UI

**Stripe Integration (future sprint)**:
- Create Stripe Customer on bookie signup (store `stripe_customer_id` on bookies table)
- Create Stripe Checkout Session or Payment Intent from a Supabase Edge Function
- Use Stripe's iOS SDK (`@stripe/stripe-ios`) for native payment sheet
- Webhook endpoint (Edge Function) listens for `customer.subscription.created`, `customer.subscription.deleted`, `invoice.payment_failed` → updates `bookies.tier`

---

### Screen 3: Pro Success View (`ProSuccessView`)

Shown after successful payment confirmation. Celebratory moment.

```
┌─────────────────────────────────────┐
│                                     │
│                                     │
│            ✓                        │  ← Large animated checkmark
│                                     │     (same style as bet success)
│       Welcome to Pro                │  ← Theme.textPrimary, headline
│                                     │
│   You now have access to all Pro    │  ← Theme.textSecondary
│   features. Invite up to 50         │
│   members and unlock the full       │
│   Booki experience.                 │
│                                     │
│  ┌─────────────────────────────┐    │
│  │        Get Started          │    │  ← Theme.accent, full-width
│  └─────────────────────────────┘    │     Dismisses sheet, returns to app
│                                     │
└─────────────────────────────────────┘
```

**Behavior**:
- "Get Started" dismisses all presented sheets and returns to the previous screen
- The tier is already updated locally (`@AppStorage`) and synced to Supabase
- All Pro features are immediately available — no restart needed

---

### Screen 4: Subscription Management View (`SubscriptionManagementView`)

Accessed from Settings → Subscription row when user is already Pro.

```
┌─────────────────────────────────────┐
│  ← Settings      Subscription       │
│                                     │
│  ┌─────────────────────────────┐    │
│  │                             │    │
│  │  CURRENT PLAN               │    │
│  │                             │    │
│  │  Booki Pro          Active  │    │  ← Green "Active" pill
│  │  $49.99/month               │    │
│  │                             │    │
│  │  ─────────────────────────  │    │
│  │                             │    │
│  │  Member Since   Feb 25, 26  │    │
│  │  Next Renewal   Mar 25, 26  │    │
│  │  Members        12 of 50    │    │  ← Usage indicator
│  │                             │    │
│  └─────────────────────────────┘    │
│                                     │
│  ┌─────────────────────────────┐    │
│  │  Manage on Stripe →         │    │  ← Opens Stripe customer portal
│  └─────────────────────────────┘    │     (update card, cancel, invoices)
│                                     │
│  Cancel anytime. Your existing      │
│  members and data are preserved.    │  ← Theme.textMuted
│                                     │
└─────────────────────────────────────┘
```

**Behavior**:
- "Manage on Stripe" opens Stripe Customer Portal URL (generated by Edge Function) in `SFSafariViewController`
- Portal handles: update payment method, view invoices, cancel subscription
- When user returns to app, re-check tier status from Supabase

---

### Flow: Settings → Subscription Row

```
Free user taps "Subscription · Free"
  → Presents ProUpgradeSheet (Screen 1)
    → Taps "Subscribe"
      → Pushes ProCheckoutView (Screen 2)
        → Completes payment (future: Stripe)
          → Shows ProSuccessView (Screen 3)
            → Taps "Get Started"
              → Dismisses all, back to Settings
              → Row now shows "Subscription · Pro"

Pro user taps "Subscription · Pro"
  → Pushes SubscriptionManagementView (Screen 4)
    → Can view details or manage on Stripe
```

### Flow: Any Upsell CTA

```
User hits a gate (member limit, multi-pick, blur, etc.)
  → Taps upgrade CTA
    → Presents ProUpgradeSheet (Screen 1) with contextMessage
      → Same flow as above from here
```

### Flow: Stripe Webhook (future sprint)

```
Stripe fires webhook (subscription.created / deleted / payment_failed)
  → Edge Function receives event
    → Updates bookies.tier in Supabase
    → On next app launch or sync, client reads new tier
    → UI updates immediately
```

---

## Subscription Settings Row

Add a persistent "Subscription" row near the top of bookie Settings (between Profile and Balance Alerts):

- **Free users**: Row shows "Subscription" label, "Free" value in `Theme.textSecondary`, small "PRO" badge pill in `Theme.accent` on the right → tapping presents `ProUpgradeSheet`
- **Pro users**: Row shows "Subscription" label, "Pro" value in `Theme.accent` → tapping pushes `SubscriptionManagementView`

---

## Payment Integration

### This Sprint (Placeholder)

- Build all 4 screens (Upgrade Sheet, Checkout, Success, Management)
- Checkout shows Stripe placeholder with "Payment coming soon" message
- "Pay" button is disabled
- For development/testing: add a hidden debug toggle in Settings (triple-tap the version number) that manually sets tier to Pro, allowing full testing of all gating logic without payment

### Next Sprint (Stripe Connection)

- Add `stripe_customer_id` column to `bookies` table
- Create Edge Function: `create_checkout_session` — returns Stripe Checkout Session URL or client secret
- Create Edge Function: `create_customer_portal` — returns Stripe Customer Portal URL for management
- Create Edge Function: `stripe_webhook` — handles subscription lifecycle events, updates `bookies.tier`
- Integrate `stripe-ios` SDK in `ProCheckoutView` for native payment UI
- Wire `ProSuccessView` to trigger on successful payment confirmation

### Server-Side Enforcement

Edge functions check the bookie's tier for:
- `create_invite`: Reject if at member limit for tier
- `submit_parlay`: Reject if bookie is free tier
- Other functions: No tier checks needed (settlements, grading, etc. work on all tiers)

### Downgrade Behavior

- If subscription lapses (Stripe webhook: `customer.subscription.deleted`), set tier to `free`
- Grace period: 3 days after failed payment (Stripe handles retry logic)
- If a Pro bookie with >3 members downgrades: existing members remain active, but no new invites until under the limit. No data is deleted. No features are retroactively removed from existing bets/history.

---

## Data Model Changes

### Bookie Model

The `tier` property already exists. Ensure it maps to:

```swift
enum BookieTier: String, Codable {
    case free
    case pro
}
```

Remove `ultra` if it exists — simplify to two tiers.

### Supabase

- `bookies.tier` column: `text`, default `'free'`
- Update on subscription change via client-side sync
- Edge functions read `bookies.tier` for enforcement

### UserDefaults / AppStorage

- `@AppStorage("bookieTier")` as local cache for instant UI gating (avoids async Supabase lookups on every view render)
- Synced from Supabase on login and subscription changes

---

## Upsell Strategy Summary

| Location | Type | Description |
|----------|------|-------------|
| Members tab (at capacity) | Inline card | "3 of 3 members · Upgrade for more" |
| Invite sheet (at capacity) | Blocking message | "You've reached the limit" + CTA |
| Bet slip multi-pick tab (player-side) | Inline message | "Ask your organizer to upgrade" |
| Dashboard (sport breakdown) | Blurred overlay | Sport performance blurred + frosted "Unlock" card |
| Settings (pick management) | Menu row | "Pick Management · Pro" with lock icon |
| Transaction history (30+ entries) | Footer row | "Showing last 30 · Upgrade for full history" |
| Settings (subscription) | Menu row | "Subscription · Free" with PRO badge |

**What we DON'T do**:
- No more than ONE blurred overlay per screen (the sport breakdown is it — anything more feels hostile)
- No popups or modals that interrupt flow unprompted
- No badges or banners on tabs
- No gating on core bet operations (place, grade, settle)
- No gating on balance management (adjust, settle up)
- No "X days left" trial pressure
- No full-screen paywalls blocking navigation

**Player-side upsell** (the one exception):
- Multi-pick disabled message tells the player to ask their organizer — this is intentional social pressure that drives bookie upgrades without charging players directly

---

## Implementation Notes

### View-Level Gating Pattern

Create a shared helper:

```swift
extension View {
    @ViewBuilder
    func proOnly(_ isPro: Bool) -> some View {
        if isPro { self }
    }
}
```

And a tier check property accessible from any view:

```swift
// Read from bookie query or environment
var isPro: Bool {
    bookie?.tier == "pro"
}
```

### Edge Function Changes

**`create_invite`**: Add tier check before insert:
```typescript
// Count active players for this bookie
const { count } = await client
  .from('players')
  .select('*', { count: 'exact', head: true })
  .eq('bookie_id', bookieId)
  .not('auth_user_id', 'is', null);

const limit = bookie.tier === 'pro' ? 50 : 3;
if (count >= limit) {
  return new Response(JSON.stringify({ error: 'member_limit_reached' }), { status: 403 });
}
```

**`submit_parlay`**: Add tier check:
```typescript
if (bookie.tier !== 'pro') {
  return new Response(JSON.stringify({ error: 'pro_required' }), { status: 403 });
}
```

### Migration

- Existing bookies default to `free` tier
- No data loss or feature removal for existing users until tier system is live
- Consider a launch promotion: existing users get 1 month Pro free

---

## Success Metrics

- **Conversion rate**: % of free bookies who upgrade to Pro within 30 days
- **Upgrade trigger**: Which entry point drives the most upgrades (track tap events per CTA)
- **Retention**: Pro subscriber churn rate (monthly)
- **Member limit hits**: How often free users hit the 3-member cap (validates the limit is right)
- **Multi-pick attempts**: How often free players try to use multi-pick (validates demand)

---

## Out of Scope (Future)

- Annual pricing ($399.99/year — 33% discount)
- Ultra/Enterprise tier (100+ members, API access, multiple bookies)
- Player-side subscriptions
- Referral/affiliate programs
- Team/org accounts
