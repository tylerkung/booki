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

## Typography layer — added 2026-08-19

Nine role-named classes in `dashboard.css`, replacing 170 repeated inline
strings:

    .t-title  .t-body-strong  .t-strong  .t-body  .t-body-muted
    .t-caption  .t-label  .t-micro  .t-micro-muted

Nothing generic existed to reuse. All 244 classes in `dashboard.css` were
component-scoped, and 31 of them were purely typographic — `.pg-odds-na`,
`.event-time`, `.bs-card-event`, `.toggle-desc`, `.tag-tooltip-desc` are the
same few styles under different names. That absence is *why* inline styles kept
being written: there was no generic style to reach for, so every new element got
a new one-off.

Those 31 component-scoped classes are left in place. They are largely the same
nine roles, and should be folded in when the component is next touched rather
than in a blind sweep.

Documented in the design system under Typography → Web roles, with specimens
that render at their true sizes rather than approximating with the iOS classes.

## Enforcement

`scripts/check-design-tokens.py` fails on any literal that bypasses the token
layer — colour, font-size, font-weight, radius, z-index, transition, and
off-grid spacing — across `dashboard.css` and the inline styles in
`index.html` / `login.html`. Deliberate exceptions live in an `ALLOW` table at
the top of the script with a stated reason.

It covers colour, font-size, font-weight, line-height, radius, z-index,
transition, and spacing — in `dashboard.css` and in inline styles.

Run it in a pre-commit hook or CI. The point is that this audit does not have to
be repeated by hand.

**Dimensions** are covered by a different rule than spacing: a size used **three
or more times** is a design decision and must be named; a size used once or
twice is a bespoke layout constraint and stays a literal, because naming it
moves the number without making it reusable.

**Skeleton geometry is exempt.** A shimmer bar is 100px wide because that is
roughly how wide a name looks. Those values are deliberately arbitrary and
tokenising them would invent meaning that is not there. 88 of the 151 inline
dimension values turned out to be skeletons — and every off-grid dimension in
the file (14, 22, 70, 90) was one of them. The real dimensions were already on
the 4pt grid without being asked.

## Dimension tokens — added 2026-08-19

19 named sizes covering 200 values, plus `--hairline` for the 107 one-pixel
borders:

    --dot-sm 4   --dot 6   --dot-lg 8   --icon-xs 16   --icon-sm 18
    --icon-md 20   --icon-lg 24   --badge 28   --avatar-xs 32   --tile 36
    --control 48   --avatar-sm 56   --avatar 64   --avatar-lg 80
    --odds-col 90   --w-panel 280   --w-panel-lg 320   --w-form 480
    --w-content 768

Named by role, which required looking at the markup rather than the numbers:
36px is the rounded icon tile, 28px the numbered step badge, 20px the sidebar
nav icon, 56px the circular avatar, 80px the auth logo.

Value-preserving by construction — each token equals the literal it replaced —
and confirmed by the resolved-value diff: **0 changed values across all three
files**, with declaration counts unchanged (1551, 1989, 30).

A counting bug in the first inventory is worth recording: `\bbottom:` also
matches inside `border-bottom: 1px solid`, which inflated the apparent dimension
count from 219 to 290 and invented a phantom cluster of 65 "1px dimensions"
that were really borders. The fix is a `(?<![-\w])` guard before every
dimension property name.

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
