# Booki Pro Tier Specification

> Reference document for the Free/Pro tier system. Covers pricing, feature gates, enforcement, and upgrade flows.

---

## Pricing

| Tier | Price | Billing |
|------|-------|---------|
| Free | $0 | Forever |
| Pro | $49.99/month | Monthly via in-app subscription |

Future consideration: annual pricing at $399.99/year (33% discount).

---

## Feature Comparison

| Feature | Free | Pro |
|---------|------|-----|
| **Active members** | 3 | 50 |
| **Singles pick tracking** | Yes | Yes |
| **Live odds & auto-grading** | Yes | Yes |
| **Auto-settlement & balances** | Yes | Yes |
| **Multi-pick (parlay) betting** | No | Yes |
| **Dashboard summary cards** | Yes | Yes |
| **Performance by sport** | Blurred teaser | Full analytics |
| **Futures tracking** | Hidden | Yes |
| **Recent activity feed** | Hidden | Yes |
| **Smart filters & attention tags** | Hidden | Yes |
| **Member search** | Hidden | Yes |
| **Transaction history** | Last 30 entries | Unlimited |
| **Pick management settings** | Auto-pilot only | Manual approval, grading rules, acceptance rules |
| **Override grade** | No | Yes |
| **Reverse settlement** | No | Yes |
| **CSV export** | No | Yes |
| **Balance alerts** | Yes | Yes |
| **Change password** | Yes | Yes |

---

## Gating Strategy

### Philosophy
- Free tier is a **complete, functional experience** for small groups
- Nothing feels broken — it just has boundaries
- Upsell placements are strategic and respectful
- Only ONE blurred overlay on the dashboard (sport breakdown) — anything more feels hostile
- No popups, no trial pressure, no full-screen paywalls

### Where Gates Are Enforced

| # | Gate | Location | Type |
|---|------|----------|------|
| 1 | Member limit (3/50) | Invite creation + `create_invite` edge function | Blocking + server-side |
| 2 | Multi-pick disabled | Player BetSlipSheet + `submit_parlay` edge function | UI disabled + server-side |
| 3 | Dashboard analytics | AnalyticsDashboardView | Blurred/hidden sections |
| 4 | Smart filters & tags | PlayersListView (Members tab) | Hidden |
| 5 | Transaction history | AccountView / PlayerActivityView | Capped at 30 entries |
| 6 | Pick management | SettingsView | Hidden behind Pro row |
| 7 | Export data | SettingsView | Hidden |
| 8 | Override actions | BetDetailView | Hidden |

### Player-Side Gate
Multi-pick is the only player-facing gate. When a free-tier bookie's player taps the Multi-Pick tab, they see: *"Multi-Picks aren't available yet. Ask your organizer to upgrade."* This creates social pressure that drives bookie upgrades.

---

## Upsell Entry Points

| # | Trigger | Context Message | Opens |
|---|---------|-----------------|-------|
| 1 | Members tab capacity banner | "You've reached the 3-member limit" | ProUpgradeSheet |
| 2 | Invite sheet at capacity | "You've reached the 3-member limit" | ProUpgradeSheet |
| 3 | Dashboard sport breakdown blur | "Unlock analytics" | ProUpgradeSheet |
| 4 | Settings "Pick Management · Pro" row | (none) | ProUpgradeSheet |
| 5 | Transaction history footer | "See your full history" | ProUpgradeSheet |
| 6 | Settings → Subscription row | (none) | ProUpgradeSheet |

---

## Technical Implementation

### Source of Truth
- **Bookie.tier** (SwiftData model, synced from Supabase `bookies.tier` column)
- All views read from `bookies.first?.tier` via `@Query`
- `TierService` exists for non-View contexts but is secondary

### Database
- `bookies.tier` column: `text`, default `'free'`
- Values: `'free'`, `'pro'`
- Edge functions read `bookies.tier` for server-side enforcement

### Debug Toggle
- Triple-tap version number in Settings → About
- Writes directly to `Bookie.tier` in SwiftData
- For development/testing only — remove before App Store submission

### Server-Side Enforcement
- **`create_invite`**: Counts active players, rejects if at tier limit
- **`submit_parlay`**: Rejects if bookie tier is `free`
- Other functions (settle, grade, etc.) have no tier checks — core operations work on all tiers

---

## Payment Integration (Future)

### Planned: Stripe
- Create `stripe_customer_id` column on `bookies` table
- Edge function: `create_checkout_session` — returns Stripe session
- Edge function: `create_customer_portal` — returns portal URL for management
- Edge function: `stripe_webhook` — handles subscription lifecycle, updates `bookies.tier`
- iOS: Stripe SDK for native payment sheet in `ProCheckoutView`

### Downgrade Behavior
- Subscription lapses → tier set to `free` via webhook
- Grace period: 3 days after failed payment (Stripe retry logic)
- Existing members remain active — no new invites until under limit
- No data deleted, no features retroactively removed from existing picks/history

---

## Screens

### ProUpgradeSheet
Reusable sheet presented from every upsell entry point. Shows:
- Booki logo + "PRO" header
- $49.99/month price
- Feature checklist (11 items)
- "Subscribe" CTA → ProCheckoutView
- "Restore Purchase" link
- Terms / Privacy links

### ProCheckoutView
- Summary card (Booki Pro, $49.99, billing cycle)
- Stripe payment placeholder (currently shows "Payment coming soon")
- Pay button (disabled until Stripe is wired)

### ProSuccessView
- Animated checkmark + "Welcome to Pro"
- "Get Started" dismisses all sheets
- Tier updated immediately — no restart needed

### SubscriptionManagementView
- Current plan card (Active pill, price, renewal date, member usage)
- "Manage on Stripe" link → Stripe Customer Portal
- Cancel info

---

## What We Don't Do

- No more than ONE blurred overlay per screen
- No popups or modals that interrupt flow unprompted
- No badges or banners on tabs
- No gating on core pick operations (place, grade, settle)
- No gating on balance management (adjust, settle up)
- No "X days left" trial pressure
- No full-screen paywalls blocking navigation

---

## Out of Scope (Future)

- Annual pricing ($399.99/year)
- Ultra/Enterprise tier (100+ members, API access)
- Player-side subscriptions
- Referral/affiliate programs
- Team/org accounts

---

*Last updated: February 25, 2026*
