# PRD: Knowledge Base

Status: draft for discussion · Created 2026-08-18 · Supersedes prd-organizer-odds-transparency

## Introduction

Organizers are being asked to run a book on software whose mechanics are
invisible to them. Where do the odds come from? Why does that game have no
price? What happens when a member hits their limit? Who handles the money?
Nothing in the product answers any of it, and an organizer who can't answer them
doesn't send the invite.

The original plan was a couple of explainer pages in Settings. That doesn't
scale — the same logic would add a fifth and sixth row within a year, and none
of it would be reachable from search. A **knowledge base** gives every answer a
stable URL, one destination to link from anywhere in the product, and a surface
that earns search traffic on the way.

It mirrors the existing blog rather than inventing a parallel system: same nav,
same card patterns, same static-page approach under `landing/`.

**The dividing line with the blog is subject, not tone.** The blog covers the
category and the problem space — how independent organizers handle settlements,
whether a spreadsheet is enough, what pay-per-head services actually charge. It
stands on its own without Booki existing. The knowledge base covers **Booki's
own mechanics** — what this button does, why that game has no price, what
happens when a limit is hit.

That line also keeps them out of each other's way in search: the blog targets
problem-shaped queries from people who don't know the category name, the
knowledge base targets product queries from people already using Booki. Two of
your own pages never compete for the same intent.

Existing blog posts stay where they are. `how-organizers-track-weekly-settlements`
and `spreadsheet-template-tracking-picks` are editorial pieces about the general
practice, not documentation of a Booki feature — moving them would cost their
existing URLs and mis-file them besides.

## Goals

- An organizer can self-serve the questions that currently have no answer
- Every explanation has a permanent URL, linkable from app, email and support
- Reference content earns long-tail search and gives assistants something
  accurate to cite
- Reuses blog styling and navigation; no new design system
- Scales to future topics without adding Settings rows

## Non-goals

- Ticketing, live chat, or any support-request workflow
- A CMS — these are static pages, edited in the repo like the blog
- Member-facing depth in v1; organizers are the audience whose hesitation blocks
  invites

## User Stories

### US-001: Knowledge base structure
**Description:** As an organizer, I want one place to look things up.

**Acceptance Criteria:**
- [ ] `landing/help/` with an index grouping articles by category
- [ ] Categories: Getting started · Running your group · How odds work · Limits and rules · Billing
- [ ] Reuses blog card patterns, nav bar and styling — no parallel design
- [ ] Nav link added across landing pages alongside Features and Blog
- [ ] Client-side search over titles and excerpts (static site, so no backend)
- [ ] Every article in `sitemap.xml`
- [ ] `FAQPage` or `HowTo` JSON-LD per article, following the existing blog pattern

### US-002: "How to run your group" — the flagship article
**Description:** As a new organizer, I want to understand the whole loop before committing.

Explains the cycle end to end, in order:

1. **Set up** — create your group, set defaults (credit limit, win limit)
2. **Invite** — send a code or link; members sign up attached to you
3. **Members pick** — they browse and place picks themselves; no manual entry
4. **You set guardrails** — per-member credit and win limits, and what happens
   when one is hit (suspend picks vs require approval)
5. **You monitor** — open activity, exposure, who's up and who's down
6. **Picks grade automatically** — results land, picks settle, balances update
   with no action from you
7. **You settle up off-platform** — cash, Venmo, whatever you already use — then
   record it with Settle Up so balances zero

**Acceptance Criteria:**
- [ ] Covers all seven steps using the real UI names
- [ ] States plainly that **Booki never touches money** — no deposits, no
      payouts, no processing. This is both the compliance position and the
      reassurance an organizer needs before inviting friends
- [ ] Emphasises that grading and balance updates are automatic; manual
      settlement is the biggest chore this replaces and prospects may not
      realise it's handled
- [ ] Approved compliance vocabulary throughout
- [ ] Linked from organizer onboarding, not merely findable afterwards

### US-003: "How odds work" article
**Description:** As an organizer, I want to know where the numbers come from.

**Acceptance Criteria:**
- [ ] Adapted from `docs/odds-explained.md`, rewritten for organizers rather
      than developers
- [ ] Covers: odds are bought from a provider aggregating real sportsbooks;
      Booki does not set them; the 48h visibility window; why finished games
      show no odds; why futures differ
- [ ] Includes the **neutrality statement**: Booki does not set lines, does not
      adjust them per member, takes no position, and does not profit when a
      member loses. Confirmed accurate — per-member adjustment is not planned
- [ ] Includes source attribution, checked against what the provider's terms
      permit
- [ ] Explains that a settled pick keeps the exact price it was taken at, so
      deleting old odds never affects history

### US-004: Supporting articles
**Description:** As an organizer, I want answers to the next questions I'll have.

**Acceptance Criteria:**
- [ ] Credit limits and win limits — what each caps, and the difference between
      suspending picks and requiring approval
- [ ] Settling up — how balances accrue and what Settle Up records
- [ ] How picks are graded — including multi-picks, pushes and voids
- [ ] Free vs Pro — member limits and what upgrading changes
- [ ] Each answers its question in the opening paragraph, then expands

### US-005: In-product entry points
**Description:** As an organizer, I want help where I get stuck, not just on the website.

**Acceptance Criteria:**
- [ ] Single Settings row ("Help" / "How Booki works") replacing the several
      explainer rows the earlier plan implied
- [ ] Contextual deep links where confusion actually occurs — the limits editor
      links to the limits article, Settle Up links to the settling article
- [ ] Opens the web knowledge base; no duplicated in-app copy to drift
- [ ] Member-facing entry point from Account (v2)

### US-006: Empty state — RESOLVED 2026-08-18
**Description:** As an organizer, I don't want to see games with no prices.

`EventsListView` used a 14-day horizon while `sync_games` stores odds for 7
days, leaving ~9 games priceless and unexplained. Members were already
unaffected after the 48h display window shipped.

Fixed by narrowing rather than explaining: `Event.organizerWindow` is 6 days,
deliberately inside the storage window, since sync runs twice daily and a game
that just crossed into storage can be priceless for up to 12 hours.

```
organizer sees at 14 days (before):  42 games,  9 without odds
organizer sees at  6 days (after):   33 games,  0 without odds
```

**Acceptance Criteria:**
- [x] Organizer horizon narrowed to inside the storage window
- [x] Verified 0 priceless games in the organizer view
- [ ] A game starting today with no price remains a genuine fault — no article
      should make that case read as expected

## Open questions

- **Cross-linking between the two.** A blog post on weekly settlement practice
  should probably link to the KB article on Settle Up, and vice versa. Worth a
  convention so it happens consistently rather than ad hoc.
- **Public or gated?** Public is better for search and for prospects evaluating
  Booki; it also means competitors read it.
- **Who writes it?** Voice matters — the founder voice in `how-we-built-booki`
  reads very differently from reference documentation.
- **Member-facing tier.** Worth a separate section, or does one KB serve both
  audiences with clear labelling?

## Decisions taken

- **2026-08-18 — blog and knowledge base split by subject.** The blog covers the
  category and problem space and stands alone without Booki; the knowledge base
  documents Booki's mechanics. Existing blog posts stay put — they are editorial
  pieces about general practice, not feature documentation. This also prevents
  the two from competing for the same search intent.

- **2026-08-18 — no per-member line adjustment.** Confirmed not planned, so the
  neutrality claim in US-005 can be stated unconditionally.
- **2026-08-18 — no freshness indicator.** US-002 (an "updated X ago" timestamp
  on odds) was dropped: sportsbooks don't surface this, and advertising
  staleness invites complaints rather than building trust.
- **2026-08-18 — empty state fixed by narrowing, not explaining.** Option (a):
  organizer horizon cut from 14 days to 6, inside the 7-day storage window.

## Prior art in this codebase

- `landing/blog/` — index with cards, per-article pages, `data-publish`
  scheduling, `Article` JSON-LD. The knowledge base should mirror this
  structure rather than invent one.
- `docs/odds-explained.md` — source content for US-003, already written in plain
  language
- `Booki/Views/SettingsView.swift` — navigable-row pattern for US-005
- `tasks/prd-seo-ai-ranking.md` — US-003 there (category and concept pages)
  targets problem-shaped queries and belongs to the blog side of the split
  above, not the knowledge base
