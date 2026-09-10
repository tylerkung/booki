# Booki design system

Two CSS files and an assembler. `landing/tokens.css` — the file every styled
surface on the web already links — is now **generated** from the sources here.

```
design-system/core.css         structural tokens: spacing, radius, type scale,
                               tracking, CTA sizing, motion, layers, dimensions
design-system/brand-booki.css  colour: palette, channel triplets, tinted fills,
                               fill foregrounds, wave texture, elevation
design-system/core.rules.css   the two rules that need braces — reduced motion
                               and the input focus ring
        ↓  scripts/build-tokens.py
landing/tokens.css             generated; do not edit by hand
```

## Why the split

The point is that **`core.css` is reusable and `brand-booki.css` is not**.
Everything in core is a decision about structure — an 8px spacing rhythm, a
radius scale keyed to nesting depth, a 40px CTA height — and none of it says
anything about Booki. Swapping `brand-booki.css` for a `brand-<project>.css`
that defines the same token names gives another product the same structure in
its own colours, without forking the scale decisions.

The split is enforced, not aspirational: `build-tokens.py` emits sections in a
fixed order and fails if either file gains or loses one, so a colour token
added to `core.css` shows up as a build error rather than quietly making the
core file brand-specific.

## The contract

A brand file must define `--accent` and `--bg`. `core.css` references both —
focus rings are drawn in the accent, and several structural tokens composite
against the background — so a brand file that omits either produces a page with
invisible focus states. Nothing else in core reaches for a brand token.

Fonts are **not** loaded here. `tokens.css` names families in
`--font-display` / `--font-body`; each consuming page is responsible for
actually requesting them. `scripts/check-font-loading.py` is what catches a
page that names a face it never loads — an unloaded webfont is invisible in
review because the fallback renders fine.

`--wave-texture` in the brand file points at an absolute `/assets/wave.png`.
That is deliberate: the same token is read from `landing/`, `landing/dashboard/`
and `landing/admin/`, which sit at three different depths, so a relative URL
would resolve correctly in at most one of them.

## Regenerating

```sh
python3 scripts/build-tokens.py           # write landing/tokens.css
python3 scripts/build-tokens.py --check   # fail if it is stale
```

The `--check` form runs inside `scripts/check-all.sh`, so a source edit that
was never rebuilt fails the suite rather than shipping a tokens.css that
disagrees with its own sources.

## Reusing this in another project

Add the repo as a submodule and point the assembler at your own brand file:

```sh
git submodule add <booki-repo> vendor/booki-ds
cp vendor/booki-ds/design-system/brand-booki.css src/brand-acme.css
```

Then edit the `BRAND` path in your copy of `build-tokens.py`. There is no npm
package because this repo has no build step — the site is static HTML linking
plain CSS, and adding a package manager to distribute one generated file would
cost more than it saves.

**What does not travel yet.** The five token-aware check scripts
(`check-design-tokens`, `check-contrast`, `check-motion`, `check-focus-states`,
`check-ds-drift`) hardcode `landing/…` paths. They are the most valuable part
of this system to reuse — they are what keep the tokens honest — but they need
their paths parameterised before another project can run them. Until then a
consumer gets the tokens without the enforcement.
