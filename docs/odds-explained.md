# How Booki Handles Odds

A plain-language reference: where the numbers come from, how long we keep them,
and why a game sometimes shows no price at all.

> Also published as a shareable page:
> https://claude.ai/code/artifact/8afa6c78-edac-4694-bfe5-e3aa6e3f2e5d
>
> Technical detail and the reasoning behind these rules lives in
> `docs/games-sync-redesign.md`.

## The short version

Booki doesn't set its own lines. We buy odds from a data provider called **The
Odds API**, which aggregates prices from real sportsbooks. Our job is to fetch
those numbers regularly, keep the ones that matter, and throw away the ones
that don't. Everything runs on timers — nobody presses a button, and no
organizer sets a price by hand.

| | |
|---|---|
| **Members see odds** | 48 hours before a game |
| **We store odds** | 7 days before a game |
| **After the game** | Odds deleted; result kept |

## The life of a game

| Stage | What happens |
|---|---|
| **Weeks out** | The game is listed but has no price. Prices that far out move constantly and almost nobody bets them, so storing them would mean holding and re-downloading thousands of unused numbers. |
| **7 days** | The game enters the storage window. We start saving its prices and refreshing them on every sync. Stored before it's shown, on purpose — so a game already has a price the moment it becomes visible. |
| **48 hours** | The game becomes visible and bettable to members. |
| **Kickoff** | The line locks. No new picks. Existing picks keep the exact price they were taken at. |
| **Final** | Open picks are graded, then the odds are deleted. The game and its final score are kept forever. |

## Why deleting old odds is safe

**Every pick stores its own price at the moment it's placed.** When a member
takes the Yankees at −140, that number is copied onto their pick and never
changes, even if the line moves to −165 an hour later.

That's why a finished game's odds can be deleted without harming anything.
Grading uses the final score and the price already saved on the pick — it never
looks up the old market. A settled pick from three months ago displays
identically whether those odds still exist or not.

## Futures work differently

A futures bet ("who wins the NBA Championship") has no meaningful start time and
sits open for a whole season. The normal rules would delete every futures market
immediately, since by any start-time measure they look long overdue.

So futures are **exempt from both the storage window and the deletion rule**.
They're kept while live, refreshed daily rather than hourly (their prices drift
slowly), and graded by hand — nothing can automatically decide a championship is
over.

## What runs, and how often

| Job | Runs | What it does |
|---|---|---|
| Game sync | 2× daily | Finds newly scheduled games, refreshes prices inside the window, marks finished games final and deletes their odds. |
| Odds refresh | Every 30 min | Re-prices games, at a rate that depends on how close they are (below). Also grades and settles picks as results land. |
| Live scores | Every 5 min | Watches games that should be ending. Only calls the provider when a game is genuinely near its finish, so most runs cost nothing. |

### How often a price is refreshed

Not every game is re-priced at the same rate. Odds cost money to fetch — we pay
per request — so effort goes where lines actually move.

| Game | Refreshed |
|---|---|
| Starting within 4 hours, in the NFL, NBA or MLB | Every 30 minutes |
| Starting within 4 hours, any other league | Hourly |
| Starting in 4–48 hours | Every 2 hours |
| Futures (championship winners) | Once a day |

So a line can lag the market by up to half an hour on a big game about to start,
and by a couple of hours on one that's still a day or two out.

## How we know two games are the same game

The Marlins play the Mets seven times a season. Those are seven separate games,
not one game listed seven times — but the teams, league, and often the start
hour look identical.

So we never identify a game by its teams. The provider assigns every game a
unique ID, and that ID is the only thing we match on. A rematch gets its own ID
and is treated as genuinely new. If the provider shifts a fight's start time by
twenty minutes, the ID is unchanged and we update the existing game rather than
creating a second copy.

## If something looks wrong

**A game shows dashes instead of odds.** Usually it's more than 48 hours away
and working as intended. A game starting *today* with no price is a real fault —
it means the sync didn't store its market.

**A finished game shows no odds.** Expected. Picks on it still show the price
they were taken at.

**An old game has no final score.** The provider only serves scores for the last
three days, so older games can never be backfilled. It doesn't affect grading —
picks are graded when the game ends, not later.

**Odds look stale.** Prices refresh hourly for games starting soon and twice
daily for everything else, so a line can lag the market by up to an hour. That's
a deliberate cost decision — every refresh spends provider quota.
