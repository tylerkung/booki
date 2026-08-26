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
| beautifului.dev | Progressive disclosure, status/confidence, traceability | Applies to pick states and the settle-up trail |

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
  streaming; Booki has neither.
- **A visual redesign.** Nothing in the audit points at the aesthetic.
- **All 232 checklist items.** Maintenance items assume a multi-team design org.

## Caveat

Every number here is static analysis of four stylesheets — grep counts, computed
WCAG ratios, token reference counts. That establishes what is *absent*. It cannot
confirm what is present renders correctly, so Phase 1 ends with a keyboard pass
through the real dashboard, not a green check script.
