# PRD — Design System Adoption

**Status:** proposed · **Date:** 2026-08-25
**Readable version:** https://claude.ai/code/artifact/4fdd9dc7-5077-44d1-82a1-b3e9efe07fb3

## Premise

The brief was to expand the component library. The audit says inventory is not
the bottleneck — adoption is. Booki already has a token system, a 21-section
design-system site at `landing/design/`, and an opinionated set of rules. The
product largely does not implement them.

## The finding that reframes it

There are three `:focus-visible` rules in the codebase. All three are in
`landing/design/ds.css` — the design system's own documentation site.

| stylesheet | role | `:hover` | `:focus-visible` |
|---|---|---:|---:|
| `dashboard.css` | the product | 36 | **0** |
| `styles.css` | marketing | 21 | **0** |
| `admin.css` | admin | 3 | **0** |
| `ds.css` | the docs | 13 | 3 |

The DS specifies "2px accent, 2px offset, on every interactive element…
applied through `:focus-visible`". The token exists — `--shadow-focus` — and is
referenced **zero times**. Rule written, token defined, nothing consumes either.

## Findings

1. **Keyboard focus absent (critical).** Above. Documented 44px tap targets have
   1 implementation across all four stylesheets.
2. **11 of 30 colour pairs fail WCAG AA (high).** `--text-muted` (144 uses)
   scores 3.77 / 3.49 / 3.14 on background / card / elevated — fails AA normal
   text on every surface. `--final` scores 2.80 and 2.51, below the 3.0:1
   large-text floor.
3. **Motion undisciplined (medium).** 82 transition/animation declarations;
   `dashboard.css` has no `prefers-reduced-motion` block. Docs mandate
   "critically damped; nothing in Booki bounces" but the only easing token is
   `--ease: ease`, the browser default.
4. **Type diverges across platforms (medium).** `tokens.css` claims to mirror
   `Theme.swift`; true for colour, not type. Web body is Inter, iOS body is IBM
   Plex Sans. Space Grotesk is shared for display.
5. **464 classes, 10 named components (consolidation).** Against the 29 core
   components in designsystemchecklist.com.
6. **Breakpoints untokenised (low).** Six raw values; 768/769 and 900/901 are
   the same boundary written twice.

## What is already strong

`check-design-tokens.py` passes — every styled value routes through a token.
`ds.css` is 568 `var()` references against 1 hex literal. Elevation (6 shadows),
z-index (7 named layers), icon sizes (4), a 4pt spacing grid and a 10-step type
scale are complete scales. The radius nesting rule is a genuinely distinctive
decision.

This matters: **the enforcement pattern already works.** One check script keeps
the whole colour and spacing layer honest. The plan extends that proven
mechanism to rules that currently have nothing behind them.

## What each reference contributes

| Source | What we take | What it fixes |
|---|---|---|
| designsystemchecklist.com | 232-item frame (Design language, Foundations, 29 components, Maintenance) | A defensible target list for the component gap |
| shadcn/ui | `background` / `-foreground` token pairing | Makes contrast failures structurally impossible |
| emilkowal.ski | Purpose / frequency / speed; <300ms; never animate keyboard-initiated actions | Turns 82 ad-hoc transitions into a policy |
| coss.com/ui | 50+ component inventory on Base UI primitives | Reference for behaviours beyond appearance |
| beautifului.dev | Motion values, mono-for-data, dashed hairlines (see appendix) | Supplies the concrete curve/duration numbers Phase 5 needs |

## Phases

### 1. Make the documented rules true
- Base-layer `:focus-visible` keyed off `--shadow-focus`, not per-component
- Raise `--text-muted` to clear 4.5:1 on `elevated`; restrict or lift `--final`
- `prefers-reduced-motion` blocks in `dashboard.css` and `admin.css`
- 44px minimum on the dismiss/overflow controls the DS names

*First because it is the only phase that changes what users experience today,
and every item is already an approved decision — implementation, not design.*

### 2. Extend enforcement to cover them
- `check-contrast.py` — WCAG ratios for every foreground/surface pair
- `check-focus-states.py` — fail when `:hover` on an interactive selector has no
  focus counterpart. This is the check that catches the 60-to-0 gap
- `check-motion.py` — fail on >300ms transitions and on animations with no
  reduced-motion block
- Wire into `scripts/check-all.sh`

*The rules were documented and still didn't ship. Documentation didn't fail for
lack of quality — nothing enforced it.*

### 3. Adopt foreground pairing in the token layer
- Add `--card-foreground`, `--elevated-foreground`, `--accent-foreground` etc.,
  each verified against its own surface. Additive; existing names unchanged
- Resolve the type divergence, or record the split as deliberate in `tokens.css`
- Tokenise breakpoints; collapse the 768/769 and 900/901 duplicates

### 4. Consolidate before extending
- Map the 464 classes against the 29-component list; promote repeats, delete
  the one-offs they replace
- Build only the missing primitives already needed: tooltip (currently ad-hoc in
  `dashboard.js`), select, progress, avatar
- Document each in `ds-content.js` as it lands

*Adding components to a 464-class surface makes the next audit worse.*

### 5. Close the docs-to-code loop
- DS site renders live examples from the product stylesheets rather than
  re-describing them, so drift shows on the page
- Replace `--ease: ease` with the damped curves the anti-patterns section mandates
- Motion policy section; audit the 82 existing transitions against it

## Non-goals

- **Adopting shadcn/ui or Coss UI as dependencies.** Both are React on Base UI;
  the dashboard is Alpine.js and the marketing site is static HTML. Take the
  conventions, not the packages.
- **AI-interface components from beautifului.dev.** Built for agent reasoning and
  streaming; Booki has neither. Its *visual and motion* layer is worth taking —
  see the appendix.
- **A visual redesign.** Nothing in the audit points at the aesthetic.
- **All 232 checklist items.** Maintenance items assume a multi-team design org.

## Caveat

Every number here is static analysis of four stylesheets — grep counts, computed
WCAG ratios, token reference counts. That establishes what is *absent*. It cannot
confirm what is present renders correctly, so Phase 1 ends with a keyboard pass
through the real dashboard, not a green check script.


---

## Appendix — what to take from beautifului.dev

Measured from the live site via computed styles, not eyeballed.

### Take

**1. Motion values — you already have the curve.**
Their entrance easing is `cubic-bezier(0.23, 1, 0.32, 1)`. Booki's `.reveal`
uses `cubic-bezier(0.22, 1, 0.36, 1)`. Same curve (easeOutQuint), arrived at
independently. Their motion is `ease-out` and nothing else — 1,030 declarations,
zero bounce — which is what Booki's own anti-patterns section already mandates.

The gap is propagation and speed, not character:

| | beautifului.dev | Booki |
|---|---|---|
| Dominant interaction duration | **0.12s** (827 uses) | 0.3s (22), 0.2s (17) |
| Entrance | fade-up 0.3–0.6s @ easeOutQuint | 0.6–0.7s @ easeOutQuint |
| Easing token | curve set | `--ease: ease` (browser default) |
| Uses of the good curve | throughout | 4, all in `styles.css` |

Action: promote the curve into `tokens.css` as `--ease-out`, add
`--dur-interaction: 0.12s`, and retire `--ease: ease`. Interaction transitions
drop from 200–300ms to ~120ms. This is Emil Kowalski's speed argument with a
reference implementation attached.

**2. Monospace + tabular numerals for all data.**
They set every numeric in mono at 10.5–12.5px, letter-spacing -0.14px. Booki has
~50 distinct numeric-bearing classes (odds, balance, stake, profit, score,
credit, pnl) and 6 mono/tabular rules in `dashboard.css`. Largest visual upgrade
available for the least structural change — odds and balances are what members
actually read.

**3. Dashed hairline rules.** 1px dashed in a desaturated border colour, used to
separate sections and frame the content column. Booki has only solid
`--divider`. A dashed variant is a few lines and reads as considered.

**4. Section header pattern.** Bold title with an inline muted description on the
same line. Cheap scannability win for the game detail and admin tables.

**5. Typography — tokenise tracking.**

| | beautifului.dev | Booki |
|---|---|---|
| Families | Inter + JetBrains Mono | Inter + Space Grotesk (IBM Plex on iOS) |
| Size range | 10.5–21px; UI lives in 11–14px | 11–40px, 9 steps |
| Weights | 400/500/600/700 | 400/500/600/700/800 |
| Tracking | negative at every size, −0.011em → −0.02em | 8 raw values, mixed px and em, 1 token |
| Uppercase | none | 36 rules |
| Body default | 13px w500 | 14px w400 |

Their type reads tighter because they apply negative tracking universally,
scaling with size (−0.14px at 13px, −0.42px at 21px). Booki already does this —
`-0.02em` appears 10 times, matching their display value — but ad-hoc, across
eight raw values in mixed units with one token. Same drift shape as the focus
ring: right instinct, no system.

Action: a tracking scale with BOTH arms, which they don't need and Booki does —
`--ls-tight` (−0.011em, UI), `--ls-tighter` (−0.02em, display), and `--ls-caps`
(~0.08em) to replace the ad-hoc positive values on the 36 uppercase rules.

**6. Hierarchy by weight at one size.** Their section titles are 13px w600 inline
beside a 13px w400 description — differentiated by weight and colour, not size.
Worth adopting on dense surfaces (admin tables, game-detail rows, member lists).

### Don't take

- **Their compressed scale.** Their H1 is 21px, 1.6x body. Booki's 40px display
  exists because the product is read one-handed and quickly on a phone, where
  balance and odds must carry at a glance — the DS says so directly. A 21px
  ceiling suits a component gallery at desk distance, not this product.
- **Dropping uppercase labels.** Established Booki element; their system has zero
  caps so it offers no guidance here.
- **w500 body — flag, don't adopt yet.** On a dark ground 400-weight Inter does
  read thin, and this is likely part of the appeal. But it changes every screen
  at once. Try it on one view first.
- **The diagonal hatch texture.** It is
  `repeating-linear-gradient(-45deg, transparent 0 7px, rgba(255,255,255,.055) 7px 8px)`
  — the same idea as Booki's wave at the same opacity band (`--o-faint`, 0.05).
  Booki already has this job filled; a second texture competes with the first.
  If the framed-gutter effect is wanted, extend the wave rather than add a hatch.
- **JetBrains Mono.** The existing `--font-mono` system stack is fine, and web
  already loads two Google families. Use the stack, not a third webfont.
- **Their near-monochrome palette.** Booki's teal is brand equity.
- **Numbered section eyebrows,** except where order is real. Parlay legs are
  genuinely ordered and could carry them; generic sections shouldn't.
