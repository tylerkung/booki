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

---

## Notes for whoever picks this up

- Delete the app from the simulator if SwiftData schema changed (it has not, in any of the above)
- `swiftc -parse <file>` is a cheap syntax check but proves very little
- The stress suite (`tests/`) is Node and cannot run on the current machine — Node is not installed
