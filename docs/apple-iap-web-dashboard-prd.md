# Apple IAP + Web Dashboard PRD

**Version:** 1.0
**Date:** February 26, 2026
**Status:** Implementation Complete

---

## Overview

This PRD covers two interconnected features:
1. **Apple IAP In-App Subscription** — Replace "Coming Soon" Pro upgrade with live Apple IAP ($59.99/mo)
2. **Web Dashboard** — Full-featured organizer dashboard at bookisports.com/dashboard with Stripe billing ($49.99/mo)

Both paths update the same `bookies.tier` column. A `subscription_source` column (`'apple'` | `'stripe'` | NULL) prevents cross-platform webhook conflicts.

---

## Part 1: Apple IAP In-App ($59.99/mo)

### User Stories

**US-IAP-01: Subscribe to Pro via IAP**
- As a free-tier organizer, I can subscribe to Booki Pro from the in-app upgrade sheet
- Acceptance: Tapping "Subscribe" triggers Apple IAP purchase flow, on success bookie tier updates to `pro`

**US-IAP-02: View Dynamic Price**
- As an organizer, I see the Apple-localized price (not hardcoded) on the upgrade sheet
- Acceptance: `product.displayPrice` shown in CTA button and subtitle

**US-IAP-03: Restore Purchases**
- As an organizer who reinstalled the app, I can restore my existing subscription
- Acceptance: "Restore Purchases" button syncs with App Store and re-enables Pro

**US-IAP-04: Manage Apple Subscription**
- As a Pro organizer, I can manage my subscription from Settings
- Acceptance: "Manage Subscription" opens `https://apps.apple.com/account/subscriptions`

**US-IAP-05: Auto-Renewal Compliance**
- As an organizer, I see required Apple auto-renewal disclosure language before purchasing
- Acceptance: Disclosure text, Terms of Service link, and Privacy Policy link present

**US-IAP-06: Server-Side Validation**
- As the system, verified transactions are sent to the server to update the database
- Acceptance: `apple_iap_webhook` edge function validates JWS claims and updates `bookies.tier`

**US-IAP-07: Apple Server Notifications**
- As the system, Apple renewal/expiration/refund notifications are processed
- Acceptance: `DID_RENEW` confirms pro, `EXPIRED`/`REFUND`/`REVOKE` downgrade to free

### Technical Spec

#### Database (Migration 026)
```sql
ALTER TABLE bookies ADD COLUMN subscription_source TEXT;
ALTER TABLE bookies ADD COLUMN apple_original_transaction_id TEXT UNIQUE;
```

#### StoreKitService (`Booki/Services/StoreKitService.swift`)
- `@Observable @MainActor` singleton
- Product ID: `com.bookisports.booki.pro.monthly`
- StoreKit 2 APIs: `Product.products()`, `product.purchase()`, `Transaction.updates`, `Transaction.currentEntitlements`
- Sends verified JWS to `apple_iap_webhook` edge function

#### Edge Function (`supabase/functions/apple_iap_webhook/index.ts`)
- **Client path** (POST with JWT): Validates `bundleId`, `productId`, `expiresDate` → sets `tier='pro'`, `subscription_source='apple'`
- **Server Notification path** (POST from Apple): Handles `DID_RENEW`, `EXPIRED`, `DID_FAIL_TO_RENEW`, `REFUND`, `REVOKE`
- Only processes downgrades when `subscription_source = 'apple'`

#### Stripe Webhook Guard
- `checkout.session.completed` now sets `subscription_source = 'stripe'`
- `customer.subscription.deleted` and `invoice.payment_failed` skip if `subscription_source = 'apple'`

#### ProUpgradeSheet Changes
- "Coming Soon" → Live "Subscribe for {displayPrice}/mo" button
- Added: Restore Purchases button, auto-renewal disclosure, ToS/Privacy links
- On success → `ProSuccessView`

#### SubscriptionManagementView Changes
- Removed Stripe portal integration
- "Manage Subscription" links to Apple subscription settings

#### Deleted
- `ProCheckoutView.swift` — Stripe WKWebView checkout (no longer needed)

---

## Part 2: Web Dashboard

### User Stories

**US-WEB-01: Log In**
- As an organizer, I can log into my dashboard at bookisports.com/dashboard
- Acceptance: Email/password login, session persists, redirect to app.html

**US-WEB-02: Sign Up**
- As a new user, I can create an organizer account from the web
- Acceptance: Sign up with name/email/password/18+ checkbox, email verification if enabled

**US-WEB-03: View Dashboard**
- As an organizer, I see summary stats (PnL, members, open picks, volume) with time filtering
- Acceptance: Stats update on 1D/1W/1M/All toggle, recent activity table shows last 10 entries

**US-WEB-04: Manage Members**
- As an organizer, I can view, search, settle up, and adjust balances for members
- Acceptance: Member table with search, balance display, settle up and adjust modals

**US-WEB-05: Create Invites**
- As an organizer, I can invite new members via the web
- Acceptance: Invite modal with email + credit limit, calls `create_invite` edge function

**US-WEB-06: View Picks**
- As an organizer, I can browse all picks with filters
- Acceptance: Open/Past toggle, member dropdown, type chips (Singles/Multi-Pick/Futures)

**US-WEB-07: Upgrade via Stripe**
- As a free-tier organizer on web, I can upgrade to Pro via Stripe ($49.99/mo)
- Acceptance: "Upgrade to Pro" redirects to Stripe checkout, success redirects back

**US-WEB-08: Manage Stripe Billing**
- As a Pro organizer on web, I can manage billing via Stripe portal
- Acceptance: "Manage Billing" opens Stripe customer portal

**US-WEB-09: Responsive Design**
- As an organizer on mobile, the dashboard works with collapsible sidebar
- Acceptance: Hamburger menu on <768px, responsive stat grids

### Technical Spec

#### Architecture
- **Framework:** Alpine.js v3 (CDN) — reactive data binding, no build step
- **Auth:** Supabase JS v2 (CDN) — JWT-based, same project
- **Routing:** Hash-based (`#/dashboard`, `#/members`, `#/picks`, `#/subscription`)
- **Styling:** Custom CSS with shared theme variables from landing site
- **Hosting:** Netlify (same as landing page)

#### Files
| File | Purpose |
|------|---------|
| `landing/dashboard/index.html` | Auth page (login/signup/forgot password) |
| `landing/dashboard/app.html` | Main SPA with Alpine.js |
| `landing/dashboard/dashboard.css` | Styles (dark theme, responsive) |
| `landing/dashboard/dashboard.js` | Core logic, Alpine data store, Supabase queries |

#### Data Access
- Uses existing RLS policies (Supabase JS sends JWT automatically)
- Queries: `bookies`, `players`, `bets`, `ledger_entries`, `invites`
- Edge function calls: `create_invite`, `adjust_balance`, `create_checkout_session`, `create_customer_portal`

#### Landing Nav
- "Log In" link added to desktop and mobile nav, pointing to `/dashboard/`

---

## Cross-Platform Subscription Source

| Action | subscription_source | Result |
|--------|-------------------|--------|
| Apple IAP purchase | `'apple'` | Tier → pro |
| Stripe checkout | `'stripe'` | Tier → pro |
| Apple renewal | `'apple'` (unchanged) | Tier stays pro |
| Apple expiry/refund | `'apple'` → NULL | Tier → free |
| Stripe deletion | `'stripe'` → NULL | Tier → free |
| Stripe event + source=apple | Skipped | No change |
| Apple event + source=stripe | Skipped | No change |

---

## Apple Compliance Checklist

- [x] Restore Purchases button
- [x] Terms of Service link
- [x] Privacy Policy link
- [x] Auto-renewal disclosure language
- [x] Price from StoreKit (localized, not hardcoded)
- [x] No references to web pricing or Stripe in iOS app

---

## Verification Plan

1. **StoreKit**: Test with Xcode StoreKit configuration file — purchase, restore, cancellation, expiration
2. **Edge function**: Test `apple_iap_webhook` with sample JWS payloads (client + server notification paths)
3. **Stripe webhook**: Verify `subscription_source` guard prevents cross-platform downgrades
4. **Web auth**: Login, signup, session persistence, logout
5. **Web dashboard**: Verify RLS returns correct bookie-scoped data
6. **Web Stripe**: Test checkout redirect flow and portal access
7. **CORS**: Verify edge functions accept requests from bookisports.com

---

## Files Changed

### New Files
- `supabase/migrations/026_apple_iap_columns.sql`
- `Booki/Services/StoreKitService.swift`
- `supabase/functions/apple_iap_webhook/index.ts`
- `landing/dashboard/index.html`
- `landing/dashboard/app.html`
- `landing/dashboard/dashboard.css`
- `landing/dashboard/dashboard.js`
- `docs/apple-iap-web-dashboard-prd.md`

### Modified Files
- `supabase/functions/stripe_webhook/index.ts` — subscription_source guard
- `Booki/Views/ProUpgradeSheet.swift` — IAP purchase UI
- `Booki/Views/SubscriptionManagementView.swift` — Apple subscription management
- `Booki/BookiApp.swift` — StoreKit lifecycle
- `Booki/Services/BookieService.swift` — new fields in BookieRecord
- `landing/index.html` — nav login link
- `landing/styles.css` — login button style
- `landing/netlify.toml` — dashboard headers

### Deleted Files
- `Booki/Views/ProCheckoutView.swift` — Stripe WKWebView checkout
