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

## P3 — Type off the scale

The system defines 34 / 28 / 22 / 17 / 16 / 15 / 13 / 12 / 11.

- **41 of 113** `font-size` declarations in CSS are off-scale
- **86 of 298** inline `font-size` declarations are off-scale
- `14px` is the biggest offender — 46 inline uses, 22 in CSS — sitting between
  the scale's 13 and 15

## P3 — Radius values in the wild

Beyond the two tokens, raw radius values appear directly:

- CSS: `6`(×6) `4`(×3) `3`(×2) `2`(×2) `1` `10` `8` `12` `16` `999`
- Inline: `10`(×10) `4`(×8) `6`(×7) `8`(×4) `3`(×2) `20` `99` `999`

Ten distinct radii against a system that defines two plus full.

## P3 — Inline style volume

`index.html` carries **869 `style` attributes / 2,389 declarations**. Most
repeated: `color` (325), `font-size` (298), `margin-bottom` (228),
`display` (192), `padding` (135).

This is where drift accumulates — a value written inline is never reviewed
against a token.

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
