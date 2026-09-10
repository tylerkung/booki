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
design-system/build-tokens.py  the assembler
        ↓
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

A brand file must define these seven tokens. `core.css` and `core.rules.css`
reference them and define none of them, so a brand file that omits one produces
a page that renders but is subtly broken:

| token | what breaks without it |
|---|---|
| `--accent` | focus rings and every accented surface |
| `--focus-ring`, `--focus-ring-offset`, `--shadow-focus` | keyboard focus is invisible |
| `--font-sans`, `--font-display`, `--font-mono` | every face falls back to the system stack |

Nothing else in core reaches for a brand token. The check is mechanical — grep
core and core.rules for `var(--x)` where `x` is not defined in core — and it is
worth re-running after any core edit rather than trusting this table.

`--font-cta: var(--font-display)` deliberately stays in core: *the CTA is set in
the display face* is a structural decision, while *which* display face is the
brand's business.

Fonts are named here but **not loaded**. Each consuming page is responsible for
actually requesting the faces `--font-sans` / `--font-display` / `--font-mono`
name. `scripts/check-font-loading.py` is what catches a page that names a face
it never loads — an unloaded webfont is invisible in review, because the
fallback renders perfectly well.

`--wave-texture` in the brand file points at an absolute `/assets/wave.png`.
That is deliberate: the same token is read from `landing/`, `landing/dashboard/`
and `landing/admin/`, which sit at three different depths, so a relative URL
would resolve correctly in at most one of them.

### Section names

The assembler slices each file into labelled `/* ── name ── */` sections and
emits them in the fixed `ORDER` list. Two rules, both enforced with an error:

- core and brand may not define a section with the same name;
- every name in `ORDER` must exist.

The first rule exists because `slug()` folds any label beginning with `type`
onto the type scales — a brand section called `typeface` would have replaced
core's entire web type scale with three font families, silently. That is why
the faces live under `families`.

## Regenerating

```sh
python3 design-system/build-tokens.py           # write landing/tokens.css
python3 design-system/build-tokens.py --check   # fail if it is stale
```

The `--check` form runs inside `scripts/check-all.sh`, so a source edit that
was never rebuilt fails the suite rather than shipping a tokens.css that
disagrees with its own sources.

## Reusing this in another project

Copy the whole directory. It is self-contained — sources and assembler — and
the only edits needed are in one file.

```sh
cp -r design-system/ ../newproject/design-system/
cd ../newproject
git mv design-system/brand-booki.css design-system/brand-acme.css
```

Then in `design-system/build-tokens.py`, point `BRAND` at the renamed file and
`OUT` at wherever that project serves its stylesheet from. Rewrite every value
in the brand file; keep every section name. Run it, and the new project has
Booki's structure in its own colours and faces.

**Copy rather than submodule.** The earlier plan here was a git submodule, and
that was the wrong call for two static sites. A submodule buys upstream updates
and costs a clone-time footgun on every checkout, and neither project has a
build step to absorb it. More to the point, the second product *should* diverge
— it will want its own spacing rhythm eventually — and a submodule makes the
useful thing (editing core) the awkward thing. Copy, and treat drift as
expected rather than as failure.

**What does not travel yet.** The five token-aware check scripts
(`check-design-tokens`, `check-contrast`, `check-motion`, `check-focus-states`,
`check-ds-drift`) live in `scripts/` and hardcode `landing/…` paths. They are
the most valuable part of this system to reuse — they are what keep the tokens
honest, and every silent failure this system has hit was caught by one of them
— but they need their paths parameterised first. Until then a consumer gets the
tokens without the enforcement, which is the tokens without the part that makes
them stay true.
