# Mobile Web Dashboard — UI Audit

**Device target:** 375px viewport (iPhone SE/13 mini/14/15)
**Date:** 2026-03-03
**Files audited:** `landing/dashboard/app.html`, `landing/dashboard/dashboard.css`, `landing/dashboard/dashboard.js`

---

## Executive Summary

The web dashboard has solid responsive bones — sidebar collapses to hamburger, tables convert to stacked cards at 768px, stats grid goes single-column at 480px. But there are **~20 visual issues** ranging from layout overflows to missing touch targets that degrade the mobile experience. The player-facing views (Games, Track, Bet Slip) have the most issues since they're the newest code. Organizer views are more mature but still have problems with information density on narrow screens.

---

## Critical Issues (Broken/Unusable)

### 1. Toast notifications overflow viewport

**Location:** `dashboard.css` line 647
**Problem:** `.toast-container` is `position: fixed; top: 24px; right: 24px` with no `max-width` or `left` constraint. Long toast messages (e.g., "Failed to update notification preferences") render at auto width and overflow the right edge of a 375px screen — text is clipped and unreadable.

**Fix:** Add mobile override:
```css
@media (max-width: 480px) {
    .toast-container { right: 12px; left: 12px; }
    .toast { max-width: 100%; }
}
```

---

### 2. Settlement table data-label attributes missing on some cells

**Location:** `app.html` lines 1545-1581
**Problem:** The 8-column settlement table converts to stacked cards at 768px via `td[data-label]::before { content: attr(data-label); }`. But several `<td>` elements are missing `data-label` attributes, so on mobile they render as unlabeled values — you see "$1,234" with no context of whether it's Starting Balance, Won, Lost, or Ending Balance.

**Fix:** Add `data-label` to every `<td>` in settlement table rows:
```html
<td data-label="Starting" ...>
<td data-label="Won" ...>
<td data-label="Lost" ...>
<td data-label="Adjustments" ...>
<td data-label="Ending" ...>
<td data-label="Status" ...>
<td data-label="Actions" ...>
```

---

### 3. Player games odds grid — team names truncate to 4-5 characters

**Location:** `dashboard.css` line 1560
**Problem:** At 768px breakpoint, `.pg-odds-btn` shrinks from 90px to 70px. On 375px with 16px body padding:
- Available width: 375 - 32 = 343px
- 3 odds buttons: 3 × 70px + 2 × 3px gap = 216px
- Team name gets: 343 - 216 - 8px gap = 119px
- At 12px font, that's ~10 chars — "Los Angeles..." or "Golden Sta..."

But the real problem is games with long spread lines (e.g., "+13.5 -110") which push the button content wider than 70px, causing the row to overflow or compress the team name to 4-5 chars.

**Fix:** Reduce odds buttons to 62px at a 480px breakpoint, drop spread line text to just the number (hide odds value on smallest screens), or switch to a 2-row stacked layout per team on very narrow viewports.

---

### 4. Picks table has 8-9 columns with no mobile card conversion

**Location:** `app.html` lines 1042-1065
**Problem:** The picks table has columns: Date, Member, Type, Pick, Odds, Stake, Status, (Actions). The `data-table` class does convert to cards at 768px, but several `<td>` cells are missing `data-label` attributes, and the "Pick" column contains long text like "Lakers -3.5 (-110)" that wraps awkwardly in the card layout.

**Fix:** Add `data-label` to all cells, and truncate/ellipsis the Pick column text on mobile.

---

## High Issues (Poor UX)

### 5. Member detail header buttons overflow on narrow screens

**Location:** `app.html` line 875
**Problem:** Member detail header uses inline `display:flex;justify-content:space-between` with the member name on the left and 3 action buttons (Settle Up, Adjust Balance, overflow menu) on the right. On 375px, the name truncates to ~6 chars while the 3 buttons (each ~100px) take 300px. The row is too cramped.

**Fix:** Stack the action buttons below the name on mobile, or collapse Settle Up / Adjust Balance into the overflow menu.

---

### 6. Bet slip quick stake buttons don't fit

**Location:** `app.html` lines 2379-2383
**Problem:** Quick stake buttons (+$1, +$5, +$25) sit alongside the stake input in a flex-wrap row. On 375px inside the bet slip modal (max-width 480px, padding 20px = 335px content), the input group (min-width 100px) + 3 quick buttons (each ~50px with gap) = 100 + 150 = 250px, which fits. But when the to-win display is also shown, it wraps to a second line, creating visual inconsistency between selections.

**Fix:** Move quick stake buttons to their own row below the input, full-width, evenly spaced.

---

### 7. Settlement week selector cramped on mobile

**Location:** `dashboard.css` line 1269
**Problem:** `.settlement-week-label` has `min-width: 200px` at the 768px breakpoint (reduced from 260px desktop). The week selector row has prev/next buttons + the week label + Export CSV button. On 375px: 32px (prev) + 200px (label) + 32px (next) + ~100px (export) = 364px. Barely fits, and the Export button may get pushed off or squished.

**Fix:** Hide "Export CSV" text on mobile, show just a download icon. Or move export to a separate row.

---

### 8. Dashboard stat tiles — large numbers overflow

**Location:** `dashboard.css` line 445
**Problem:** `.stat-value` is `font-size: 28px` with `font-family: Space Grotesk`. On 480px+ screens it's a 2-column grid, so each tile gets ~170px. A value like "$12,345.67" at 28px in Space Grotesk is ~150px wide — fits barely. But negative values like "-$12,345.67" overflow the tile padding. At 375px (1-column), it's fine since tiles are full-width.

**Fix:** Add `font-size: 24px` at the 768px breakpoint for `.stat-value`, and ensure `overflow: hidden; text-overflow: ellipsis` as fallback.

---

### 9. Event detail markets card — odds grid has no mobile layout

**Location:** `app.html` lines 641-704
**Problem:** The event detail markets section renders odds in a horizontal layout (home vs away with labels). The `.market-odds-cell` has `min-width: 100px`. With two cells + labels, the row needs ~300px+. On 375px with card padding, available width is ~311px — very tight, odds values may wrap.

**Fix:** Stack odds vertically on mobile (home above away) instead of side-by-side.

---

### 10. Financials card 2-column grid doesn't collapse

**Location:** `app.html` lines 1121-1144, 2659-2691
**Problem:** Pick detail and ticket detail financials cards use inline `grid-template-columns:1fr 1fr` (sometimes `repeat(4, 1fr)`). On 375px, a 4-column grid gives each cell ~78px, which is too narrow for "$1,234.56" values. The 2-column variant is borderline at ~155px per cell.

**Fix:** Add responsive override: `grid-template-columns: 1fr 1fr` at 768px, `1fr` at 480px for the 4-column variants. Keep 2-column for the simpler financials.

---

## Medium Issues (Visual Polish)

### 11. Mobile header doesn't show current page title

**Location:** `app.html` lines 37-44
**Problem:** The mobile header (56px fixed bar) shows the hamburger icon on the left and (for players) balance on the right. But there's no indication of which page the user is on. iOS shows the page title in the nav bar. On mobile web, after the header, you see the page content but the header is just blank space with a hamburger.

**Fix:** Add the current route name to the mobile header center (e.g., "Games", "Track", "Dashboard").

---

### 12. Cards have no horizontal margin on mobile

**Location:** `dashboard.css` line 789
**Problem:** `.main-content` padding at 768px is `72px 16px 24px`. Cards are full-width within this padding, so they sit 16px from screen edges. This is fine, but some cards have inner elements with their own `padding: 20px`, creating 36px total left inset. The visual hierarchy feels inconsistent — some content starts at 16px, some at 36px.

**Fix:** Reduce card padding from 20px to 16px at 480px breakpoint for tighter, more consistent spacing.

---

### 13. Search input max-width: 400px exceeds mobile viewport

**Location:** `app.html` line 2135
**Problem:** Player games search has inline `style="max-width:400px"`. On 375px with 16px body padding, available width is 343px. The input renders at 343px (constrained by parent), so the max-width doesn't cause overflow — but it's a code smell. The search input correctly fills the parent, but on tablet landscape (768px+) there's a jarring jump when the 400px limit kicks in.

**Fix:** Remove the inline max-width, let the search input be full-width on all sizes. Or set it via CSS class with responsive breakpoints.

---

### 14. Filter chip rows wrap inconsistently

**Location:** Multiple views
**Problem:** The `.filter-bar` uses `flex-wrap: wrap` with `gap: 6px` on mobile. This works for 3-4 chips, but on the Track view there are 5 chips (All, Open, Won, Lost, Pushed) each with count badges. On 375px, they wrap to 2 rows: first row gets 3 chips, second row gets 2 left-aligned. The uneven split looks unbalanced.

**Fix:** Use horizontal scroll (`overflow-x: auto; flex-wrap: nowrap`) for filter chips on mobile, with fade edges to hint at scrollability. This matches the iOS pattern for filter chips.

---

### 15. Toggle switch labels truncate on narrow screens

**Location:** `app.html` lines 1749-1803 (settings), 2864-2909 (player notifications)
**Problem:** Toggle rows are flex with label on left, switch on right. The `.toggle-label` text like "Require Approval Above Threshold" is long. The switch is `flex-shrink: 0; width: 44px`, so the label gets 375 - 32 (padding) - 40 (card padding) - 44 (switch) - 12 (gap) = 247px. The label fits, but the `.toggle-desc` below it at `font-size: 13px` wraps to 3+ lines, making the row very tall.

**Fix:** Reduce `.toggle-desc` to `font-size: 12px` and `line-height: 1.3` on mobile. Consider hiding description text entirely on very narrow screens and using a tooltip/info icon instead.

---

### 16. Credit utilization bar label overlap

**Location:** `app.html` lines 2072-2090 (player home), 1298-1333 (member detail)
**Problem:** The credit utilization section shows "Used: $X" on the left and "Available: $X" on the right in a flex row below the bar. On 375px with long dollar amounts ("$12,345.67"), both labels total ~250px+, fitting within 311px available — but barely. With amounts over $99,999, they overlap.

**Fix:** Stack labels vertically on mobile, or use abbreviated format ("$12.3K") for the utilization labels.

---

### 17. Attention tags wrap to multiple lines

**Location:** `app.html` lines 1285-1295 (member detail), 375-410 (dashboard member cards)
**Problem:** Attention tags ("Picks Pending", "On Heater", "Cold Streak", "Whale", "Parlay Demon") are inline badges. A member with 3+ tags wraps to 2 rows, which pushes subsequent content down and creates inconsistent card heights in the dashboard member grid.

**Fix:** Limit visible tags to 2 on mobile with a "+N more" overflow indicator. Show full list on tap.

---

### 18. Player track ticket cards — stake/profit row wraps

**Location:** `app.html` lines 2530-2579
**Problem:** Ticket cards show "Stake: $X" on the left and "Profit: +$X" (or "Potential: $X") on the right. For multi-picks with combined odds display, the line becomes "3-leg Multi-Pick · +450" on the left, which is ~200px at 13px font. On 375px, the right side wraps below.

**Fix:** Move odds to its own line between title and stake/profit row. Keep stake and profit on a single line.

---

### 19. Sidebar logout button positioning

**Location:** `dashboard.css` line 323
**Problem:** `.sidebar-bottom` is `position: absolute; bottom: 24px`. When the sidebar nav has many items (7 organizer links + divider), on shorter mobile screens (667px iPhone SE) the absolute-positioned logout overlaps the last nav items. The sidebar has `overflow-y: auto` but the bottom section doesn't scroll with it.

**Fix:** Change logout from absolute to sticky, or move it into the nav flow with a margin-top: auto in a flex column layout.

---

### 20. Pro-gated blur overlay touch issues

**Location:** `app.html` lines 261-293 (risk watchlist), 413-444 (sport performance)
**Problem:** Pro-gated sections show a blurred card with an absolute-positioned upgrade overlay. On mobile, the overlay button ("Upgrade to Pro") is tappable, but the blurred content behind it sometimes captures scroll events, making it hard to scroll past these sections.

**Fix:** Add `pointer-events: none` to the blurred content container, keep `pointer-events: auto` only on the upgrade overlay CTA.

---

## Low Issues (Nitpicks)

### 21. Monospace font (IBM Plex Mono) not loaded on mobile

**Problem:** Odds values use `font-family: 'IBM Plex Mono', monospace`. If the font isn't loaded (slow connection, font blocked), odds fall back to system monospace which has different metrics, causing slight alignment shifts in the odds grid.

**Fix:** Preload the mono font variant, or use tabular-nums on the system font as fallback.

### 22. Dashboard page has no pull-to-refresh

**Problem:** Native mobile apps have pull-to-refresh. The web dashboard requires tapping a Refresh button (on Track) or sidebar navigation to reload data. There's no tactile feedback for refreshing.

**Fix:** Consider adding pull-to-refresh behavior via touch events on mobile, or at minimum make the mobile header tappable to refresh current view.

### 23. Bet slip modal has no swipe-to-dismiss

**Problem:** The bet slip slides up from bottom (`.bs-modal` animation) but can only be closed by tapping the X button or the overlay. iOS users expect swipe-down to dismiss bottom sheets.

**Fix:** Add touch gesture handler for swipe-down dismiss on `.bs-modal`.

---

## Summary Matrix

| # | Issue | Severity | Views Affected | Effort |
|---|-------|----------|----------------|--------|
| 1 | Toast overflow | Critical | All | Small |
| 2 | Settlement data-labels | Critical | Settlement | Small |
| 3 | Odds grid team name truncation | Critical | Player Games | Medium |
| 4 | Picks table data-labels | Critical | Organizer Picks | Small |
| 5 | Member detail header overflow | High | Member Detail | Medium |
| 6 | Bet slip quick stakes layout | High | Bet Slip | Small |
| 7 | Settlement week selector cramped | High | Settlement | Small |
| 8 | Dashboard stat value overflow | High | Dashboard | Small |
| 9 | Event detail odds no mobile layout | High | Event Detail | Medium |
| 10 | Financials grid doesn't collapse | High | Pick/Ticket Detail | Small |
| 11 | No page title in mobile header | Medium | All | Small |
| 12 | Card padding inconsistency | Medium | All | Small |
| 13 | Search input max-width | Medium | Player Games | Trivial |
| 14 | Filter chips uneven wrap | Medium | Track, Settlement | Small |
| 15 | Toggle desc text too tall | Medium | Settings | Small |
| 16 | Credit bar label overlap | Medium | Home, Member Detail | Small |
| 17 | Attention tags multi-row | Medium | Dashboard, Member | Small |
| 18 | Track card stake/profit wrap | Medium | Player Track | Small |
| 19 | Sidebar logout overlap | Medium | Sidebar | Small |
| 20 | Pro-gated blur scroll conflict | Medium | Dashboard | Trivial |
| 21 | Mono font fallback | Low | Player Games | Trivial |
| 22 | No pull-to-refresh | Low | All | Large |
| 23 | No swipe-to-dismiss | Low | Bet Slip | Medium |
