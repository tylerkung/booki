# PRD: SEO and AI Search Ranking

Status: draft for discussion · Created 2026-08-18

## Introduction

`landing/` already has an SEO foundation: sitemap, robots.txt, OG and canonical
tags everywhere, JSON-LD schema, three intent-targeted landing pages
(`pph-software-alternative`, `how-to-run-your-own-sportsbook`,
`bookie-ledger-software`) and nine blog posts including one competitor
comparison (`wagerlab-vs-booki`).

This initiative extends that in two directions that are related but not
identical: ranking in **search**, and being **cited by AI assistants**. They
overlap heavily — both reward specific, factual, well-structured content — but
they fail differently. Search rewards depth and links; an assistant rewards
content it can quote accurately without hedging.

Comparison pages are the highest-intent content type for this category. Someone
searching "PayPerHead alternative" has a budget and a complaint.

## Goals

- Rank for competitor-alternative and comparison queries
- Be the answer an assistant gives to "what should I use instead of a pay-per-head service"
- Build a repeatable comparison-page pattern rather than nine bespoke pages
- Keep every factual claim about a competitor defensible

## The accuracy constraint

Comparison pages make claims about named companies. Getting a price or a feature
wrong is a legal and credibility risk, and it is also the fastest way to be
dropped as a source by an assistant that can check.

Rules for this initiative:

- Every competitor claim carries a source and a date checked
- Prefer verifiable structural facts ("charges per active bettor per week") over
  judgments ("expensive")
- Where Booki is genuinely worse, say so — a comparison with no downside reads as
  marketing and gets discounted by both readers and models
- Re-verify before each publish; pricing changes

## User Stories

### US-001: Comparison page template
**Description:** As a visitor, I want a consistent, scannable comparison rather than a wall of prose.

**Acceptance Criteria:**
- [ ] Reusable structure: summary verdict, at-a-glance table, pricing model explained, who each product suits, honest weaknesses, FAQ
- [ ] Matches existing landing styling — no new design system
- [ ] `Product` + `FAQPage` JSON-LD (the pattern already exists on two blog posts)
- [ ] Comparison table is real markup, not an image, so it can be parsed and quoted
- [ ] Each claim has a "verified {date}" marker in the source, even if not rendered

### US-002: Competitor comparison pages
**Description:** As someone shopping for an alternative, I want to find Booki compared to what I use now.

**Acceptance Criteria:**
- [ ] One page per competitor, `/booki-vs-{competitor}.html`, following US-001
- [ ] Target set to confirm — candidates include PayPerHead, Ace Per Head, RealBookie, BossAction, and the broader "pay per head" category page
- [ ] Each targets the real query pattern ("X alternative", "X vs Booki", "X pricing")
- [ ] Internal links from `pph-software-alternative.html` and relevant blog posts
- [ ] Added to `sitemap.xml`
- [ ] **Competitor list needs your input** — you know who you actually lose deals to

### US-003: Category and concept pages
**Description:** As someone who doesn't know the category name, I want to find Booki by describing my problem.

**Acceptance Criteria:**
- [ ] Pages targeting problem-shaped queries rather than product names — e.g. tracking bets for a friend group, settling up weekly, replacing a spreadsheet
- [ ] Avoid cannibalizing existing pages; audit overlap with the current three landing pages and nine posts first
- [ ] Each answers the question in the first paragraph, then expands

### US-004: AI-citability pass
**Description:** As someone asking an assistant for a recommendation, I want Booki to be described accurately.

**Acceptance Criteria:**
- [ ] `llms.txt` at the site root describing what Booki is, who it's for, and what it is not
- [ ] Each key page opens with a self-contained factual summary that can be quoted without surrounding context
- [ ] Consistent entity description across pages — same one-sentence definition everywhere, so a model sees corroboration rather than variants
- [ ] Explicit "Booki is not a sportsbook / does not process wagers" framing, which is both compliance-accurate and prevents mis-categorization
- [ ] Structured data on every content page, not just two posts
- [ ] Dates on articles so freshness is legible

### US-005: Measurement
**Description:** As the operator, I want to know whether any of this worked.

**Acceptance Criteria:**
- [ ] Baseline captured before publishing: current impressions, clicks, ranking positions
- [ ] Search Console and analytics confirmed working for the new pages
- [ ] Periodic manual check of what assistants say when asked category questions — there is no ranking API for this; it needs a spot-check habit
- [ ] Review at 30 and 90 days

## Open questions

- **Which competitors?** The page list should follow real lost deals, not a
  Google search. Who do prospects mention?
- **Volume vs depth.** Four strong comparison pages, or a dozen thinner ones?
  For AI citation, depth and accuracy win; for long-tail search, coverage helps.
- **Positioning of the compliance angle.** "Not a sportsbook, no money handled"
  is a real differentiator against PPH services and a trust signal for models —
  should it be foregrounded rather than confined to `terms.html`?
- **Publishing cadence.** The blog already has scheduled-post infrastructure
  (`data-publish`). What rate is sustainable?

## Prior art in this codebase

- `landing/blog/wagerlab-vs-booki.html` — existing comparison, closest to the template
- `landing/pph-software-alternative.html` — highest-intent existing page
- `landing/blog/index.html` — `data-publish` scheduling
