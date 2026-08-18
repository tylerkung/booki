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

### US-002: Odds freshness indicator
**Description:** As an organizer, I want to see how current a price is, so a lag is visible rather than suspicious.

**Acceptance Criteria:**
- [ ] "Updated X ago" shown on odds surfaces, sourced from `events.last_odds_update` — already populated on every sync
- [ ] Pattern already exists on the golf sport page; extend it rather than inventing a second treatment
- [ ] Visually de-emphasized — informational, not an alarm
- [ ] Consider a distinct state when a price is materially older than its tier's expected cadence (see `HIGH_FREQUENCY_LEAGUES` tiering in `auto_refresh_games`)

### US-003: Source attribution
**Description:** As an organizer, I want to see that prices come from a real market.

**Acceptance Criteria:**
- [ ] Brief, consistent attribution on odds surfaces — e.g. "Lines aggregated from US sportsbooks"
- [ ] Links to the "How odds work" page
- [ ] Wording checked against compliance vocabulary and against what the provider's terms permit regarding attribution

### US-004: Explain the empty state
**Description:** As an organizer, I want a game with no odds to explain itself.

**Acceptance Criteria:**
- [ ] A game outside the 48h window shows a short reason, not a dash — e.g. "Lines open 48 hours before start"
- [ ] A finished game's pick detail explains that odds are kept on the pick itself, so history is unaffected
- [ ] Distinguishes expected-empty from genuinely-missing; a game starting today with no price is a fault and should not be reassuring
- [ ] **This is the highest-value item here** — the dash with no explanation is what triggered the original investigation

### US-005: Neutrality statement
**Description:** As an organizer, I want to know the software is not playing against my members.

**Acceptance Criteria:**
- [ ] Plain statement that Booki does not set lines, does not adjust them per member, does not take a position, and does not profit from member losses
- [ ] Placed where an organizer forms trust — onboarding, the odds page, and the marketing site
- [ ] Factually accurate as written; if any per-member adjustment ever ships, this copy must change with it

## Open questions

- **How much detail?** Full mechanics (storage windows, tiered refresh) risks
  reading as complexity. Too little reads as evasive. Where's the line?
- **Should members see it too?** The same explanation may build trust with
  members, or may invite line-shopping arguments.
- **Is freshness a liability?** "Updated 2 hours ago" is honest, but it also
  advertises staleness. Does it increase trust or invite complaints?
- **Onboarding placement.** Worth adding to the organizer onboarding flow, or
  does that front-load complexity during signup?

## Prior art in this codebase

- `docs/odds-explained.md` — the source content
- `Booki/Views/SettingsView.swift` — navigable-row pattern
- Golf sport page — existing "Updated X ago" treatment
- `events.last_odds_update` — the data, already populated
