# PRD: Push Notifications

## Overview

Booki has zero notification infrastructure. The app is entirely pull-based — users have to open it to see anything that happened. For a pick tracking app where games finalize, picks get graded, and balances change throughout the day, this is a critical gap.

This PRD covers APNs integration, a Supabase-backed delivery pipeline, notification preferences, and deep linking from notification taps.

---

## Goals

1. Members know when their picks are graded and their balance changes — without opening the app
2. Organizers know when members join, submit picks, and when risk thresholds are crossed
3. Notifications deep link to the relevant screen (pick detail, member detail, game, etc.)
4. Users control what they receive — granular opt-in/opt-out per category

## Non-Goals

- Rich media / image attachments (v2)
- In-app notification center / inbox (v2)
- Email notifications (already handled by Resend for invites and auth)
- SMS notifications
- Real-time in-app toasts (Realtime already handles live UI updates)

---

## Architecture

### Device Token Flow

```
iOS App                    Supabase                    APNs
  │                           │                          │
  ├─ Request permission ──►   │                          │
  ├─ Register for APNs ──────────────────────────────►   │
  │◄── Device token ─────────────────────────────────    │
  ├─ Store token ─────────► device_tokens table          │
  │                           │                          │
  │   (server event occurs)   │                          │
  │                    send_notification()                │
  │                           ├── APNs HTTP/2 ────────►  │
  │◄──────────────────────────────────────── push ──     │
  │                           │                          │
  ├─ Tap notification ──►  deep link to screen           │
```

### Components

1. **iOS: `NotificationService.swift`** — Permission request, token registration, token refresh, notification handling, deep link routing
2. **Supabase: `device_tokens` table** — Stores APNs tokens per user, per device
3. **Supabase: `notification_preferences` table** — Per-user opt-in/opt-out by category
4. **Supabase: `send_notification` edge function** — Accepts event type + payload, resolves recipients, checks preferences, sends via APNs HTTP/2
5. **Caller integration** — Existing edge functions (`auto_refresh_games`, `grade_bet`, `adjust_balance`, `claim_invite`, etc.) call `send_notification` after their core logic completes

---

## Database Schema

### `device_tokens`

| Column | Type | Notes |
|--------|------|-------|
| id | uuid | PK |
| user_id | uuid | FK → auth.users, indexed |
| token | text | APNs device token (hex string) |
| platform | text | `ios` (future-proof for Android/web push) |
| app_version | text | e.g. `1.0.0` |
| created_at | timestamptz | |
| updated_at | timestamptz | Refreshed on each app launch |

- Unique constraint on `(user_id, token)` — same device doesn't duplicate
- RLS: users can only insert/update/delete their own tokens
- On logout: delete all tokens for that user on that device
- On app launch: upsert token (handles token refresh)

### `notification_preferences`

| Column | Type | Notes |
|--------|------|-------|
| id | uuid | PK |
| user_id | uuid | FK → auth.users, unique |
| picks_graded | boolean | Default true |
| balance_changes | boolean | Default true |
| new_members | boolean | Default true (organizer only) |
| pick_submissions | boolean | Default false (organizer only) |
| game_results | boolean | Default true |
| risk_alerts | boolean | Default true (organizer only) |
| marketing | boolean | Default false |
| created_at | timestamptz | |

- Row created on first app launch (all defaults)
- RLS: users can only read/update their own row

---

## Notification Categories

### Member Notifications

| Event | Trigger | Title | Body Example | Deep Link |
|-------|---------|-------|-------------|-----------|
| Pick graded | `auto_refresh_games` or `grade_bet` grades a bet | Your pick was graded | Lakers ML — Won (+$50) | `booki://bet/{betId}` |
| Multi-pick graded | Parlay fully graded and settled | Multi-pick settled | 3-leg parlay — Won (+$240) | `booki://ticket/{ticketId}` |
| Balance adjusted | `adjust_balance` by organizer | Balance updated | Your balance was adjusted by -$25 | `booki://account` |
| Settle up logged | `adjust_balance` with type `paymentLogged` | Payment recorded | $150 payment logged by organizer | `booki://account` |
| Pick declined | `decline_bet` by organizer | Pick declined | Lakers ML -110 was declined | `booki://bet/{betId}` |

**Preference key:** `picks_graded` covers graded/settled, `balance_changes` covers adjustments and settle ups.

### Organizer Notifications

| Event | Trigger | Title | Body Example | Deep Link |
|-------|---------|-------|-------------|-----------|
| New member joined | `claim_invite` | New member | Jake joined your group | `booki://members/{playerId}` |
| Pick submitted | `submit_bet` or `submit_bets` | New pick | Jake — Lakers ML $50 | `booki://bet/{betId}` |
| Large pick submitted | `submit_bet` where stake > member credit * 0.5 | Large pick | Jake — $500 on Lakers ML (50% of credit) | `booki://bet/{betId}` |
| Member overdue | Cron check or on-demand | Member overdue | Jake owes $340 — last activity 7 days ago | `booki://members/{playerId}` |

**Preference keys:** `new_members`, `pick_submissions`, `risk_alerts`.

### Shared Notifications

| Event | Trigger | Title | Body Example | Deep Link |
|-------|---------|-------|-------------|-----------|
| Games finalized | `auto_refresh_games` batch | Games finished | 4 games finalized — 6 picks graded | `booki://picks` |

**Preference key:** `game_results`.

---

## Edge Function: `send_notification`

### Input

```typescript
{
  event: string,           // e.g. "pick_graded", "new_member", "balance_adjusted"
  recipient_user_ids: string[],  // who to notify
  title: string,
  body: string,
  data: {                  // payload for deep linking
    deep_link: string,     // e.g. "booki://bet/abc-123"
    [key: string]: any     // additional context
  }
}
```

### Logic

1. For each recipient, check `notification_preferences` — skip if opted out for this event category
2. Fetch all `device_tokens` for remaining recipients
3. Send APNs HTTP/2 request for each token
4. Handle token errors: if APNs returns `410 Gone` or `BadDeviceToken`, delete the token from `device_tokens`
5. Log delivery attempt (optional `notification_log` table for debugging, not required for v1)

### APNs Configuration

- **Auth:** Token-based authentication (`.p8` key from Apple Developer)
- **Key ID, Team ID, Bundle ID** stored as Supabase secrets
- **Environment:** `api.push.apple.com` (production), `api.sandbox.push.apple.com` (sandbox/TestFlight)
- **Topic:** `com.bookiapp.booki`
- **Push type:** `alert`
- **Priority:** `10` (immediate) for pick graded / balance changes, `5` (power-considerate) for game results

### JWT for APNs

The edge function generates a short-lived JWT signed with the `.p8` key:

```typescript
// Header: { alg: "ES256", kid: KEY_ID }
// Payload: { iss: TEAM_ID, iat: now }
// Sign with .p8 private key
```

Cache the JWT for ~50 minutes (APNs tokens are valid for 1 hour).

---

## iOS Implementation

### `NotificationService.swift`

```
@Observable class NotificationService {
    // Request permission (called after onboarding, not on first launch)
    // Register with APNs
    // Upsert token to Supabase device_tokens table
    // Handle incoming notification (foreground: suppress if already on that screen)
    // Handle notification tap → deep link routing
}
```

### Permission Request Timing

Don't ask on first launch. Ask after the user has submitted their first pick or completed onboarding — when they have context for why notifications matter. Show a pre-permission screen explaining what they'll receive.

### Deep Link Routing

`ContentView` already handles tab routing. Add a `pendingDeepLink` property:

1. Notification tap sets `pendingDeepLink`
2. On app foregrounding / view appear, consume the deep link
3. Route to the correct tab and push the detail view

URL scheme: `booki://` (already registered)

| Scheme | Screen |
|--------|--------|
| `booki://bet/{id}` | BetDetailView |
| `booki://ticket/{id}` | TicketDetailView |
| `booki://members/{id}` | PlayerAnalyticsDetailView |
| `booki://picks` | Picks tab |
| `booki://account` | Account tab |

### Token Lifecycle

- **App launch:** Request current token, upsert to `device_tokens`
- **Token refresh:** `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)` → upsert
- **Logout:** Delete all tokens for user on this device
- **Account deletion:** `delete_account` edge function already deletes user data — tokens go with it

### Badge Count

Set app icon badge to the count of unread graded picks (picks graded since last app open). Clear on app foreground.

---

## Integration Points

Existing edge functions gain a notification call at the end of their success path:

| Edge Function | Event | Recipient |
|---------------|-------|-----------|
| `auto_refresh_games` | `pick_graded`, `game_results` | Affected players, bookie |
| `grade_bet` | `pick_graded` | Player who placed the bet |
| `settle_bet` | `pick_graded` | Player |
| `settle_parlay` | `parlay_graded` | Player |
| `decline_bet` | `pick_declined` | Player |
| `adjust_balance` | `balance_adjusted` | Player |
| `submit_bet` / `submit_bets` | `pick_submitted` | Bookie |
| `claim_invite` | `new_member` | Bookie |

The notification call is **fire-and-forget** — it should not block or fail the primary operation. Wrap in try/catch, log errors, move on.

---

## Notification Preferences UI

### Member (Account → Notifications)

- **Pick results** — When your picks are graded (default: on)
- **Balance changes** — Adjustments and settle ups (default: on)
- **Game results** — When games in your sports finalize (default: on)

### Organizer (Settings → Notifications)

- **New members** — When someone joins your group (default: on)
- **Pick submissions** — When members submit picks (default: off — could be noisy)
- **Risk alerts** — Large picks and overdue balances (default: on)
- **Game results** — When games finalize and picks are graded (default: on)

Simple toggle list in a `.cardStyle()` card, matching existing Settings layout.

---

## Rollout Plan

### Phase 1: Core Infrastructure
- `device_tokens` and `notification_preferences` migrations
- `NotificationService.swift` — permission, token registration, deep linking
- `send_notification` edge function with APNs HTTP/2
- Integration with `auto_refresh_games` (the biggest source of events — covers pick grading and game results)

### Phase 2: Full Coverage
- Integration with remaining edge functions (`adjust_balance`, `claim_invite`, `submit_bet`, `decline_bet`)
- Notification preferences UI in Settings / Account
- Badge count management
- Pre-permission screen

### Phase 3: Smart Notifications (v2)
- Batch/digest notifications (don't send 8 "pick graded" notifications in a row — bundle them)
- "Games starting soon" for games with open picks
- Weekly summary digest (your record this week, balance change)
- In-app notification center

---

## Apple Requirements

- **Info.plist:** `UIBackgroundModes` → `remote-notification`
- **Entitlements:** `aps-environment` → `production`
- **App Store Connect:** Enable push notification capability
- **Apple Developer:** Create APNs key (`.p8`), note Key ID and Team ID
- **Supabase secrets:** `APNS_KEY_P8`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_BUNDLE_ID`, `APNS_ENVIRONMENT`

---

## Privacy

- Device tokens are stored in Supabase with RLS (user can only access their own)
- Tokens deleted on logout and account deletion
- No notification content stored server-side (fire-and-forget)
- Update `PrivacyInfo.xcprivacy` to declare push token collection if required
- Notification preferences are user-controlled and default conservative (pick submissions off for organizers)

---

## Success Metrics (post-analytics)

- Notification opt-in rate (target: >60% of active users)
- Notification tap-through rate (target: >15%)
- DAU lift after notifications enabled vs before
- Time-to-open after pick graded (should decrease significantly)
