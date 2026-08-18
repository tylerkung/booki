# PRD: Odds Transparency for Organizers

Status: draft for discussion · Created 2026-08-18

## Introduction

An organizer is being asked to run their book on numbers they did not set and
cannot see the origin of. When a line looks stale or a game shows no price, the
software looks broken or — worse — looks like it is doing something in its own
favour. Neither is true, but nothing in the product currently says so.

This is a trust problem, not a features problem. The mechanics are already
documented for internal use in `docs/odds-explained.md` and the published
reference page. This PRD is about surfacing an organizer-appropriate version
in-product, plus the small runtime signals that make the system legible while
it's running.

**The underlying pitch:** Booki does not set lines, does not take the other side,
and does not profit from a member losing. Making that visible is a competitive
advantage against pay-per-head services, where the pricing is opaque by design.

## Goals

- An organizer can answer "where do these odds come from" without asking
- A stale or missing price reads as a known, explained behavior rather than a bug
- The neutrality of the software is stated plainly and visibly
- No change to how odds actually work — this is explanation, not mechanism

## User Stories

### US-001: "How odds work" page in Settings
**Description:** As an organizer, I want to understand the odds pipeline in plain language, inside the app.

**Acceptance Criteria:**
- [ ] New row in Settings, following the existing navigable-row pattern (Profile, Change Password, Pick Management, About)
- [ ] Content adapted from `docs/odds-explained.md` — organizer-appropriate, not developer-facing
- [ ] Covers: odds are bought from a data provider that aggregates real sportsbooks; Booki does not set them; refresh cadence; the 48h visibility window; why finished games show no odds; why futures behave differently
- [ ] Uses approved compliance vocabulary throughout (Organizer, Member, Pick, Stake)
- [ ] Uses `.cardStyle()` and Theme tokens, consistent with other Settings detail pages
- [ ] Mirrored in the web dashboard, not iOS-only

### US-003: Source attribution
**Description:** As an organizer, I want to see that prices come from a real market.

**Acceptance Criteria:**
- [ ] Brief, consistent attribution on odds surfaces — e.g. "Lines aggregated from US sportsbooks"
- [ ] Links to the "How odds work" page
- [ ] Wording checked against compliance vocabulary and against what the provider's terms permit regarding attribution

### US-004: Empty state — RESOLVED 2026-08-18 (option a)
**Description:** As an organizer, I don't want to see games with no prices.

Members were already unaffected after the 48h display window shipped. The
organizer gap was structural: `EventsListView` used a 14-day horizon while
`sync_games` stores odds for 7 days, leaving ~9 games priceless and unexplained.

Resolved by narrowing the organizer horizon rather than explaining the gap.
`Event.organizerWindow` is **6 days**, deliberately a day inside the 7-day
storage window: sync runs twice daily, so a game that has only just crossed into
storage can be priceless for up to 12 hours. Six days guarantees at least two
syncs have covered anything shown.

```
organizer sees at 14 days (before):  42 games,  9 without odds
organizer sees at  6 days (after):   33 games,  0 without odds
```

**Acceptance Criteria:**
- [x] Organizer horizon narrowed to a value inside the storage window
- [x] Verified 0 priceless games in the organizer view
- [ ] Still worth a short line on a finished game's pick detail noting that odds
      live on the pick itself, so history is unaffected
- [ ] A game starting today with no price remains a genuine fault and must not
      read as normal — no copy should make that case look expected

### US-005: Neutrality statement
**Description:** As an organizer, I want to know the software is not playing against my members.

**Acceptance Criteria:**
- [ ] Plain statement that Booki does not set lines, does not adjust them per member, does not take a position, and does not profit from member losses
- [ ] Placed where an organizer forms trust — onboarding, the odds page, and the marketing site
- [x] Confirmed accurate 2026-08-18: per-member line adjustment is not planned, so the claim is safe to make unconditionally

### US-006: "How to run your group" guide
**Description:** As a new organizer, I want to understand how running a group actually works before I commit to it.

This is the piece most likely to convert hesitation into a first invite. It
explains the whole loop end to end, in order, in plain language:

1. **Set up** — create your group, set defaults (credit limit, win limit)
2. **Invite** — send a code or link; members sign up and are attached to you
3. **Members pick** — they browse games and place picks themselves; no manual entry
4. **You set the guardrails** — per-member credit and win limits, and what
   happens when a limit is hit (suspend picks vs require approval)
5. **You monitor** — open activity, exposure, who is up and who is down
6. **Picks grade automatically** — results land, picks settle, balances update
   with no action from you
7. **You settle up off-platform** — cash, Venmo, whatever you already use — and
   record it with Settle Up so balances zero out

**Acceptance Criteria:**
- [ ] Covers all seven steps above with the real UI names
- [ ] States plainly that **Booki never touches money** — no deposits, no
      payouts, no processing. Organizers settle off-platform and record it.
      This is both the compliance position and a genuine reassurance
- [ ] Explains that grading and balance updates are automatic, since manual
      settlement is the single biggest chore this replaces
- [ ] Uses approved compliance vocabulary throughout
- [ ] Lives in-product (Settings, near US-001) *and* on the marketing site,
      where it doubles as high-intent SEO content — see
      `tasks/prd-seo-ai-ranking.md` US-003
- [ ] Reachable from organizer onboarding, not just findable after the fact

## Open questions

- **How much odds detail in US-001?** Full mechanics (storage windows, tiered
  refresh) risks reading as complexity; too little reads as evasive.
- **Should members see the odds explanation too?** It may build trust, or invite
  line-shopping arguments.
- **Where does US-006 sit in onboarding?** Before the first invite is where it
  would do the most good, but that front-loads reading during signup.
- **One guide or two?** US-001 (how odds work) and US-006 (how to run a group)
  overlap at the edges. They may read better merged as a single "how Booki
  works" guide with sections, rather than two Settings rows.

## Decisions taken

- **2026-08-18 — no per-member line adjustment.** Confirmed not planned, so the
  neutrality claim in US-005 can be stated unconditionally.
- **2026-08-18 — no freshness indicator.** US-002 (an "updated X ago" timestamp
  on odds) was dropped: sportsbooks don't surface this, and advertising
  staleness invites complaints rather than building trust.
- **2026-08-18 — empty state fixed by narrowing, not explaining.** Option (a):
  organizer horizon cut from 14 days to 6, inside the 7-day storage window.

## Prior art in this codebase

- `docs/odds-explained.md` — the source content
- `Booki/Views/SettingsView.swift` — navigable-row pattern
- Golf sport page — existing "Updated X ago" treatment
- `events.last_odds_update` — the data, already populated
