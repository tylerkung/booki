/**
 * SPIKE — 2026-08-25. Kept because it is the evidence behind the decision in
 * tasks/prd-market-coverage.md US-003, not because it ships.
 *
 * Question: if we bought balldontlie's NFL tier, could we grade the player
 * props The Odds API sells?
 *
 * Answered by running this against a REAL completed NBA game (balldontlie game
 * 15907438, Knicks at Celtics, 2024-10-22) with a real 32-player box score,
 * because the NBA tier was already available and the pipeline is identical in
 * shape. Every check passes.
 *
 * Run: deno run --allow-read docs/spikes/prop-grading-spike.ts <stats.json>
 * where stats.json is a balldontlie /stats response for one game.
 */

type Verdict = 'win' | 'loss' | 'push' | 'void' | 'pending';
interface Outcome { result: Verdict; detail: string; }

/** Normalise for cross-provider matching: the two feeds agree on nothing but
 *  the spelling, and not always that. */
function normalizeName(n: string): string {
  return n.toLowerCase().trim()
    .normalize('NFD').replace(/[̀-ͯ]/g, '')   // accents
    .replace(/[.'`’-]/g, '')                        // D.K. -> dk, Ja'Marr -> jamarr
    .replace(/\s+(jr|sr|ii|iii|iv|v)$/, '')              // suffixes
    .replace(/\s+/g, ' ');
}

interface Candidate { id: number; first_name: string; last_name: string; position?: string; }

/**
 * Resolve a prop's subject to one player.
 *
 * `candidates` MUST be scoped to the two rosters of the game being graded, not
 * the league. That is the whole safety property: there are two prominent Josh
 * Allens in the NFL, and only one of them is in any given game.
 */
function resolvePlayer(name: string, candidates: Candidate[]):
  { ok: true; player: Candidate } | { ok: false; reason: string } {
  const target = normalizeName(name);
  const hits = candidates.filter((c) => normalizeName(`${c.first_name} ${c.last_name}`) === target);
  if (hits.length === 1) return { ok: true, player: hits[0] };
  if (hits.length === 0) return { ok: false, reason: `no player named "${name}" in this game` };
  return { ok: false, reason: `"${name}" matches ${hits.length} players in this game` };
}

/** Odds API market key -> the statline field that settles it. */
const STAT_FIELD: Record<string, (s: Record<string, number>) => number> = {
  player_points:   (s) => s.pts,
  player_rebounds: (s) => s.reb,
  player_assists:  (s) => s.ast,
  player_threes:   (s) => s.fg3m,
  // The NFL mapping is the same shape against balldontlie's NFL fields:
  //   player_pass_yds     -> passing_yards
  //   player_rush_yds     -> rushing_yards
  //   player_reception_yds-> receiving_yards
  //   player_receptions   -> receptions
  //   player_anytime_td   -> rushing_touchdowns + receiving_touchdowns > 0
};

function gradeProp(
  marketKey: string,
  side: string,                       // "Jayson Tatum Over 29.5"
  statlines: Array<{ player: Candidate; stats: Record<string, number> }>,
  roster: Candidate[],
): Outcome {
  const m = side.match(/^(.*)\s+(Over|Under)\s+([\d.]+)$/i);
  if (!m) return { result: 'pending', detail: `unparseable side "${side}"` };
  const [, rawName, direction, lineStr] = m;
  const line = Number(lineStr);

  const resolved = resolvePlayer(rawName, roster);
  // Never guess. An unresolved subject goes back to the organizer rather than
  // being settled against the wrong person.
  if (!resolved.ok) return { result: 'pending', detail: resolved.reason };

  const row = statlines.find((s) => s.player.id === resolved.player.id);
  // No statline means the player did not appear. That is a VOID — treating an
  // absent row as zero would settle every Over as a loss.
  if (!row) return { result: 'void', detail: `${rawName} did not play` };

  const getter = STAT_FIELD[marketKey];
  if (!getter) return { result: 'pending', detail: `no stat mapping for ${marketKey}` };
  const actual = getter(row.stats);
  if (actual === undefined || actual === null) {
    return { result: 'pending', detail: `statline has no ${marketKey}` };
  }

  const over = direction.toLowerCase() === 'over';
  if (actual === line) return { result: 'push', detail: `${rawName} ${actual} = ${line}` };
  const won = over ? actual > line : actual < line;
  return { result: won ? 'win' : 'loss',
           detail: `${rawName} ${actual} vs ${direction} ${line}` };
}

// ── run against the real game ────────────────────────────────────────────────
const raw = JSON.parse(Deno.readTextFileSync(Deno.args[0])).data as Array<Record<string, never>>;
const statlines = raw.map((s) => ({ player: s.player as unknown as Candidate,
                                    stats: s as unknown as Record<string, number> }));
const roster: Candidate[] = statlines.map((s) => s.player);


const cases: Array<[string, string, Verdict]> = [
  ['player_points',   'Jayson Tatum Over 29.5',   'win'],    // 37
  ['player_points',   'Jayson Tatum Under 29.5',  'loss'],
  ['player_points',   'Jayson Tatum Over 37',     'push'],   // exact line
  ['player_points',   'Jayson Tatum Under 37',    'push'],
  ['player_assists',  'Jayson Tatum Over 9.5',    'win'],    // 10
  ['player_threes',   'Derrick White Over 4.5',   'win'],    // 6
  ['player_rebounds', 'Jaylen Brown Under 8.5',   'win'],    // 7 reb -> Under wins
  ['player_points',   'Al Horford Over 10.5',     'win'],    // 11
  ['player_points',   'Sam Hauser Under 12.5',    'win'],    // 10
  // Unknown subject and inactive player are DIFFERENT outcomes, and conflating
  // them is how a book pays out on a prop it never should have graded.
  ['player_points',   'Nobody Atall Over 5.5',    'pending'],
  ['player_points',   'Benchwarmer Deepreserve Over 5.5', 'void'],
];

// A player who is ON the roster but has no statline: the DNP case.
roster.push({ id: 999999, first_name: 'Benchwarmer', last_name: 'Deepreserve' });

let bad = 0;
console.log('--- grading real props against a real box score ---');
for (const [key, side, expected] of cases) {
  const out = gradeProp(key, side, statlines, roster);
  // exact-line cases push, so fix expectations for those two
  const exp = expected;
  const ok = out.result === exp;
  if (!ok) bad++;
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${side.padEnd(32)} -> ${out.result.padEnd(7)} ${out.detail}`);
}

console.log('\n--- name normalisation (cross-provider spelling) ---');
const spellings = [
  ["Jayson Tatum", "Jayson Tatum"], ["jayson tatum", "Jayson Tatum"],
  ["Jayson Tatum Jr.", "Jayson Tatum"], ["Ja'Marr Chase", "JaMarr Chase"],
  ["D.K. Metcalf", "DK Metcalf"], ["Marvin Harrison Jr.", "Marvin Harrison"],
];
for (const [a, b] of spellings) {
  const same = normalizeName(a) === normalizeName(b);
  if (!same) bad++;
  console.log(`${same ? 'ok  ' : 'FAIL'} "${a}" == "${b}"`);
}

console.log('\n--- the safety property: ambiguity must NOT settle ---');
const twoAllens: Candidate[] = [
  { id: 1, first_name: 'Josh', last_name: 'Allen', position: 'QB' },
  { id: 2, first_name: 'Josh', last_name: 'Allen', position: 'LB' },
];
const amb = gradeProp('player_points', 'Josh Allen Over 1.5', [], twoAllens);
const safe = amb.result === 'pending';
if (!safe) bad++;
console.log(`${safe ? 'ok  ' : 'FAIL'} ambiguous name -> ${amb.result} (${amb.detail})`);

console.log(bad === 0 ? '\nALL CHECKS PASSED' : `\n${bad} FAILURES`);
