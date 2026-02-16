# PRD: Booki Marketing Landing Page

## Introduction

Create a marketing landing page for Booki that converts potential bookies into email waitlist signups. The page will communicate Booki's value proposition—helping bookies run their sportsbook like a business—and showcase features, pricing, and a clear path to getting started.

**Target Audience:** Independent bookies who currently manage their book manually (spreadsheets, notes, memory) and want a better system.

**Tech Stack:** Static HTML/CSS hosted on Netlify

## Goals

- Capture email addresses for waitlist/launch notification
- Clearly communicate what Booki does and who it's for
- Display pricing tiers to set expectations and qualify leads
- Establish credibility and trust with professional design
- Achieve fast page load (<2s) for SEO and user experience

## User Stories

### US-001: Set up project structure and build pipeline
**Description:** As a developer, I need a project structure for static HTML/CSS with a build process so I can develop efficiently and deploy to Netlify.

**Acceptance Criteria:**
- [ ] Create `landing/` folder in project root
- [ ] Set up `index.html`, `styles.css`, and `assets/` folder structure
- [ ] Add `netlify.toml` configuration file
- [ ] Create README with local development instructions
- [ ] Page loads successfully when opened in browser

### US-002: Create hero section with value proposition
**Description:** As a potential bookie visiting the site, I want to immediately understand what Booki does so I can decide if it's relevant to me.

**Acceptance Criteria:**
- [ ] "Coming Soon" badge above headline
- [ ] Headline: "Run your sportsbook like a business"
- [ ] Subheadline explaining the core value (track bets, manage players, settlements)
- [ ] Primary CTA button: "Join the Waitlist" (scrolls to email form)
- [ ] Secondary CTA: "See Pricing" (scrolls to pricing section)
- [ ] Placeholder app mockup/illustration (will be replaced with real screenshots later)
- [ ] Mobile responsive (stacks vertically on small screens)
- [ ] Verify in browser

### US-003: Create features section
**Description:** As a potential bookie, I want to see what features Booki offers so I can understand how it will help me.

**Acceptance Criteria:**
- [ ] Section headline: "Everything you need to run your book"
- [ ] 6 feature cards in 2x3 or 3x2 grid:
  - Player Management (track credit limits, balances, collection status)
  - Bet Tracking (straights, parlays, automatic odds calculation)
  - Live Odds Integration (import games from major sports)
  - Automatic Grading (bets graded when games finish)
  - Weekly Settlements (know who owes what, mark payments)
  - Risk Dashboard (exposure alerts, player watchlist)
- [ ] Each card has icon, title, and 1-2 sentence description
- [ ] Mobile responsive (single column on small screens)
- [ ] Verify in browser

### US-004: Create "How it Works" section
**Description:** As a potential bookie, I want to understand the workflow so I can visualize using the product.

**Acceptance Criteria:**
- [ ] Section headline: "Get started in minutes"
- [ ] 3-4 step process with numbered steps:
  1. Sign up and configure your book settings
  2. Add your players and set credit limits
  3. Import games from NFL, NBA, MLB, NHL
  4. Players bet, you track everything automatically
- [ ] Each step has icon/illustration and brief description
- [ ] Visual connector between steps (line, arrows, or similar)
- [ ] Mobile responsive
- [ ] Verify in browser

### US-005: Create pricing section
**Description:** As a potential bookie, I want to see pricing upfront so I can evaluate if Booki fits my budget.

**Acceptance Criteria:**
- [ ] Section headline: "Simple, transparent pricing"
- [ ] "Beta Pricing" badge indicating these are early-bird rates
- [ ] 3 pricing tiers displayed as cards:
  - **Starter** (Free): Up to 5 players, basic features, "Get Started Free"
  - **Pro** ($19/mo): Up to 25 players, all features, priority support, "Most Popular" badge
  - **Unlimited** ($49/mo): Unlimited players, all features, dedicated support
- [ ] Each card lists included features with checkmarks
- [ ] CTA button on each card scrolls to waitlist form
- [ ] Highlight recommended tier (Pro) with border/badge
- [ ] Mobile responsive (cards stack vertically)
- [ ] Verify in browser

### US-006: Create email waitlist form
**Description:** As a potential bookie, I want to join the waitlist so I get notified when Booki launches.

**Acceptance Criteria:**
- [ ] Section headline: "Be the first to know when we launch"
- [ ] Email input field with placeholder "Enter your email"
- [ ] Submit button: "Join Waitlist"
- [ ] Form submits to Netlify Forms (no backend needed)
- [ ] Success message appears after submission: "You're on the list!"
- [ ] Basic email validation (shows error for invalid format)
- [ ] Privacy note: "We'll never share your email. Unsubscribe anytime."
- [ ] Mobile responsive
- [ ] Verify in browser

### US-007: Create footer
**Description:** As a visitor, I want to see standard footer information for legitimacy and navigation.

**Acceptance Criteria:**
- [ ] Booki logo/name
- [ ] Copyright notice with current year
- [ ] Links: Privacy Policy, Terms of Service (link to placeholder pages)
- [ ] Social links placeholder (Twitter/X icon, optional)
- [ ] Mobile responsive
- [ ] Verify in browser

### US-008: Implement responsive design and polish
**Description:** As a mobile user, I want the page to look great on my phone so I can read about Booki anywhere.

**Acceptance Criteria:**
- [ ] Breakpoints: mobile (<768px), tablet (768-1024px), desktop (>1024px)
- [ ] Navigation collapses appropriately on mobile
- [ ] All text readable without zooming on mobile
- [ ] Touch targets at least 44x44px on mobile
- [ ] No horizontal scrolling on any screen size
- [ ] Smooth scroll behavior for anchor links
- [ ] Verify on mobile viewport in browser

### US-009: Add dark theme styling consistent with app
**Description:** As a potential user, I want the landing page to match the app's dark sports-betting aesthetic so the brand feels cohesive.

**Acceptance Criteria:**
- [ ] Dark background (#0A0A12 or similar from app Theme)
- [ ] Accent color: electric cyan/teal (#00F5D4)
- [ ] Secondary accent: purple (#9D4EDD)
- [ ] Text colors: bright white for headings, muted for body
- [ ] Card backgrounds slightly lighter than page background
- [ ] Buttons use gradient styling (cyan to purple)
- [ ] Verify in browser

### US-010: Create placeholder legal pages
**Description:** As a visitor, I want to see Privacy Policy and Terms of Service pages so the site feels legitimate and trustworthy.

**Acceptance Criteria:**
- [ ] Create `privacy.html` with placeholder Privacy Policy content
- [ ] Create `terms.html` with placeholder Terms of Service content
- [ ] Both pages use same dark theme styling as main page
- [ ] Include "Last updated" date placeholder
- [ ] Link back to main landing page
- [ ] Footer links on main page navigate to these pages
- [ ] Verify in browser

### US-011: Deploy to Netlify
**Description:** As a developer, I want to deploy the landing page so it's publicly accessible.

**Acceptance Criteria:**
- [ ] Site deployed to Netlify
- [ ] Custom subdomain configured (e.g., booki-app.netlify.app or similar)
- [ ] HTTPS enabled (automatic with Netlify)
- [ ] Netlify Forms receiving submissions
- [ ] Page loads in under 2 seconds on 3G connection
- [ ] Document deployment URL in README

## Functional Requirements

- FR-1: Page must be a single HTML file with linked CSS (no JavaScript frameworks required)
- FR-2: Email form must submit to Netlify Forms with `data-netlify="true"` attribute
- FR-3: All anchor links (Join Waitlist, See Pricing) must smooth-scroll to target section
- FR-4: Page must score 90+ on Lighthouse performance audit
- FR-5: All images must have alt text for accessibility
- FR-6: Page must work with JavaScript disabled (progressive enhancement)

## Non-Goals (Out of Scope)

- No actual account creation (waitlist only)
- No payment processing or Stripe integration
- No blog or content pages (single landing page only)
- No backend server (static site only)
- No analytics integration (can be added later)
- No A/B testing infrastructure
- No internationalization/multiple languages

## Design Considerations

- **Visual Style:** Match the iOS app's dark sports-betting theme
- **Typography:** Use system fonts or Google Fonts (Inter, SF Pro Display alternatives)
- **Icons:** Use simple SVG icons (Heroicons, Feather, or custom)
- **Imagery:** App screenshots or mockups showing key features
- **Layout:** Single-page scroll with distinct sections
- **Inspiration:** Modern SaaS landing pages (Linear, Vercel, Notion)

### Color Palette (from app Theme.swift)
```
Background: #0A0A12
Card Background: #14141F
Accent (Cyan): #00F5D4
Accent Secondary (Purple): #9D4EDD
Accent Tertiary (Pink): #FF006E
Text Primary: #F8F8F8
Text Secondary: #A8A8B8
Text Muted: #6B6B7B
```

## Technical Considerations

- **Hosting:** Netlify (free tier sufficient)
- **Forms:** Netlify Forms (100 free submissions/month)
- **Images:** Optimize with TinyPNG or similar before adding
- **CSS:** Use CSS custom properties for theme colors
- **No build step required:** Plain HTML/CSS works, but can add PostCSS later if needed

## Success Metrics

- **Primary:** Email signups (target: 100 in first month)
- **Secondary:** Page load time under 2 seconds
- **Secondary:** Bounce rate under 60%
- **Secondary:** Mobile traffic properly served (no UX issues)

## Open Questions

- What custom domain will be used? (e.g., getbooki.com, bookiapp.com)
- Any specific testimonials or social proof to include later?
