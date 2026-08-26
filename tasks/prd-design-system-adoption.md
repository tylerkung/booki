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
4. **Type is split three ways (medium).** CORRECTED 2026-08-25 — the original
   entry said "web is Inter, iOS is IBM Plex Sans" and recommended bringing web
   to IBM Plex Sans. The product is already there; the real split is:

   | surface | loads |
   |---|---|
   | dashboard + admin (the product) | IBM Plex Sans — matches iOS |
   | marketing site | Inter |
   | the design-system site itself | Inter |
   | `--font-sans` token claims | Inter |

   So the token is wrong for the product, `dashboard.css:40` hardcodes around it,
   and the DS documents Booki's type in a typeface the product does not use.
   Resolving it is a brand call, not a cleanup — left open deliberately.
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
| Families | Inter + JetBrains Mono | IBM Plex Sans + Space Grotesk (product); Inter (marketing) |
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


---

## Implemented 2026-08-25 — tracking scale + numerals

**Tracking.** 51 raw `letter-spacing` declarations across five stylesheets
collapsed to seven tokens. The defect was two unit systems for one job: px
tracking does not scale with font-size, so the same `0.5px` meant 0.045em on an
11px label and 0.036em on a 14px one. Each value mapped to its nearest token, so
nothing moved by more than ~0.15px — verified in the browser (`.card-title`
0.50px → 0.52px, sidebar balance −0.50px → −0.44px).

**Numerals.** Two treatments, deliberately different:

- *Tabular figures* everywhere numeric. Proportional digits are drawn at
  different widths, so a balance ticking 1,180 → 1,220 visibly shifts and a
  column of stakes never aligns. Costs nothing visually.
- *Monospace* only for odds and scores — machine data read in columns. Money
  stays in the product's typeface: a balance is the member's own figure and
  belongs in Booki's voice.

`.gd-cell-line` was tried in the mono set and pulled back out: it carries a line
value on the board but the words "Over"/"Under" on player props, and words in a
monospace face are the decoration the rule exists to prevent.

**Bug found on the way.** `IBM Plex Mono` was named in four `dashboard.css`
rules and loaded by nothing, so `.odds-mono` had always fallen back to whatever
generic monospace the browser picked. It is now loaded (400/600/700 — the
weights those rules actually declare) and routed through `--font-mono`.
`check-design-tokens.py` did not catch the hardcoded family, which is a gap in
the checker worth closing.


---

## Implemented 2026-08-25 — motion tokens

**What was actually wrong.** Not the durations — the easing. `--ease` was defined
as the literal keyword `ease` and referenced **zero times**, so all 66 transition
declarations fell through to the CSS default, which is also `ease`: a curve that
*accelerates* out of the gate before settling. Every hover in the product was
starting slowly. That also silently contradicted the anti-patterns page, which
already required critically damped motion.

Measured after the change: **321 elements carry a transition, 0 still use the
browser default curve.**

**One curve.** `--ease-out: cubic-bezier(0.22, 1, 0.36, 1)` — easeOutQuint. It
was already in the codebase, used four times on the marketing scroll reveals,
and had never reached the product. A single curve is a system decision as much
as an aesthetic one: with one, nobody has to choose, and motion cannot drift the
way the tracking values did.

**Durations graded by what moves,** not by taste:

| token | was | now | for |
|---|---|---|---|
| `--dur-fast` | 0.15s | **0.12s** | feedback — colour, border, hover, focus |
| `--dur-base` | 0.2s | **0.18s** | state — toggles, form focus, small transforms |
| `--dur-slow` | 0.3s | 0.3s | layout — sidebar, width fills, accordions |
| `--dur-entrance` | — | **0.6s** | an element arriving |

`dashboard.css` turned out to already be fully tokenised on duration, so
retuning `--dur-fast` alone sped up 37 interactions without touching a rule.
`styles.css` held the raw values and was mapped by role — hover feedback on a
card moved to `--dur-fast` even where it had been 0.3s, while scroll reveals
kept their longer timing and their existing curve, because they are entrances
and are watched rather than felt.

**Reduced motion, structurally.** Rather than add a matching `@media` block to
each stylesheet — the omission that left three of four surfaces uncovered — the
guard re-points the four duration tokens inside one query in `tokens.css`. That
disables transition motion on dashboard, admin, marketing and the DS site at
once. `0.01ms` rather than `none`, because a zero-length transition still fires
`transitionend` and `none` never does, which would hang any handler waiting on
it.

Keyframes do not read tokens, so `dashboard.css` names its six directly, drawing
one distinction: entrances (toast, bet-slip bar, modal, check) are decoration and
are simply placed; the shimmer sweep stops because a skeleton communicates
through shape; **the spinner is kept and slowed**, because motion is its message
and stopping it turns "working" into "frozen".

**Not done.** `transition: all` appears 12 times in `dashboard.css`. It animates
every property including layout ones, and narrowing each to explicit properties
needs per-rule knowledge of what changes on hover — deferred rather than guessed.


---

## Implemented 2026-08-26 — contrast, focus, tap targets, enforcement

Phases 1, 2 and most of 3.

**The contrast count was wrong, and the checker is why.** The original audit
reported 11 failing pairs by measuring every foreground token against every
surface. Most were fiction: `--accent-secondary` only appears in gradients, and
`--final` / `--scheduled` are only ever text on their own tinted fill, never on
a raw surface. `check-contrast.py` parses actual rules instead — it pairs a
`color:` with the `background` set in the same rule, or with the page surfaces
when the rule sets none. That found **3 real failures**, then 3 more the manual
audit had missed entirely (`.attention-tag-purple`, `.attention-tag-pink`,
`.seo-pain-icon`).

It also encodes WCAG 1.4.11: icons and indicators are held to 3:1, not 4.5:1.
Holding an icon to the text threshold is not stricter, it is wrong, and it
pressures people into changing brand colours to satisfy a rule that does not
apply.

**Fixes.** `--text-muted` lifted #6B6B7B → #858595 (144 uses, now 5.43 / 5.03 /
4.52). Seven `--fill-*-foreground` tokens added so every tinted fill ships the
text colour that is legible on it — the shadcn pairing convention, applied where
the failures actually were rather than blanket across surfaces. 19 badge rules
repointed.

**Focus.** The base rule lives in `tokens.css`, which every surface loads,
because a rule that must be repeated in four files gets written in one — that is
precisely how the gap happened. `:where()` gives it zero specificity so any
component overrides it without a specificity war. Buttons and links take the
2px accent ring the DS always specified; inputs take `--shadow-focus` instead,
which had zero uses until now, because ringing a bordered input reads as a
double border. Verified with real Tab presses, not scripted focus — Chrome only
sets `:focus-visible` on genuine keyboard interaction.

**Tap targets.** The DS's own technique, not a blunt min-height: an invisible
`::after` centred on the control and stretched to `--tap-target`, so visual size
is unchanged and only the target grows. Controls take the real minimum under
768px, where thumbs are the input.

**Enforcement.** Three checks, each verified to actually fail by breaking the
thing it guards — a check that cannot fire is the inert-RLS-policy bug again.
All wired into `check-all.sh`, now 7 checks.

`check-design-tokens.py` caught the `--text-muted` lift as Theme.swift drift
within seconds of the change. Rather than delete the token from the map — which
would stop checking it forever and leave no way to tell a decision from an
omission — it gained a `THEME_DIVERGENCE` table that requires a written reason
and still reports on every run.

**Still open:** Phase 4 entirely (465 classes, no tooltip/select/progress/avatar),
Phase 5's live-example DS site, breakpoint duplicates, and `transition: all`
×12. Note the PRD's "tokenise breakpoints" item is not achievable as written —
custom properties are invalid inside media query conditions without a build step.


---

## Implemented 2026-08-26 — Phase 5, the docs-to-code loop

The design-system page now loads `../dashboard/dashboard.css` and renders the
product's real classes. Loaded BEFORE `ds.css`, so the page's own layout rules
still win — verified, no breakage.

**Avatars converted outright.** The nine `.ds-avatar` rules are deleted and all
36 references in `ds-content.js` point at the product's `.avatar`. The section
renders from `dashboard.css` alone. This is the shape the whole page should
eventually take.

**Three components could not be renamed, and that turned out to be the finding.**
The two systems do not model them the same way:

| | design system | product |
|---|---|---|
| badge | `won / lost / push / live / final` — what it MEANS | `success / danger / muted / accent` — how it LOOKS |
| btn | `--primary --secondary --ghost --lg --block` — intent | `-accent -grade-win -void -primary-full` — outcome |
| card | `card__head / card__foot` | `card-header / card-title` |

Those are different axes, not different spellings. Picking one is a design
decision, not a refactor, so instead of faking agreement the page now shows the
divergence: each component renders with the product's real classes beside a
union table marking which variants exist on each side.

**Of 20 button variants across the two systems, 3 exist on both.** That number
is now printed on the page rather than buried in two stylesheets.

**`check-ds-drift.py`** fails when a `.ds-*` class duplicates a product class.
The three above are listed in `KNOWN` with reasons and still print on a clean
run — the divergence stays visible rather than being resolved by forgetting it.
The first version derived base names by splitting on `-` and invented three
phantom duplicates (`.tag-tooltip` is not evidence of a `.tag`); it compares
exact class names now.

**All five PRD phases are now done.** `check-all.sh` runs nine checks.


---

## 2026-08-26 — semantic badge naming adopted

The badge question raised in the previous entry was decided in favour of the
design system's model: a badge is named for what it MEANS, not what colour it is.

The reason this mattered more than tidiness: the state-to-colour mapping lived in
`dashboard.js`, in **three separate functions that had drifted apart**. "What
colour is a won pick" was application logic, and restyling a state meant editing
behaviour. Now the domain word is the class and the stylesheet decides the look.

Ten semantic classes added — `won`, `lost`, `push`, `void`, `pending`,
`settled`, `scheduled`, `live`, `final`, `canceled` — and all three mappers
converted. The visual names stay for badges that genuinely are about appearance;
a member being active is not a pick outcome.

**Adopting the model resolved three collisions the visual naming had hidden:**

| state | was | now | why |
|---|---|---|---|
| `final` | `badge-success` — green | neutral | a completed game rendered the same green as a won pick. Finishing is not winning. |
| `scheduled` | `badge-muted` — grey | `--scheduled` purple | indistinguishable from settled. Uses a token that existed for this and had **zero uses**. |
| `void` | `badge-danger` — red | faint | identical to a loss. A void pick is not a loss; the stake comes back. |

`--scheduled` (0 uses) and `--final` (1 use) were effectively dead tokens that
existed for precisely this purpose.

**The drift table is now computed at runtime.** Generating it statically was
repeating the original mistake — a hand-written inventory of another file's
contents goes stale the moment that file changes, which is the drift the section
exists to expose. `renderDrift()` in `ds.js` reads the loaded stylesheets and
derives the comparison, the same way the colour swatches already read their hex
from the resolved token. Adding a variant to `dashboard.css` changes the table on
the next reload, with nothing to update by hand.

Badge convergence: **7 of 17 variants now agree, up from 2 of 14.**

**Still visual, deliberately:** member active/pending, invite has-email,
settlement collection status, and alert severity. Each is arguably its own
semantic domain, but none is a pick or game state, so they were left alone rather
than swept in.
