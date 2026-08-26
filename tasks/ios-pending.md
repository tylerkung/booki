# iOS — Pending Work

Running list of iOS changes that are shipped-but-unverified, or not yet written.
This project cannot be built from the CLI (`CLAUDE.md`: "Xcode command line
tools don't support full builds — use Xcode IDE"), so everything here needs a
real build and a run in the simulator.

Last updated: 2026-08-19

---

## A. Shipped but only parse-checked

These are committed and on `main`. `swiftc -parse` passes, which catches syntax
errors and nothing else — no type checking against the rest of the target, no
runtime behaviour. **Build before trusting.**

### A1. 48-hour member display window — commit `3606b71`

Members now see games starting within 48 hours instead of 14 days.

- `Booki/Models/Event.swift` — added `displayWindow` (48h), `displayHorizon`,
  `isOutrightEvent`, `isWithinDisplayWindow(now:)`
- `Booki/Views/GamesView.swift` — uses `isWithinDisplayWindow`; the old
  duplicated 14-day `upcomingHorizon` was removed
- `Booki/Views/SearchView.swift` — same
- `Booki/Views/SportPageView.swift` — added the window to the player branch only

**Verify:**
- [ ] Builds
- [ ] Player Games shows only games inside ~48h
- [ ] **Futures still appear.** `isOutrightEvent` keys off `awayTeam == "Outright"`,
      the sentinel the sync writes. If that string ever changes, every future
      silently disappears — this is the highest-risk item on the page
- [ ] Search respects the same window
- [ ] Sport pages respect it for members but not for organizers

### A2. Organizer events horizon 14d → 6d — commit `6788a6c`

- `Booki/Models/Event.swift` — added `organizerWindow` (6 days), `organizerHorizon`
- `Booki/Views/EventsListView.swift` — uses it instead of a hardcoded 14 days

Deliberately 6 days, inside the server's 7-day odds storage window: sync runs
twice daily, so a game that just crossed into storage can have no price for up
to 12 hours. Six days guarantees two syncs have covered anything shown.

**Verify:**
- [ ] Builds
- [ ] Organizer Events tab shows ~6 days and every game has odds
- [ ] Recent finals (last 48h) still appear — that path is separate and should be untouched

---

## B. Not yet written

### B1. Line change confirmation in the bet slip — **highest value**

Server and web are done (`90ecc72`). All three submit endpoints now return:

```json
{ "error": "line_changed",
  "market_id": "…", "submitted_odds": -110,
  "current_odds": -150, "current_side": "Team -3.5" }
```

For `submit_bets` (batch) these arrive in the `failed` array; for `submit_bet`
and `submit_parlay` it is the top-level response with HTTP 409.

**iOS currently shows a generic error for this.** The pick fails and the member
is told nothing useful.

What to build, mirroring `dashboard.js` (`applyLineChangesToSlip`,
`confirmLineChanges`):
- [ ] Detect `line_changed` — batch: scan `failed`; single/parlay: check the top-level error
- [ ] Update the slip in place with `current_odds` / `current_side`, keeping the old price for display
- [ ] Show old → new and ask to confirm, keeping the pick in the slip
- [ ] Confirm = ordinary resubmission with a **fresh idempotency key**, so it runs the same validation again. There is no honoured-price window by design
- [ ] Cancel leaves the pick unplaced
- [ ] **Check the batch ordering trap the web version had**: when every bet in a
      batch hits a moved line the server returns `All bets failed validation`
      with the details in `failed`. Handling the generic error first shows a
      dead-end message instead of the prompt

### B2. Knowledge base entry point

`tasks/prd-knowledge-base.md` US-005. The KB is live at
`https://bookisports.com/help/`.

- [ ] One "Help" row in organizer Settings, matching the existing navigable-row pattern
- [ ] Opens the web KB rather than duplicating copy in-app
- [ ] Contextual links later: limits editor → credit-and-win-limits, Settle Up → settling-up

### B3. `superseded line` rejection copy

Submit endpoints can now return `error: 'line_no_longer_offered'` when a member
bets a line the book has moved off (market rows are keyed by line value, so an
old line lingers as its own row).

- [ ] Show something better than a raw error string — e.g. "That line is no
      longer offered" with the pick removed or re-pointed to the current line

**Priority dropped after migration 048.** This was written while the guard was
comparing every market against `events.last_odds_update`, which in production
refused all 705 outright markets — so on iOS *every futures bet* failed with
this error and the copy mattered a great deal. 048 fixed the guard itself
(server-side, so iOS picked it up with no client change) and the rejection is
now rare and usually correct. Still worth doing, no longer urgent.

### B4. Corner radius — iOS has diverged from web

Web tightened its radius on 2026-08-19 (`d54e512`, `f3263d9`):
`--radius` 16 → **12**, `--radius-sm` 12 → **8**. iOS was deliberately left
alone, so the two platforms now disagree.

`Booki/Theme.swift`:

```swift
static let cornerRadius: CGFloat = 16        // web is now 12
static let cornerRadiusSmall: CGFloat = 12   // web is now 8
```

- [ ] Decide whether iOS follows. If it does, the two constants are the only
      edit — 13 call sites read them and need no change
- [ ] **Fold in the two bare literals.** `Theme.swift:474` and `:478` use
      `RoundedRectangle(cornerRadius: 8)` directly rather than a constant. They
      are already inconsistent; if `cornerRadiusSmall` becomes 8 they would
      silently become "correct" by coincidence, which is worse than being
      wrong. Point them at the constant either way
- [ ] Adopt the nesting rule while there. Radius is chosen by **depth, not
      element type**: the outermost rounded view takes `cornerRadius`, anything
      rounded inside it steps down to `cornerRadiusSmall`. No exemption for
      controls — a top-level button or field takes the full radius exactly like
      a card. Documented under Surfaces & Elevation in the design system
- [ ] Auditing this on iOS has no equivalent of the DOM walk used on web (830
      views checked automatically). Expect to do it by reading the view tree

Not urgent: the platforms looking slightly different is cosmetic, and this
needs an Xcode build plus a release either way.

---

## Notes for whoever picks this up

- Delete the app from the simulator if SwiftData schema changed (it has not, in any of the above)
- `swiftc -parse <file>` is a cheap syntax check but proves very little
- The stress suite (`tests/`) is Node and cannot run on the current machine — Node is not installed

## MarketType.oddEven — NOW BLOCKING A SHIPPED FEATURE

The web/backend now sync an `odd_even` market for NFL and NBA (combined final
score odd or even). `MarketType` has no case for it, so `SyncService`'s
`MarketType(rawValue:) ?? .moneyline` coerces it and iOS labels the market
"Moneyline" with sides Odd / Even.

**Updated 2026-08-26:** `odd_even` has been REMOVED from `sync_games`'
`DEEP_MARKETS` because of this. Without the iOS case, members on the current
build would have seen a "Moneyline" market with sides Odd and Even from the
moment NFL games entered the 3-day window on 7 September. Adding the case is
now what unblocks re-enabling that market.

**This is cosmetic, not a mis-grade.** The submit functions read `market.type`
from the database row rather than from the client, so the bet is stored as
`odd_even` and graded by `gradeOddEvenBet` regardless of what the app calls it.
Existing App Store builds are therefore safe.

Adding the case is small but touches eight exhaustive `switch` statements over
`MarketType` — Market.swift, BetConfirmationSheet, SearchView, GameDetailView,
GamesView, SportPageView, EventDetailView, AddMarketSheet — and none of them can
be compiled from the CLI, so it was deliberately left for a session with Xcode
rather than shipped unverified.

Also worth doing in the same pass: `GameDetailView` already renders alternate
spread and total sections, but nothing renders team totals or odd/even.

---

## Running list: web changes that need an iOS counterpart

Kept as web work happens rather than discovered later, because iOS fails
QUIETLY when the web moves ahead: `SyncService` decodes market types with
`MarketType(rawValue:) ?? .moneyline`, so any type Swift lacks a case for is
silently RELABELLED as a moneyline on shipped builds rather than ignored.

| Web change | iOS counterpart | Status on web |
|---|---|---|
| `alternate_spread`, `alternate_total`, `team_total` | cases already exist; `GameDetailView` renders alt lines but not team totals | **shipped** |
| `odd_even` market | `MarketType.oddEven` + display | **live**, hidden from iOS by migration 045 |
| `player_prop` market | `MarketType.playerProp`, plus a props UI grouped by player | **unblocked**, hidden from iOS by migration 045 |
| `SyncService` markets query has no type filter | give `MarketType` an `unknown` case and SKIP unknown types | worked around server-side; the client fix is what lets an entry be removed from `legacy_client_hidden_market_types()` |
| Game detail view (`#/player-game/:id`) | iOS `GameDetailView` already exists; needs team totals + props sections | shipped on web |
| Props UI grouped by player | iOS needs the same grouping; the ladder layout does not fit a prop | shipped on web |
| `get_event_player_props()` RPC | iOS must call this RPC for props — a plain `markets` select will never return them once `MarketType` supports the type | shipped on web |

**The structural fix worth doing first:** give `MarketType` an `unknown` case and
have the sync SKIP unknown types instead of coercing them. Three separate
incidents in one session traced to this single behaviour. With that in place,
the web can add market types freely and old builds ignore them rather than
mislabelling them — which removes the dependency that is currently holding two
finished features.
