# Booki: Be The House

**A case study in designing, building, and shipping a full-stack sports betting platform as a solo product designer.**

---

## The Problem

Every friend group that bets on sports eventually hits the same wall. Someone's tracking bets in a shared Google Sheet. Venmo requests pile up. Nobody remembers what the line was when the bet was placed. Arguments happen.

The existing solutions — pay-per-head (PPH) platforms — were built for offshore bookmakers, not friend groups. They charge $5-10 per player per week, look like they were designed in 2008, and come with baggage that makes casual organizers uncomfortable.

I saw a gap: a modern, trust-first platform for private sports betting groups, priced as flat-fee SaaS instead of per-head extraction.

---

## My Role

Everything. Product strategy, UX research, interaction design, visual design, design system, frontend engineering (SwiftUI + web), backend architecture (Supabase Edge Functions, PostgreSQL), marketing site, SEO, content, and go-to-market.

**Timeline:** ~2 months, 789 commits, 43,000+ lines of code.

**Stack:** iOS (Swift 6 / SwiftUI / SwiftData), Web (Alpine.js SPA), Backend (Supabase / PostgreSQL / Deno Edge Functions), Payments (Stripe + Apple IAP), Email (Resend).

---

## Strategic Framing

### Two-Sided Product, One Interface

Booki serves two users with fundamentally different mental models:

- **Organizers** think in risk, exposure, and settlement cycles. Their job is managing a group.
- **Members** think in odds, picks, and balances. Their job is placing bets and knowing where they stand.

Rather than building two separate apps, I designed a single product with role-gated experiences — shared data model, divergent UIs. This kept the codebase manageable while letting each side feel purpose-built.

### Trust as Core Product Value

In betting, disputes are inevitable. The #1 feature isn't odds or grading — it's **proof**. Every design decision laddered up to a trust thesis:

- **Tamper-evident ledger** — financial entries are hash-chained, making retroactive edits cryptographically detectable. This isn't just backend architecture; it's a product differentiator I surface in marketing copy.
- **Server-authoritative operations** — all critical actions (submitting, grading, settling) execute on the server with idempotency protection. The client can't fabricate results.
- **Full audit trail** — every bet, grade, settlement, and balance adjustment is logged with timestamps and actor IDs. Both sides can verify history.

This wasn't over-engineering. It was the insight that in a trust-deficit domain, the product *is* the audit trail.

### Pricing as Positioning

PPH platforms charge per head per week — a model that punishes growth. A 20-person group pays $400-800/month. I priced Booki at a flat $49.99/month for up to 50 members, with a free tier for groups of 3.

This pricing isn't just cheaper — it repositions the product. PPH says "you're running a business." Booki says "you're running a friend group." The pricing communicates the audience before a single feature is evaluated.

---

## Design System

I built a comprehensive design system from scratch, documented in a dedicated spec and implemented in a centralized Theme file with reusable view modifiers.

### Visual Language

**Dark-first, sports-native.** The visual system draws from sports broadcast aesthetics — dark backgrounds, high-contrast data, accent colors that communicate win/loss state instantly:

| Token | Value | Purpose |
|-------|-------|---------|
| Accent | `#00F5D4` (electric cyan) | Actions, wins, focus states |
| Danger | `#FF6B6B` (coral red) | Losses, destructive actions |
| Warning | `#FFA94D` (warm orange) | Pending states, attention |
| Background | `#0A0A12` | Deep purple-tinted black base |
| Card | `#14141F` | Elevated surface with purple tint |

**Typography** is split between Space Grotesk (display/numbers — gives odds a sportsbook feel) and IBM Plex Sans (body text — readable at small sizes). Monospaced digits throughout for currency and odds alignment.

**Spacing** follows a 4pt base grid. **Radius** is generous (12-16pt) for a softer, more approachable feel than traditional betting UIs. **Motion** uses critically damped springs with `prefers-reduced-motion` support.

### Design Principle: "Less but better"

The system's governing philosophy: remove elements until the design breaks, then add back one thing. Every element earns its place. This kept the interface from accumulating the visual noise that plagues betting platforms.

---

## Interactive Prototype

Experience the core betting flow firsthand — browse games, tap odds to build a bet slip, enter stakes with the custom keypad, and place a pick.

<iframe src="prototype.html" width="430" height="900" style="border: none; border-radius: 54px; display: block; margin: 0 auto;" scrolling="no"></iframe>

---

## Key Design Decisions

### 1. Auto-Pilot as Default

Most betting platforms start with manual controls and let users automate later. I inverted this.

New organizers get a fully automated system: bets auto-accept, games auto-grade when final scores come in, settlements auto-calculate. Manual approval and manual grading are opt-in toggles buried in settings.

**Why:** The target user isn't a professional bookie — they're someone organizing bets for friends. They don't *want* to manually approve every bet. The first experience should feel effortless, with power controls available when needed.

This single decision shaped the entire backend architecture. Auto-grading required sport-aware logic (moneyline, spread, totals each grade differently). Auto-settlement required atomic database transactions. Live score polling required smart API call budgeting (sport-duration estimation to avoid burning quota on games that aren't close to ending).

### 2. Standalone-First Onboarding

Early versions required users to choose "Organizer" or "Member" at signup. Conversion data showed this fork paralyzed new users who just wanted to explore.

I redesigned onboarding to drop everyone into a standalone player experience with a synthetic $10K credit line and 25 open bet limit. No group needed. Just browse games, place picks, and see how it works.

The "Become an Organizer" upsell lives in the Account menu — one tap creates a bookie record, and the UI transforms. The upgrade path follows exploration, not precedes it.

### 3. Compliance-First Language

App Store review is the gatekeeper. I ran a full terminology audit and replaced every gambling term with compliant alternatives:

| Internal | User-Facing |
|----------|-------------|
| Bookie | Organizer |
| Player | Member |
| Bet | Pick |
| Parlay | Multi-Pick |
| Wager | Stake |
| Payout | Potential Return |

This wasn't just find-and-replace — it required rethinking how concepts are explained in empty states, error messages, onboarding copy, and the marketing site. The language shift also made the product feel less intimidating for casual users, which turned a compliance constraint into a UX win.

### 4. Skeleton Loading with Branded Transitions

The app is offline-first (SwiftData), but first launch requires a cloud sync. Instead of a spinner, I designed:

- **Dashboard:** Shimmer placeholder cards that match the exact layout of the real dashboard — no layout shift when data arrives.
- **Games view:** Shimmer on odds buttons specifically (the interactive elements), while static structure renders immediately.
- **Cold start:** Centered logo with accent glow — branded, calm, no spinner anxiety.

The skeletons are dismissed by observing data arrival, not arbitrary timers. If local storage has cache from a previous session, skeletons are skipped entirely.

### 5. Bet Slip as Persistent Workspace

The bet slip isn't a modal you open and close — it's a persistent workspace that accumulates selections as you browse. On iOS, it's a sheet that slides up. On web (desktop), it's a fixed right sidebar that the main content reflows around.

Key interaction details:

- **Bidirectional staking** — entering a stake calculates potential return; entering a desired return back-calculates the required stake. Both fields are live-editable with focus tracking to prevent feedback loops.
- **Mode switching** — toggling between Singles and Multi-Pick preserves all selections. If selections drop below 2, Multi auto-switches to Singles.
- **Custom numeric keypad** — a purpose-built 4x3 grid (not the system keyboard) that keeps the bet slip compact and prevents the keyboard from pushing content off screen.
- **26 confirmation messages** — on successful submission, a randomized message adds personality ("Locked in. Let's ride." / "The house always wins... right?"). Small detail, big personality.

### 6. Attention Tags for Organizer Intelligence

Organizer dashboards in competing products show raw numbers. I designed an **attention tag system** that translates data into actionable signals:

- **Picks Pending** — bets awaiting manual approval
- **Overdue** — balance outstanding past threshold
- **On Heater / Cold Streak** — recent win/loss patterns
- **Whale** — disproportionately large stakes
- **Parlay Demon** — heavy multi-pick activity

Tags are tappable with explainer modals so organizers understand *why* a member is flagged. The Members list is filterable by tag, turning a flat list into a prioritized action queue.

### 7. Non-Aggressive Monetization

Free tier gets full functionality for up to 3 members — including auto-grading, live odds, and settlement tracking. The only hard gates: parlays (Pro), advanced analytics (blurred overlay on free), and member capacity.

The upsell philosophy: show the value, don't block the workflow. The analytics blur is a single overlay — not a hostile paywall cascade. The social lever is more effective: when a member tries to place a parlay and can't, they see "Multi-Picks are locked — ask your organizer to upgrade." Peer pressure converts better than pop-ups.

---

## Information Architecture

### Organizer: 5-Tab Structure

| Tab | Purpose | Key Pattern |
|-----|---------|-------------|
| **Dashboard** | PnL trends, risk watchlist, exposure metrics | Time-selector (1D/1W/1M/All) filters headline number |
| **Picks** | All bets with status/type/member filters | Card-based detail view matching player's ticket view |
| **Members** | Roster with attention tags and capacity tracking | Inline search + 6 smart filter chips |
| **Events** | Sport categories as cards, league sub-tabs | Shared events architecture (no per-bookie duplication) |
| **Settings** | Profile, subscription, pick management, about | Menu page with navigable detail views |

### Member: 4-Tab Structure

| Tab | Purpose | Key Pattern |
|-----|---------|-------------|
| **Games** | Browse events with sport tabs, quick-pick odds | Horizontal sport scroller, compact game cards |
| **Search** | Full-text team search, grouped by sport/league | Dedicated tab (not inline search) for discoverability |
| **Track** | Bet history with ticket grouping | Open/graded toggle, final scores inline |
| **Account** | Balance, activity, profile, preferences | Card-based layout with performance stats |

The asymmetry is intentional. Organizers need more surface area (5 tabs) because their tasks are more varied. Members need speed (4 tabs) because their primary action is singular: find a game, place a pick.

---

## Platform Parity: iOS + Web

The web dashboard provides feature parity for organizers who prefer desktop. Key differences are intentional, not compromises:

- **Bet slip:** Fixed sidebar on desktop (340px), floating sheet on mobile — each native to its input paradigm.
- **Member detail:** Inline grid editing on web (click-to-edit credit/win limits), modal sheets on iOS.
- **Navigation:** Hash-based routing with responsive sidebar (collapses to hamburger on mobile).

Both clients share the same backend, Edge Functions, and real-time subscriptions. Data changes on one platform appear on the other within seconds.

---

## Marketing & Growth

### Landing Site

8-section homepage with scroll-reveal animations, dedicated features page with mixed layouts (hero feature, 3-card grids, wide splits with mock UI), and a comparison section that positions Booki against traditional PPH pricing.

### SEO & Content

- Structured data (JSON-LD), Open Graph tags, and sitemap on all pages.
- 3 bottom-funnel SEO landing pages targeting search intent ("PPH alternative," "bookie software," "ledger software").
- Blog with 8+ articles, staggered publish dates, FAQPage schema on comparison posts.

### Web-First Pivot

Originally positioned as an iOS app with a web companion. I pivoted to web-first messaging — replacing App Store CTAs with "Get Started Free" links to the web dashboard. This removed the friction of requiring a download before experiencing the product.

---

## Technical Complexity I Navigated as a Designer

This section isn't about showing off code — it's about demonstrating that I understand the systems I'm designing for, and that my design decisions account for real engineering constraints.

- **26 Edge Functions** handling everything from bet submission to Stripe webhooks to Apple IAP verification. Each function enforces its own authorization, idempotency, and audit logging — because I understood that server-side trust is a product feature, not just an engineering concern.
- **27 database migrations** evolving the schema from a simple bet tracker to a multi-tenant platform with hash-chain ledger integrity, atomic settlement transactions, and row-level security policies.
- **Smart API budgeting** — the live scores system estimates game durations by sport and only polls the Odds API when games are in their finishing window. This is a cost optimization that required product judgment: how stale is too stale? (Answer: 5 minutes during the last 30 minutes of a game.)
- **Offline-first architecture** — local storage for everything, cloud sync when online. This isn't just a technical choice; it means the app feels instant, and I designed loading states around sync completion rather than network latency.

---

## Outcomes & Reflection

### By the Numbers

| Metric | Value |
|--------|-------|
| Timeline | ~2 months |
| Commits | 789 |
| Lines of code | ~43,000+ |
| iOS views | 67 |
| Edge functions | 26 |
| Database migrations | 27 |
| Landing pages | 16+ |
| Blog posts | 8+ |
| Design phases completed | 20 |
| Stress test assertions | 142 across 15 suites |

### What I'd Do Differently

- **Start with the web dashboard, not iOS.** The web-first pivot was the right call, but I'd have reached it faster by shipping the web experience first and treating native as the upgrade.
- **User-test the organizer onboarding earlier.** The standalone-first flow was a redesign born from watching people stall at the role-selection fork. Earlier testing would have caught this sooner.
- **Design the attention tag system from day one.** It became the most compelling organizer feature, but it was a late addition. If I'd centered the organizer experience around "here's who needs your attention" from the start, every other feature would have been better contextualized.

### What This Demonstrates

- **End-to-end product ownership** — from market insight to information architecture to pixel-level UI to production backend to marketing site.
- **Product-minded design** — every design decision tied to a business thesis (trust, pricing as positioning, compliance as UX win).
- **Systems thinking** — designing across iOS, web, and server-side with consistent mental models and intentional platform divergence.
- **Technical fluency** — not just "familiar with code" but shipping production systems with real architectural tradeoffs (offline-first, server-authoritative, hash-chain integrity).
- **Constraint-driven creativity** — App Store compliance language becoming a friendlier product voice; API rate limits becoming smart polling; pricing model becoming brand positioning.

---

*Built by Tyler Kung. 2026.*
