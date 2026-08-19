# Web Dashboard vs Design System — Audit

Date: 2026-08-19 · Source: `landing/dashboard/dashboard.css`, `landing/dashboard/index.html`
Measured against `Booki/DESIGN_SYSTEM.md` / `landing/design/`

## Summary

Colour *discipline* is strong — 322 of 324 inline colour declarations go through
a token. But the dashboard defines **its own token block**, and four of those
tokens disagree with the system, so the app is internally consistent while being
consistently wrong against the spec.

Spacing and radius have no token layer at all.

## P1 — Token values that disagree — RESOLVED 2026-08-19

Every error state, warning and rounded corner in the web app differs from iOS.

| Token | Dashboard | System | Effect |
|---|---|---|---|
| `--danger` | `#FF4D6A` | `#FF6B6B` | every error, loss and destructive action is a different red |
| `--warning` | `#FFB347` | `#FFA94D` | every pending/attention state is a different orange |
| `--radius` | `12px` | `16px` | **every card, modal and sheet** is one step tighter |
| `--radius-sm` | `8px` | `12px` | **every button, chip and input** is one step tighter |

The radius pair is the most visible: it applies to essentially every surface, so
the web app reads as a slightly different product to the iOS app side by side.

## P2 — System tokens with no equivalent — RESOLVED 2026-08-19

`gold` `#FFE66D`, `scheduled` `#7B68EE`, `finalStatus` `#5C5C6F`

Nothing in the dashboard mapped to these, so status colours for upcoming/final
events and gold highlights were improvised per use site or simply absent. All
three are now defined as `--gold`, `--scheduled` and `--final-status`.

## P2 — No spacing scale — RESOLVED 2026-08-19

The dashboard defined no spacing tokens.

Resolved for `dashboard.css`: `--s-xxs` through `--s-xxxl` added, 264 token
references, **zero off-grid values remaining**. Migrated in two passes — 194
exact matches converted with no visual change, then 60 off-grid values rounded
up (6→8, 10→12, 14→16) after checking the running app.

Verified against live data: no element overflows, the body does not scroll
horizontally, and the odds buttons — the tightest component, and the one that
carried three of the 6px values — render cleanly in their three-column row.

The 20 raw px values left (`16, 20, 28, 36, 40, 72`) are all divisible by 4 and
compliant; they simply have no name in a scale that jumps 16 → 24 → 32 → 48.

**Inline styles in `index.html` are untouched** — 129 off-grid values remain
there.

## P3 — Type off the scale — RESOLVED 2026-08-19

415 `font-size` declarations, none tokenised, across 18 distinct sizes.

The web app was given its **own** 9-step scale rather than being conformed to
`Booki/DESIGN_SYSTEM.md`. That scale is built on Apple text styles with a 17px
body; the dashboard is a dense desktop UI whose dominant size is 13px (132 of
415 declarations). Conforming to iOS would have enlarged nearly every text
element on the page. Colour, spacing and radius are genuinely shared with iOS —
type sizes are not, and pretending otherwise is what let 18 ad-hoc sizes appear.

    --fs-micro 11   --fs-caption 12   --fs-sm 13   --fs-body 14   --fs-lg 16
    --fs-title3 18  --fs-title2 22    --fs-title1 28   --fs-display 40

57 declarations moved by 1–2px to land on it; 358 were already on a step.

## P3 — Radius values in the wild — RESOLVED 2026-08-19

121 declarations over 12 values, now 5 tokens. `50%` was kept **separate** from
`999px` as `--radius-circle`: on a non-square element the two are not
interchangeable — 50% yields an ellipse, 999px a stadium — so collapsing them
would have silently reshaped elements.

## P3 — Inline style volume — RESOLVED (values), OPEN (structure) 2026-08-19

869 inline `style` attributes in `index.html`. Every *value* inside them now
references a token, so a palette or scale change reaches them. The attributes
themselves remain: extracting 869 inline styles into classes is a separate
refactor with real regression risk, and it is no longer blocking, because the
values are no longer literals.

32 `:style` Alpine bindings were left alone — their contents are JS expressions,
not CSS text.

## Stale literals this uncovered

Consolidating found colour literals that had silently stopped matching their
tokens. Each was a tint frozen at a colour the palette had moved off:

| literal | was | now |
|---|---|---|
| `rgba(255,77,106,…)` ×6 | old `--danger` `#FF4D6A` | `--danger` `#FF6B6B` |
| `rgba(255,179,71,…)` ×2 | old `--warning` `#FFB347` | `--warning` `#FFA94D` |
| `rgba(255,176,32,…)` ×3 | `#FFB020`, never a token | `--warning` |
| `rgba(255,193,7,…)` ×2 | `#FFC107`, never a token | `--warning` |
| `rgba(255,140,0,…)`, `#FF8C00` | `#FF8C00`, never a token | `--warning` |
| `rgba(100,149,237,…)`, `#6495ED` | old `--scheduled` | `--scheduled` `#7B68EE` |

`.attention-tag-orange` was the clearest case: `background: rgba(255,140,0,.15)`
paired with `color: var(--warning)` — the tint and the text were different
oranges. This is the concrete argument for the token layer: these did not look
broken, so no visual review would have caught them.

## Enforcement

`scripts/check-design-tokens.py` fails on any literal that bypasses the token
layer — colour, font-size, font-weight, radius, z-index, transition, and
off-grid spacing — across `dashboard.css` and the inline styles in
`index.html` / `login.html`. Deliberate exceptions live in an `ALLOW` table at
the top of the script with a stated reason.

Run it in a pre-commit hook or CI. The point is that this audit does not have to
be repeated by hand.

## Verification method

A mechanical rewrite of this size needs proof, not a spot check. Two passes:

1. **Static** — resolve every `var()` back to its literal in both the old and
   new files and diff declaration by declaration. Declaration counts matched
   exactly (1529→1529 CSS, 2389→2389 inline, 30→30 login), so nothing was
   dropped, duplicated or misaligned.
2. **Rendered** — snapshot 19 computed properties on ~3,900 elements across 13
   routes before and after, then diff.

Every surviving difference was an intended consolidation or a stale-literal fix.

The static pass caught a real regression the rendered pass would have missed:
mapping `#00D4B8` to `--accent` collapsed two CTA gradients from
`#00F5D4 → #00D4B8` into a flat fill. Restored as `--gradient-accent`, with
`--accent-deep` documented as *not* interchangeable with `--accent`. **Lesson:
mapping a colour literal to a token is unsafe when the literal is one stop of a
gradient whose other stop maps to the same token.**

## What is already right

- 322/324 inline colour declarations use `var(--token)`; only 2 literals (`#000`)
- Core surfaces, text and accent tokens match the system exactly
- Only 7 hardcoded hex occurrences in the whole stylesheet outside `:root`

## Suggested order

1. ~~Align the four token values~~ — **done**. Compared side by side first: the
   spec's corners are rounder and its red and orange warmer. No other file
   hardcoded the old values, so the change was contained to `:root`.
2. ~~Add the missing status tokens~~ — **done**.
3. ~~Introduce a spacing scale~~ — **done** for `dashboard.css`. Inline styles
   in `index.html` still carry 129 off-grid values.
4. **Snap the loose radii** to the two tokens.
5. **Type scale** last — the largest mechanical change for the least visible gain.
