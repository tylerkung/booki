# PRD — QA fixes, August 2026

**Source:** QA pass by Quincy, 2026-08-27, against production.
**Status:** proposed. Every claim below was re-verified against the code or the
live site before being accepted; five did not reproduce and are not scheduled.

## Summary

12 items were reported. Verification found:

| | count | |
|---|---|---|
| Confirmed, scheduled | 6 | root cause identified for all but two |
| Needs a product decision first | 1 | the reported "bug" is the documented convention |
| Did not reproduce | 5 | do not spend time on these without new evidence |

Two of the confirmed bugs are one-line fixes with exact line numbers. One is a
genuine feature build disguised as a bug.

---

## P0 — Ship first

### 1. The invite landing page is decorative (QA P0-1, P0-7, P0-8, P1-10, P1-11)

**Confirmed, and it is worse than "no server lookup".** `landing/invite.html`
contains **zero** Supabase or `fetch` references. It reads the last path segment
and validates only its *shape*:

```js
var code = /^[A-Z0-9]{6,12}$/.test(candidate) ? candidate : '';
```

Consequences, all reproduced:

- `/invite` → the last segment is the word `invite`, which is 6 alphanumeric
  characters, so it passes the regex and the page renders **INVITE** as a
  copyable invite code.
- `/invite/NOTACODE` → 8 alphanumeric characters, passes, looks completely valid.
- `/invite/9QB68F7N` → shows the right string but no group name, no organizer, no
  credit limit, and a hardcoded "expires in 7 days" rather than the real date.
- GET STARTED is `href="/dashboard/"`. The code is not carried anywhere, so
  nothing redeems it.
- The "Invite link incomplete" state exists in the markup and is unreachable,
  because every path that should trigger it passes the shape check.

*Note: this is a regression I introduced.* The page was rewritten on 2026-08-25
to fix its styling, and the guard added then only defended against
`/invite.html` — the dot fails the regex. The literal word `invite` does not.

**Work**
- Look the code up server-side. `claim_invite` already exists; this needs a read
  path — either a new `get_invite(code)` edge function or an anon-readable view
  exposing group name, organizer name, credit limit and `expires_at` for a valid
  unclaimed code, and nothing for anything else.
- Three real states: missing code → incomplete; unknown/expired/claimed → error;
  valid → group context and the true expiry.
- GET STARTED carries the code into signup (`/dashboard/login?invite=CODE`) and
  the signup flow redeems it on success.
- **Do not leak existence.** An unknown code and an expired code should be
  distinguishable to a legitimate user but must not turn the page into an oracle
  for enumerating valid codes. Rate-limit the lookup.

**Done when** `/invite` and `/invite/NOTACODE` show the error state, a valid code
shows real group context and expiry, and GET STARTED attaches the member.

---

### 2. Invite TTL copy contradicts the server (QA P0-4)

**Confirmed, exact cause.** `supabase/functions/create_invite/index.ts:22`:

```ts
const INVITE_EXPIRY_HOURS = 24 * 7;   // 168 hours = 7 days — the truth
```

Against it:

| surface | says | correct? |
|---|---|---|
| `create_invite` (server) | 168h / 7 days | ✅ source of truth |
| Create-link modal, `index.html:4211` | "expires in 24 hours" | ❌ |
| Create-link confirm, `index.html:4250` | "expires in 24 hours" | ❌ |
| Pending-invites table | Sep 3 (7 days) | ✅ |
| `invite.html:211` | "expires in 7 days" | ✅ but hardcoded |

The "167 hours" the tester saw after creating is 168 minus elapsed time, so the
computed display is right and only the two static strings are wrong.

**Work** Fix the two strings. Then make the public page render the real
`expires_at` rather than a hardcoded phrase — folds into item 1.

---

### 3. Sport win rate is inverted (QA P0-6)

**Confirmed, one line.** `landing/dashboard/index.html:487`:

```js
Math.round(sp.losses / (sp.wins + sp.losses) * 100) + '%'
```

It divides **losses** by the total and labels the column "Win Rate". With 4 wins
and 2 losses that yields 2/6 = 33%, exactly what was reported against the
member's true 67%.

The counters themselves are correct — `grade_result === 'win'` increments `wins`,
`'loss'` increments `losses`. Only the ratio is backwards.

**Work** Change `sp.losses` to `sp.wins`. Then check the other win-rate readouts
(`playerWinRate`, `memberWinRate`) for the same inversion, since a copy-paste is
the likely origin.

---

## Needs a decision before it is scheduled

### 4. Dashboard activity signs (QA P0-5)

The two surfaces genuinely differ:

- Organizer dashboard, `index.html:560` — `formatCurrency(entry.amount)` (raw)
- Member page, `index.html:3287` — `formatCurrency(-entry.amount)` (negated)

**But that is the documented convention, not a defect.** CLAUDE.md states:
*"Internal: positive = player owes bookie… Player-facing display: negate…
**Bookie-facing views use internal convention directly (no negation)**."*

From the organizer's ledger, a member winning **is** money leaving. `-$9.52`
against "Bet won" is arithmetically correct for the organizer.

The real defect is that the **label describes the member's outcome while the
amount describes the organizer's ledger**. "Bet won −$9.52" reads as a
contradiction because two different subjects share one row.

Two fixes, and this is a product call:

- **A — negate on the dashboard** (what QA asked for). Wins read positive
  everywhere. Cost: the activity feed then disagrees with the organizer's own
  balance and P&L, which are computed in the internal convention.
- **B — keep the sign, fix the label.** "Member won — you paid $9.52". Ledger
  stays coherent; the row stops contradicting itself.

**Recommendation: B.** A makes two numbers on the same screen mean opposite
things. But it is more copy work, and QA explicitly asked for A, so the call
should be made deliberately rather than by whoever picks up the ticket.

---

## P2 / P3 — Confirmed, low risk

### 6. Picks empty state lies (QA P3-6)

Confirmed, `index.html:1142`: "No picks yet. Members will appear here once they
start placing picks." — shown on the **Open** filter while six graded picks
exist. Should read "No open picks". The current copy tells an organizer with a
full history that they have nothing.

### 7. Events flashes "0 events" (QA P3-7)

Plausible, not yet reproduced. There **is** a guard —
`isLoadingPlayerEvents ? 'Loading games…' : filteredPlayerEvents.length + …` —
so the flash means the flag clears before the list populates. Same shape as the
`loadPlayerTrack` race fixed on 2026-08-27: a loader that reports "done" while
its data is still arriving. Reproduce first, then gate the count on the data
rather than the flag.

### 8. Signup error UX (QA P2-1, P2-2, P2-5)

Not verified — needs a manual walkthrough with a real inbox. Reported: raw
"Error sending confirmation email" with no recovery, no client-side email format
validation, and a verification screen with no resend or change-email. All three
are plausible and worth fixing regardless; treat the specific wording as
unconfirmed until walked.

---

## Did not reproduce — do not schedule

Checked against production on 2026-08-27. Each of these needs new evidence
before it is worth anyone's time.

| QA ID | Claim | What was found |
|---|---|---|
| P1-6 | `/sitemap.xml` returns 500 | Returns **200**, and the local file parses as valid XML. The sitemap was edited and redeployed on 26–27 Aug; the tester most likely hit a deploy window. |
| P1-5 | Blog card 404 | The card's actual href is `how-to-be-a-bookie-for-friends.html`, the file exists, and both `/blog/how-to-be-a-bookie-for-friends` and the `.html` form return **200**. The brief says the tester *guessed* slugs — the guess 404'd, the real link does not. |
| P3-2 | Marketing nav breaks from `/features` | `/features` returns 200 with **no** redirect to `/features/`, so relative `help/` resolves against `/` and gives `/help/`. `/features/` itself 301s. The described `/features/help/` is not reachable. *Making the hrefs root-relative is still cheap hygiene, but it is not fixing a live break.* |
| P3-4 | `support@bookisports.com— the gaps` missing a space | Source and live both render `support@bookisports.com</a> —` **with** a space. |
| P1-4 | `/help/where-the-odds-come-from` and `/help/odds` 404 | Both do 404, but neither is linked from anywhere. The real link is `<a href='/help/how-odds-work'>More on where the odds come from</a>`, and `/help/how-odds-work` returns **200**. The guessed slugs came from the link TEXT. |

**A pattern worth feeding back.** Three of the five non-reproducing items (P1-4,
P1-5, and P3-2 in effect) come from constructing a URL rather than following the
link — guessing a slug from the anchor text, or assuming a trailing slash. Two
of the three "404s" are pages that work. Following the actual `href` would have
caught all three before they were filed.

---

## Shipped 2026-08-27

- **Item 1 (invite lookup)** — migration 052 `get_invite(p_code)` plus a rewritten
  `landing/invite.html` and the signup handoff. Verified on production:
  `/invite/9QB68F7N` shows "Organizer invited you", a $1,000 credit limit and the
  real 3 September expiry; `/invite/NOTACODE` shows the error state; `/invite`
  shows the incomplete state and renders no code. The CTA carries the code to
  `login.html`, which stores it and strips it from the URL. Throttle confirmed
  live: the 21st lookup in a minute returns `rate_limited`, and the window clears.
  **The migration 010 `USING (true)` policy is still in place** — see B9 in
  `tasks/ios-pending.md`. Dropping it is the remaining half of this fix.

- **Item 3 (win rate)** — `sp.losses` → `sp.wins`. Verified the other two
  readouts (`playerWinRate`, `memberWinRate`) already compute `wins / total`, so
  the inversion was isolated rather than a copy-paste family.
- **Item 2 (TTL copy)** — both "expires in 24 hours" strings → "7 days",
  matching `INVITE_EXPIRY_HOURS`.
- **Item 6 (empty state)** — now names the active filter: "No open picks…" vs
  "No settled picks yet…". Expression verified to evaluate correctly for both
  filter values.

## Suggested order

1. ~~Item 3, 2, 6~~ — shipped, see above.
2. ~~Item 1~~ — shipped. Follow-up: drop the 010 policy once iOS moves to
   `get_invite` (B9).
3. **Item 4** — get the product decision, then implement.
4. **Items 7, 8** — reproduce first, then fix.

## Out of scope

Everything in the brief's own out-of-scope table stands, plus the five
non-reproducing items above.
