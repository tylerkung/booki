# Booki Design System

A minimalist design system for a premium sports betting experience.

---

## Philosophy

**Less, but better.** Every element earns its place. Remove until it breaks, then add back one thing.

---

## Colors

### Core Palette

| Token | Value | Usage |
|-------|-------|-------|
| `background` | `#0A0A12` | App background, sheets |
| `cardBackground` | `#14141F` | Cards, elevated containers |
| `elevatedBackground` | `#1E1E2D` | Modals, popovers, nested elements |
| `border` | `#2A2A3A` | Dividers, card edges |
| `divider` | `#22222E` | Subtle separation |

### Text

| Token | Value | Usage |
|-------|-------|-------|
| `textPrimary` | `#F8F8F8` | Headlines, primary content |
| `textSecondary` | `#A8A8B8` | Supporting text, labels |
| `textMuted` | `#6B6B7B` | Disabled, hints |

### Accent

| Token | Value | Usage |
|-------|-------|-------|
| `accent` | `#00F5D4` | Primary actions, links, focus, wins |
| `accentSecondary` | `#9D4EDD` | Gradients, variety, secondary emphasis |
| `accentTertiary` | `#FF006E` | Highlights, special elements |
| `gold` | `#FFE66D` | Gold highlights, streaks, achievements |

### Semantic

| Token | Value | Usage |
|-------|-------|-------|
| `danger` | `#FF6B6B` | Losses, negative balance, destructive, errors |
| `warning` | `#FFA94D` | Pending, attention needed, caution states |

### Status

| Token | Value | Usage |
|-------|-------|-------|
| `live` | `#00F5D4` | Live/in-progress indicators (matches accent) |
| `scheduled` | `#7B68EE` | Upcoming events |
| `finalStatus` | `#5C5C6F` | Completed/final events |

### Bet Results

| Token | Value | Usage |
|-------|-------|-------|
| `win` | `#00F5D4` | Winning bets (matches accent) |
| `loss` | `#FF6B6B` | Losing bets (matches danger) |
| `push` | `#A8A8B8` | Push/void bets (matches textSecondary) |

### Rules

1. **Electric cyan is primary.** `#00F5D4` is the signature color for actions, wins, and focus states.
2. **Semantic colors for data only.** Cyan for wins, red for losses. Never decorative.
3. **Gradients on buttons only.** Cyan-to-purple gradient for primary CTAs. Cards use solid backgrounds.

---

## Typography

### Scale

| Token | Size | Weight | Line Height | Usage |
|-------|------|--------|-------------|-------|
| `display` | 34pt | Bold | 1.1 | Hero numbers (balance, odds) |
| `title1` | 28pt | Bold | 1.2 | Screen titles |
| `title2` | 22pt | Semibold | 1.25 | Section headers |
| `headline` | 17pt | Semibold | 1.3 | Card titles, row labels |
| `body` | 17pt | Regular | 1.4 | Primary content |
| `callout` | 16pt | Regular | 1.4 | Secondary content |
| `subheadline` | 15pt | Regular | 1.35 | Supporting info |
| `footnote` | 13pt | Regular | 1.3 | Timestamps, metadata |
| `caption` | 12pt | Regular | 1.25 | Labels, badges |
| `micro` | 11pt | Medium | 1.2 | Chip text, tiny labels |

### Rules

1. **System font only.** SF Pro handles numbers beautifully.
2. **Three weights max per screen.** Regular, Semibold, Bold.
3. **Monospace for odds.** Use `.monospacedDigit()` for all numerical displays.

---

## Spacing

### Scale (4pt base)

| Token | Value | Usage |
|-------|-------|-------|
| `xxs` | 2pt | Icon-to-text tight |
| `xs` | 4pt | Inline elements |
| `sm` | 8pt | Related items |
| `md` | 12pt | Standard padding |
| `lg` | 16pt | Section spacing |
| `xl` | 24pt | Major sections |
| `xxl` | 32pt | Screen margins |
| `xxxl` | 48pt | Hero spacing |

### Rules

1. **4pt grid.** All spacing divisible by 4.
2. **Consistent insets.** Cards use 16pt padding. Lists use 16pt horizontal.
3. **Generous vertical rhythm.** When in doubt, add space.

---

## Radius

| Token | Value | Usage |
|-------|-------|-------|
| `cornerRadiusSmall` | 12pt | Buttons, inner elements, chips |
| `cornerRadius` | 16pt | Cards, modals, sheets |
| `full` | 9999pt | Pills, avatars |

### Rules

1. **Match container to content.** Large containers get large radius.
2. **Never mix.** All corners of an element use the same radius.

---

## Shadows

| Token | Value | Usage |
|-------|-------|-------|
| `none` | - | Default for standard cards. |
| `elevated` | Accent glow @ 15% opacity, radius 12 | Elevated/featured cards |

### Rules

1. **Shadows are rare.** Use elevation through color, not shadow.
2. **Accent glow for emphasis.** Elevated cards use a subtle cyan glow, not generic dark shadows.

---

## Gradients

| Token | Colors | Usage |
|-------|--------|-------|
| `buttonGradient` | `#00F5D4` → `#9D4EDD` | Primary CTA buttons |
| `rainbowGradient` | `#00F5D4` → `#9D4EDD` → `#FF006E` | Special/featured elements |
| `goldGradient` | `#FFE66D` → `#FFAA00` | Gold highlights, achievements |
| `cardGradient` | `#14141F` → `#0E0E18` | Subtle card depth |
| `backgroundGradient` | `#12121A` → `#0A0A12` | Screen backgrounds |

### Rules

1. **Gradients on primary buttons.** Cyan-to-purple for main CTAs.
2. **Solid backgrounds for cards.** Use `cardGradient` for subtle depth, never bright gradients.
3. **No animated gradients.** Static only.

---

## Motion

| Token | Duration | Easing | Usage |
|-------|----------|--------|-------|
| `instant` | 0.1s | ease-out | Micro-interactions (taps) |
| `fast` | 0.2s | ease-out | State changes, toggles |
| `normal` | 0.3s | ease-in-out | Navigation, modals |
| `slow` | 0.5s | ease-in-out | Complex transitions |

### Rules

1. **Purposeful motion.** Animation shows causality, not decoration.
2. **Reduce motion respected.** All animations honor system preference.
3. **Critically damped springs.** Damping 0.7–0.8. No bouncy animations.

---

## Components

### Cards

```
Background: cardGradient (#14141F → #0E0E18)
Border: 1pt, gradient (border @ 80% → border @ 30%)
Radius: cornerRadius (16pt)
Padding: lg (16pt)
```

Elevated variant adds accent glow shadow.

### Buttons

**Primary**
```
Background: buttonGradient (cyan → purple)
Text: background color (#0A0A12), headline weight
Radius: cornerRadiusSmall (12pt)
Height: 50pt
```

**Secondary**
```
Background: transparent
Border: 1pt, border (#2A2A3A)
Text: textPrimary, headline weight
```

**Destructive**
```
Background: danger (#FF6B6B)
Text: white
```

### Inputs

```
Background: cardBackground (#14141F)
Border: 1pt, border (#2A2A3A)
Border (focused): accent (#00F5D4)
Radius: cornerRadiusSmall (12pt)
Height: 50pt
Padding: md (12pt) horizontal
```

### Lists

```
Row background: cardBackground (#14141F)
Separator: divider (#22222E)
Row height: 56pt minimum
Padding: lg (16pt) horizontal
ScrollContentBackground: hidden
Background: background (#0A0A12)
```

### Status Badges

```
Pending: warning background @ 15%, warning text
Accepted: accent background @ 15%, accent text
Won: accent background @ 15%, accent text
Lost: danger background @ 15%, danger text
```

Pill shape (radius: full). Micro text. Uppercase.

---

## Iconography

| Rule | Guideline |
|------|-----------|
| Style | SF Symbols only |
| Weight | Regular for UI, Semibold for emphasis |
| Size | Match text size, or 20pt standard |
| Color | Inherit from text, or accent for actions |

---

## Layout Principles

### Hierarchy

1. **One focal point per screen.** The most important element is largest.
2. **Z-pattern for scanning.** Key info top-left and bottom-right.
3. **Progressive disclosure.** Show less, reveal on demand.

### Alignment

1. **Leading alignment.** Text aligns left (LTR).
2. **Numbers align right.** Currency, odds, scores.
3. **Grid-based layout.** 16pt margins, 8pt gutters.

### Density

1. **Breathing room.** White space is a feature.
2. **Touch targets.** Minimum 44pt for interactive elements.
3. **Scannable rows.** 56pt minimum row height.

---

## Anti-Patterns

**Never do:**

- Gradient backgrounds on cards (use solid/subtle cardGradient only)
- Decorative shadows or colored glows on non-featured elements
- Animated gradients
- Color for emphasis (use weight or size instead)
- Busy backgrounds
- More than 3 font weights per screen
- Bouncy animations (use critically damped springs)
- Skeuomorphic elements
- Default iOS colors (always use Theme tokens)

---

## Implementation Notes

### Swift/SwiftUI

All tokens are defined in `Theme.swift` as static properties on the `Theme` enum.

### View Modifiers

Reusable modifiers defined in `Theme.swift`:

- `.cardStyle()` — Standard card with gradient background and border
- `.elevatedCardStyle()` — Featured card with accent glow shadow
- `.darkBackground()` — Screen background gradient
- `.glowingBorder()` — Highlighted/selected state with cyan glow
- `.gradientText()` — Accent gradient overlay on text

### Dark Theme Lists/Forms

```swift
List {
    Section { ... }
        .listRowBackground(Theme.cardBackground)
}
.scrollContentBackground(.hidden)
.background(Theme.background)
```

---

## Changelog

| Date | Change |
|------|--------|
| 2026-02-04 | Initial design system created |
| 2026-02-16 | Updated to match current Theme.swift — electric cyan (#00F5D4) primary accent, multi-accent palette, gradient system, updated radius/shadow tokens |
