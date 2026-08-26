import { callEdge, uuid, getServiceClient } from '../lib/client.js';
import { eq, ok } from '../lib/assert.js';

/**
 * End-to-end player prop settlement against a REAL box score.
 *
 * Uses balldontlie game 423945 (Cowboys at Eagles, 2025-09-05), a completed
 * game whose statlines are fixed forever, so the expected grades are known
 * exactly rather than mocked:
 *
 *   Jalen Hurts   152 passing yards, 2 rushing touchdowns
 *   Saquon Barkley 60 rushing yards
 *   Dante Fowler Jr. appears with EVERY stat at zero — he dressed and
 *                    recorded nothing, which must grade as a loss on an Over
 *                    and is the case most likely to be mishandled as a void
 *
 * The DNP case uses a player with no row at all, which is the only signal
 * balldontlie gives that someone did not play.
 */
const BDL_GAME_ID = 423945;

export default async function propGrading(ctx) {
  const svc = getServiceClient();
  const made = { eventId: null, marketIds: [], betIds: [] };

  try {
    // A completed event wired to the real balldontlie game.
    const { data: ev, error: evErr } = await svc.from('events').insert({
      name: 'Dallas Cowboys @ Philadelphia Eagles',
      sport: 'Football', league: 'NFL',
      home_team: 'Philadelphia Eagles', away_team: 'Dallas Cowboys',
      start_time: '2025-09-05T00:20:00Z',
      status: 'final', home_score: 24, away_score: 20,
      bdl_game_id: BDL_GAME_ID,
      external_id: `test_prop_${Date.now()}`,
    }).select('id').single();
    if (evErr) { ok(false, `event insert: ${evErr.message}`); return; }
    made.eventId = ev.id;
    ok(true, `test event ${ev.id.slice(0, 8)} -> bdl game ${BDL_GAME_ID}`);

    // Resolve real balldontlie ids so the markets point at real people.
    const ids = {};
    for (const [label, first, last] of [
      ['hurts', 'Jalen', 'Hurts'], ['barkley', 'Saquon', 'Barkley'], ['fowler', 'Dante', 'Fowler'],
    ]) {
      const r = await fetch(
        `https://api.balldontlie.io/nfl/v1/players?first_name=${first}&last_name=${last}&per_page=25`,
        { headers: { Authorization: process.env.BALLDONTLIE_API_KEY } });
      const d = await r.json();
      const hit = (d.data || []).find(p => p.last_name.startsWith(last));
      ids[label] = hit?.id;
    }
    ok(ids.hurts && ids.barkley && ids.fowler, 'resolved real player ids');

    // Cache them so the market rows satisfy the FK + CHECK constraint.
    for (const [label, id] of Object.entries(ids)) {
      await svc.from('bdl_players').upsert({
        bdl_player_id: id, first_name: label, last_name: label,
        normalized_name: `${label} ${label}`, sport: 'NFL',
      }, { onConflict: 'bdl_player_id' });
    }

    // side, stat, subject, expected grade
    const cases = [
      ['Jalen Hurts Over 100.5',        'player_pass_yds',  ids.hurts,   'win'],   // 152
      ['Jalen Hurts Under 100.5',       'player_pass_yds',  ids.hurts,   'loss'],
      ['Saquon Barkley Over 60',        'player_rush_yds',  ids.barkley, 'push'],  // exactly 60
      ['Dante Fowler Over 0.5',         'player_rush_yds',  ids.fowler,  'loss'],  // zero row: PLAYED
      ['Nobody Whodidntplay Over 10.5', 'player_rush_yds',  999999999,   'void'],  // no row at all
    ];

    for (const [side, statKey, subject, _expected] of cases) {
      if (subject === 999999999) {
        await svc.from('bdl_players').upsert({
          bdl_player_id: subject, first_name: 'Nobody', last_name: 'Whodidntplay',
          normalized_name: 'nobody whodidntplay', sport: 'NFL',
        }, { onConflict: 'bdl_player_id' });
      }
      const { data: mkt, error: mErr } = await svc.from('markets').insert({
        event_id: made.eventId, bookie_id: null, type: 'player_prop',
        side_a: side, side_b: side.replace(/Over/, 'Under'),
        odds_a: -110, odds_b: -110,
        stat_key: statKey, subject_player_id: subject, subject_name: side.split(' Over')[0],
      }).select('id').single();
      if (mErr) { ok(false, `market insert: ${mErr.message}`); return; }
      made.marketIds.push(mkt.id);

      const { data: bet, error: bErr } = await svc.from('bets').insert({
        bookie_id: ctx.bookieId, player_id: ctx.playerId, event_id: made.eventId,
        market_id: mkt.id, market: statKey, side, odds: -110, stake: 10,
        status: 'accepted', is_parlay: false, parlay_legs: 1,
      }).select('id').single();
      if (bErr) { ok(false, `bet insert: ${bErr.message}`); return; }
      made.betIds.push(bet.id);
    }
    ok(true, `${made.betIds.length} prop bets staged`);

    // force skips only the settling delay, never the completeness gate.
    const { status, data } = await callEdge('grade_player_props', { force: true });
    eq(status, 200, 'grade_player_props -> 200');
    eq(data?.games_graded >= 1, true, `graded ${data?.games_graded} game(s)`);

    const { data: graded } = await svc.from('bets')
      .select('id, side, grade_result, status').in('id', made.betIds);
    const byId = new Map((graded || []).map(b => [b.id, b]));

    for (let i = 0; i < cases.length; i++) {
      const [side, , , expected] = cases[i];
      const b = byId.get(made.betIds[i]);
      eq(b?.grade_result, expected, `${side} -> ${expected}`);
    }

    // The zero-row case is the one worth stating twice: it must NOT be a void.
    const fowler = byId.get(made.betIds[3]);
    eq(fowler?.grade_result !== 'void', true, 'an all-zero statline is NOT a void');

    // Ledger: a loss owes the stake, a push/void moves nothing.
    const { data: ledger } = await svc.from('ledger_entries')
      .select('bet_id, amount, type').in('bet_id', made.betIds);
    const amt = id => Number((ledger || []).find(l => l.bet_id === id)?.amount ?? NaN);
    eq(amt(made.betIds[1]), 10, 'loss writes +stake to the ledger');
    eq(amt(made.betIds[2]), 0, 'push writes 0');
    eq(amt(made.betIds[4]), 0, 'void writes 0');
    ok(Math.abs(amt(made.betIds[0]) - (-9.0909)) < 0.01, 'win writes -profit (-9.09 at -110)');
  } finally {
    for (const id of made.betIds) {
      try { await svc.from('ledger_entries').delete().eq('bet_id', id); } catch {}
      try { await svc.from('bets').delete().eq('id', id); } catch {}
    }
    for (const id of made.marketIds) { try { await svc.from('markets').delete().eq('id', id); } catch {} }
    if (made.eventId) {
      try { await svc.from('prop_grading_runs').delete().eq('event_id', made.eventId); } catch {}
      try { await svc.from('events').delete().eq('id', made.eventId); } catch {}
    }
    try { await svc.from('bdl_players').delete().eq('bdl_player_id', 999999999); } catch {}
  }
}
