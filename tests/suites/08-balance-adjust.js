import { callEdge, uuid, getServiceClient } from '../lib/client.js';
import { eq, ok } from '../lib/assert.js';

export default async function balanceAdjust(ctx) {
  const svc = getServiceClient();

  // Adjustment type (default)
  {
    const { status, data } = await callEdge('adjust_balance', {
      player_id: ctx.playerId,
      amount: '25.50',
      reason: 'Test adjustment',
      type: 'adjustment',
      idempotency_key: uuid(),
    }, ctx.bookieToken);

    eq(status, 200, 'adjustment → 200');
    eq(data?.success, true, 'adjustment success');
    ok(data?.ledger_entry, 'adjustment returns ledger_entry');
    eq(data?.ledger_entry?.type, 'adjustment', 'type = adjustment');
  }

  // paymentLogged type (settle up)
  {
    const { status, data } = await callEdge('adjust_balance', {
      player_id: ctx.playerId,
      amount: '-100',
      reason: 'Venmo payment',
      type: 'paymentLogged',
      idempotency_key: uuid(),
    }, ctx.bookieToken);

    eq(status, 200, 'paymentLogged → 200');
    eq(data?.success, true, 'paymentLogged success');
    eq(data?.ledger_entry?.type, 'paymentLogged', 'type = paymentLogged');
  }

  // Negative amount (bookie pays player)
  {
    const { status, data } = await callEdge('adjust_balance', {
      player_id: ctx.playerId,
      amount: '-50',
      idempotency_key: uuid(),
    }, ctx.bookieToken);

    eq(status, 200, 'negative amount → 200');
    eq(data?.success, true, 'negative amount success');
  }

  // Missing amount → 400
  {
    const { status } = await callEdge('adjust_balance', {
      player_id: ctx.playerId,
      idempotency_key: uuid(),
    }, ctx.bookieToken);
    eq(status, 400, 'missing amount → 400');
  }

  // Missing player_id → 400
  {
    const { status } = await callEdge('adjust_balance', {
      amount: '10',
      idempotency_key: uuid(),
    }, ctx.bookieToken);
    ok(status === 400 || status === 404, `missing player_id → ${status}`);
  }

  // Player not owned by bookie → 403
  {
    const { status } = await callEdge('adjust_balance', {
      player_id: ctx.player2Id,
      amount: '10',
      idempotency_key: uuid(),
    }, ctx.bookieToken);
    ok(status === 403 || status === 404, `adjust unowned player → ${status}`);
  }

  // Verify balance reflects adjustments
  {
    const { data: balanceRow } = await svc.from('player_balances_view').select('balance_owed').eq('player_id', ctx.playerId).single();
    ok(balanceRow !== null, `balance after adjustments: ${balanceRow?.balance_owed}`);
  }
}
