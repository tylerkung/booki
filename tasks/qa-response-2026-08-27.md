# Re: Booki QA brief, 2026-08-27

Thanks Quincy — this was a useful pass. Twelve items, and I re-verified every
one against the code or production before scheduling it. Three are already
fixed and pushed. One is a real build and is in progress. Five did not
reproduce, and one is working as designed. Detail below, including what I'd
ask you to change in how a couple of these were checked.

## Fixed and deployed

**Win rate inverted (P0-6).** Confirmed, and your diagnosis was exactly right.
`index.html:487` divided `sp.losses` by the total and labelled the column Win
Rate, so 4-2 rendered as 33%. Now `sp.wins`. I also checked the other two
win-rate readouts on the assumption this was a copy-paste family — both were
already correct, so it was isolated to the sport breakdown.

**Invite TTL copy (P0-4).** Confirmed. The server is the truth:
`create_invite` sets `INVITE_EXPIRY_HOURS = 24 * 7`. The "167 hours" you saw
after creating was correct — that's 168 minus elapsed. Only the two static
"expires in 24 hours" strings in the create-link modal were wrong. Both now
say 7 days.

**Picks empty state (P3-6).** Confirmed. It now names the active filter: "No
open picks…" on Open, "No settled picks yet…" on Settled.

## In progress

**Invite landing page (P0-1, P0-7, P0-8, P1-10, P1-11).** Confirmed, and it's
worse than "no server lookup" — the page contains zero Supabase or fetch
calls. It reads the last path segment and validates only its *shape*:

    /^[A-Z0-9]{6,12}$/

That's why `/invite` renders **INVITE** as a copyable code: the literal word
"invite" is six alphanumeric characters and passes. Same for NOTACODE. The
"Invite link incomplete" state in the markup is unreachable for exactly this
reason — everything that should trigger it passes the shape check.

For the record, this is a regression I introduced. The page was rewritten on
25 Aug to fix a styling problem, and the guard I added then only defended
against the literal `/invite.html` — the dot fails the regex, the bare word
doesn't. Your five findings here are all one root cause and you were right to
file them.

Building now: a server lookup that returns group name, organizer, credit limit
and the real `expires_at` for a valid unclaimed code and nothing for anything
else, three genuine states, and GET STARTED carrying the code into signup so
it actually redeems. Rate-limited, so the page can't be used to enumerate
valid codes.

## Not a bug — working as designed

**Dashboard activity signs (P0-5).** You're right that the two surfaces differ,
and right about which line does it: the organizer dashboard renders
`formatCurrency(entry.amount)` raw while the member page renders
`formatCurrency(-entry.amount)`. But that difference is deliberate and
documented. Our balance convention is: internally, positive means the member
owes the organizer; member-facing views negate it; **organizer-facing views use
the internal convention directly**.

So from the organizer's ledger, a member winning genuinely *is* money leaving.
`-$9.52` against a won pick is arithmetically correct for the organizer, and
negating it would put the activity feed in disagreement with the organizer's
own balance and P&L on the same screen.

What *is* wrong is the label, not the sign. "Bet won −$9.52" reads as a
contradiction because the label describes the member's outcome while the amount
describes the organizer's ledger — two subjects in one row. The fix is to make
the row say whose outcome it is ("Member won — you paid $9.52"), not to flip
the number. That's a copy change and a product call, so it's queued rather than
silently done one way or the other.

## Did not reproduce

Checked against production on 27 Aug. Please don't spend more time on these
without new evidence.

| ID | Claim | Found |
|---|---|---|
| P1-6 | `/sitemap.xml` returns 500 | Returns **200**, and the file parses as valid XML. The sitemap was edited and redeployed on 26–27 Aug — most likely you hit a deploy window. If you see it again, grab the timestamp. |
| P1-5 | Blog card 404 | The card's href is `how-to-be-a-bookie-for-friends.html`. The file exists and both the pretty URL and the `.html` form return **200**. |
| P1-4 | Help odds link 404 | `/help/where-the-odds-come-from` and `/help/odds` do 404, but nothing links to either. The actual link is `<a href='/help/how-odds-work'>More on where the odds come from</a>`, and `/help/how-odds-work` returns **200**. |
| P3-2 | Marketing nav breaks from `/features` | `/features` returns 200 with **no** redirect to `/features/`, so relative `help/` resolves against `/`. `/features/help/` isn't reachable. (Making the hrefs root-relative is still cheap hygiene — just not a live break.) |
| P3-4 | `support@bookisports.com—` missing a space | Source and live both render `support@bookisports.com</a> —` with the space. |

## One process note

Three of those five come from the same thing: constructing a URL instead of
following the link. P1-4's slugs were derived from the anchor *text* ("more on
where the odds come from"), P1-5's from the article title, and P3-2 assumed a
trailing-slash redirect that doesn't happen. Two of the three reported 404s are
pages that work fine.

Copying the actual `href` out of the DOM rather than guessing the slug would
have caught all three before filing — and would have saved the real P0 from
sitting in a list next to three phantom 404s. Everything else in the brief was
accurate and specific enough to fix directly, which is why three of them were
one-line changes.

## Still open, need your help

- **Events flashes "0 events" (P3-7).** Plausible and I want it, but I can't
  reproduce it yet. There *is* a loading guard, so if it flashes, the flag is
  clearing before the data lands — same shape as a race I fixed elsewhere on
  27 Aug. Can you get me the network conditions (throttled? cold load? which
  sport tab?) and roughly how long the 0 is visible?
- **Signup error UX (P2-1, P2-2, P2-5).** All three are believable and worth
  fixing regardless, but they need a real inbox to walk properly. Treating the
  exact wording as unconfirmed until then.
