# Spike: team and school logos

Run 2026-09-06. Question: do we have access to logos for the teams we display?

## Short answer

Not from anything we already pay for. Neither The Odds API nor balldontlie
carries a logo field — checked the NFL, NBA and MLB `teams` payloads directly,
and the fields are `id, abbreviation, full_name/display_name, location, name,
conference/division/league, slug`. No logo, image or icon anywhere.

ESPN's public CDN does, and our team names match it well enough to use.

## What we would be matching

Distinct opponents currently on the board, real teams only:

| league | teams | note |
|---|---:|---|
| NCAAF | 191 | the scale problem |
| NFL | 32 | |
| NHL | 32 | |
| MLB | 30 | |
| NBA | 27 | |
| UFC / ATP / WTA | ~330 | **individuals** — headshots, not logos. Out of scope. |

## Sources tested

`https://a.espncdn.com/i/teamlogos/{sport}/500/{abbr}.png` — 200, `image/png`,
30–56KB, verified for `nfl/kc`, `nfl/dal`, `mlb/chc`, `mlb/oak`, `nba/bos`,
`nhl/bos`.

`https://a.espncdn.com/i/teamlogos/ncaa/500/{espn_team_id}.png` — 200 for
college, keyed by ESPN id rather than abbreviation.

`https://site.api.espn.com/apis/site/v2/sports/{path}/teams?limit=1000` returns
every team with `id`, `displayName`, `abbreviation`, `slug`, a `logos[]` array,
**and team colours** (`color`, `alternateColor`). College football returns 760
teams. That endpoint is undocumented and unofficial — see risks.

## Coverage, measured

Matching our stored `home_team`/`away_team` strings against ESPN's
`displayName` / `shortDisplayName` / `name` / `location`, case- and
punctuation-insensitive, with accents stripped:

| league | ours | matched | coverage |
|---|---:|---:|---:|
| NFL | 32 | 32 | **100%** |
| NBA | 27 | 27 | **100%** |
| MLB | 30 | 30 | **100%** |
| NHL | 32 | 32 | **100%** |
| NCAAF | 191 | 179 | 93.7% |

Accent stripping is load-bearing: without it `Montréal Canadiens` fails and NHL
drops to 96.9%.

The 12 college gaps are naming variants, not missing teams — ESPN says
`App State Mountaineers`, `The Citadel Bulldogs`, `Nicholls Colonels`,
`Sam Houston Bearkats`, `SE Louisiana Lions`, `Southern Miss Golden Eagles`,
`Massachusetts Minutemen`, `Youngstown State Penguins`, and
`Houston Christian Huskies` (the school was renamed from Houston Baptist).

## The trap: do not fuzzy match

Fuzzy matching resolves 9 of those 12 correctly and then produces two
confidently wrong answers:

    LIU Sharks                    -> Fort Lewis Skyhawks     (0.55)
    UT Rio Grande Valley Vaqueros -> Grand Valley State Lakers (0.63)

Both would put another school's logo on a game, which is worse than no logo at
all and would look deliberate. `Albany` matched nothing. Two of the three are
basketball schools that are simply absent from the college FOOTBALL list —
UT Rio Grande Valley is in ESPN's men's college basketball list (id 292).

So: exact match plus a small explicit alias table, never a similarity score.
Same rule the prop subject resolution follows — an ambiguous match is a skip,
not a guess.

## What building it would take

1. A `team_logos` mapping keyed the way `bdl_teams` already is: our
   `odds_api_name` -> ESPN id/abbreviation. ~120 rows to cover everything on
   the board today, seeded from the ESPN teams endpoints.
2. A dozen alias rows for the college naming variants.
3. A neutral fallback for an unmatched team. It must be visibly generic, so a
   missing logo never reads as the wrong team.

Colours come free from the same payload and are arguably more useful than the
logos for a dark UI — they would let a game row carry team identity without
loading 30–50KB of PNG per side.

## Risks worth deciding before building

**Licensing.** Team logos are trademarks. Hotlinking ESPN's CDN is not a
licence to use them, and it is a third party we have no agreement with. This is
a product/legal call, not a technical one. The colours carry none of that risk.

**Unofficial API.** `site.api.espn.com` is undocumented and can change or be
blocked without notice. Seeding a mapping table once is safe; fetching from it
at request time is not.

**Weight.** 30–56KB per logo. A board with 60 NCAAF games would pull ~7MB of
PNG unless sized down, cached, or replaced with colour treatments.
