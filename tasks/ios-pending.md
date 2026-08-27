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


### B5. Web moved to Inter; iOS stays on IBM Plex Sans

Decided 2026-08-25. The web product (dashboard, admin, login, marketing, design
system) now uses **Inter** as its body typeface. iOS uses **IBM Plex Sans**, set
globally via `.font(Theme.body)`.

This is a deliberate divergence, not an oversight — Inter is the more neutral
face and stays out of Space Grotesk's way, and Space Grotesk still sets display
type and large figures on both platforms, so the two still share their most
recognisable typographic element.

- [ ] Decide whether iOS follows web to Inter, or the split stands permanently
- [ ] If iOS follows: Inter must be bundled as an app resource (the web loads it
      from Google Fonts, which an app cannot do), and the PostScript names must
      be verified — the IBM Plex bundle already cost a debugging cycle over
      exactly this (`IBMPlexSans`, not `IBMPlexSans-Regular`; `IBMPlexSans-Medm`,
      not `-Medium`)
- [ ] `tokens.css` no longer mirrors `Theme.swift` for type. It still does for
      colour. Worth stating in the file so the next reader does not assume the
      mirror is total.

Note the web keeps **IBM Plex Mono** for odds and scores, which is unrelated to
this decision — Inter has no official monospace sibling, and the alternative
(the system stack) would render odds in SF Mono on macOS and Consolas on
Windows.


### B6. `--text-muted` lifted on web for contrast; iOS still on the old value

Web changed `--text-muted` from `#6B6B7B` to `#858595` on 2026-08-25. The
original failed WCAG AA on every surface it can sit on — 3.77 / 3.49 / 3.14
against background / card / elevated — across 144 uses. `#858595` clears 4.5:1
on all three (5.43 / 5.03 / 4.52).

`Theme.textMuted` is unchanged, so `tokens.css` and `Theme.swift` now disagree
on exactly one colour. `scripts/check-design-tokens.py` knows about it: the pair
is listed in `THEME_DIVERGENCE` with the reason, so the check still runs and
reports the divergence on every pass rather than being silenced.

- [ ] Change `Theme.textMuted` to `#858595` and remove the entry from
      `THEME_DIVERGENCE`
- [ ] Check the same text on iOS surfaces — iOS uses the same three background
      values, so the ratios carry over, but the app also renders muted text over
      the wave texture, which the web contrast check does not model

The other new tokens (`--fill-*-foreground`, `--focus-ring`, `--tap-target`) are
web-only additions with no `Theme.swift` counterpart, so they do not create
drift. The five fill foregrounds encode which text colour is legible on each
tinted badge fill; iOS builds those badges independently and would need the same
pairing to avoid the same two failures (`final` at 2.49, `scheduled` at 3.72).


### B7. Design-system pass — web-side changes with an iOS counterpart

The August design-system work (see `tasks/prd-design-system-adoption.md`) landed
on web only. B5 and B6 above cover the two that create token drift; these are the
rest, none of which changes `Theme.swift` values but each of which has an iOS
equivalent worth making.

- [ ] **Semantic badge naming.** Web replaced visual badge classes with 23
      semantic ones (`won`, `lost`, `push`, `void`, `pending`, `settled`,
      `scheduled`, `live`, `final`, `canceled`, plus the member/balance/ledger
      domains). The reason was not tidiness: the state-to-colour mapping lived in
      `dashboard.js` across three functions that had drifted apart. iOS almost
      certainly has the same shape — check where a pick's status becomes a colour
      and whether it happens in a view or in `Theme`.
      Adopting the model also fixed three collisions worth checking on iOS: a
      `final` game rendered the same green as a `won` pick, `scheduled` was
      indistinguishable from `settled`, and `void` was the same red as a loss.

- [ ] **Tabular figures and monospace for data.** Web sets `tabular-nums` on
      every numeric surface and monospace on odds and scores. On iOS this is
      `.monospacedDigit()` on the font. Without it a balance ticking 1,180 to
      1,220 visibly shifts, and a column of stakes never aligns.

- [ ] **Tracking scale.** Web tokenised letter-spacing into seven values after
      finding eight raw values across two unit systems. iOS uses `.tracking()`;
      worth checking whether display type there is tightened at all.

- [ ] **Motion.** Web's `--ease` was the literal keyword `ease` and referenced
      zero times, so every transition inherited a curve that ACCELERATES before
      settling — the opposite of the "critically damped, nothing bounces" rule in
      the design system. Now one curve, `cubic-bezier(0.22, 1, 0.36, 1)`. iOS
      should be audited for the same: any `.easeInOut` on an interaction is the
      same mistake in SwiftUI form.

- [ ] **Contrast.** Web now has seven `--fill-*-foreground` tokens pairing each
      tinted badge fill with the text colour legible on it. Two of the five had
      been failing WCAG AA (`final` at 2.49, `scheduled` at 3.72). iOS builds
      those badges independently and will have the same two failures.

Not applicable to iOS: the focus-ring work (keyboard focus is a web concern;
iOS has VoiceOver and focus engine equivalents that are separate), the dead
`@media (max-width: var(...))` queries, and the `.select` / `.progress` /
`.tooltip` components, which are UIKit/SwiftUI primitives there.


### B8. Attribution capture is web-only

Added 2026-08-26. The web now records first-touch attribution (`attribution.js`
→ `user_attribution`) and writes an `onboarding_responses` row even when the
questionnaire is skipped. iOS does neither.

This matters more than most web/iOS gaps because attribution cannot be
backfilled — a user who signs up on iOS today has no source, permanently, and no
later change recovers it.

- [ ] Capture install/first-open attribution on iOS. Note this is NOT the same
      mechanism: there are no UTM parameters on an App Store install. The
      equivalents are Apple Search Ads attribution, a deep link carrying the
      campaign, or asking in-app. Do not try to port `attribution.js`.
- [ ] Show the onboarding questionnaire on iOS at all. There is currently no
      onboarding flow in the Swift target, so iOS signups produce neither a
      measured source nor a self-reported one.
- [ ] Write an `onboarding_responses` row on skip as well as submit, matching
      web, so a skip is distinguishable from never being asked.

Until then, read the admin Attribution view knowing the denominator is
web signups only.

## B9 — Move invite validation onto `get_invite()`, then drop the `USING (true)` policy

**Blocking a security fix.** Migration 010 created:

```sql
CREATE POLICY invites_select_by_code ON invites FOR SELECT USING (true);
```

commented "safe because invite codes are randomly generated 8-char strings".
That reasoning does not hold. RLS is row-level and cannot inspect the WHERE
clause, so the policy never requires the caller to supply a code — anyone with
the anon key who omits the `invite_code` filter reads the whole table: every
open code, every `bookie_id`, every invitee email address. Knowing a code was
assumed, never enforced.

Migration 052 adds `get_invite(p_code)` — SECURITY DEFINER, throttled, takes the
code as an *argument* (which is enforceable), returns one row of display fields
and never `bookie_id` or the invitee email. The web invite page now uses it, and
web no longer needs any anon SELECT on `invites`.

**The policy could not be dropped in 052.** `Booki/Views/InviteClaimView.swift:951`
still queries the table directly with the anon key before login:

```swift
.from("invites")
.select("id, invite_code, expires_at, claimed_at, bookie_id, bookies(name)")
.eq("invite_code", value: normalized)
```

Dropping the policy today breaks invite claiming for every shipped build.

**Work**
1. Replace that query with an RPC call to `get_invite`, mapping `status` to the
   existing error states — note `expired` must not be reported for an addressed
   invite, which is why the function already returns NULL expiry for those.
2. Ship the build.
3. Then, and only then, `DROP POLICY invites_select_by_code ON invites;` and
   confirm anon reads of `invites` fail.

Step 3 is the actual fix. Steps 1–2 exist to make it safe to take.
