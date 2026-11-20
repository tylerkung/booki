/**
 * Identity of a submit_bet / submit_bets / submit_parlay request.
 *
 * The idempotency key is not part of the payload. Two calls with the same
 * key and the same payload are one ticket. The same key with a different
 * payload is a rejection, not a second ticket.
 *
 * stake is a 2-decimal string so 1, "1", and "1.00" are one payload.
 * UUIDs are lowercase. side_label is display copy and is not identity.
 * Key order in the object does not matter: payloadsMatch sorts keys, and
 * Postgres jsonb equality does the same when the function stores this object.
 */

export type SubmitOperation = 'submit_bet' | 'submit_bets' | 'submit_parlay';

export class PayloadMismatchError extends Error {
  constructor() {
    super('idempotency_payload_mismatch');
    this.name = 'PayloadMismatchError';
  }
}

export type SubmissionDecision = 'insert' | 'replay' | 'mismatch';

interface StoredSubmission {
  request_payload?: unknown;
}

function uuid(value: unknown): string {
  return String(value ?? '').trim().toLowerCase();
}

function money(value: unknown): string {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return money(value.toFixed(2));
  }
  if (typeof value !== 'string') return '';
  const trimmed = value.trim();
  if (!/^-?\d+(\.\d+)?$/.test(trimmed)) return '';
  const negative = trimmed.startsWith('-');
  const unsigned = negative ? trimmed.slice(1) : trimmed;
  const [whole, frac = ''] = unsigned.split('.');
  const cents = (frac + '00').slice(0, 2);
  const normalized = `${String(parseInt(whole || '0', 10))}.${cents}`;
  return negative ? `-${normalized}` : normalized;
}

function odds(value: unknown): number | null {
  if (typeof value === 'number' && Number.isInteger(value)) return value;
  if (typeof value === 'string' && /^[+-]?\d+$/.test(value.trim())) return Number(value.trim());
  return null;
}

function text(value: unknown): string {
  return value == null ? '' : String(value);
}

function singleItem(bet: Record<string, unknown>) {
  return {
    event_id: uuid(bet.event_id),
    market_id: uuid(bet.market_id),
    side: text(bet.side).trim(),
    odds: odds(bet.odds),
    stake: money(bet.stake),
  };
}

function parlayLeg(leg: Record<string, unknown>) {
  return {
    event_id: uuid(leg.event_id),
    market_id: uuid(leg.market_id),
    side: text(leg.side).trim(),
    side_indicator: text(leg.side_indicator).trim(),
    odds: odds(leg.odds),
  };
}

export function canonicalSubmitPayload(
  operation: SubmitOperation,
  body: Record<string, unknown>,
): Record<string, unknown> {
  const base = {
    operation,
    player_id: uuid(body.player_id),
    bookie_id: uuid(body.bookie_id),
  };
  if (operation === 'submit_bet') {
    return { ...base, ...singleItem(body) };
  }
  if (operation === 'submit_bets') {
    const bets = Array.isArray(body.bets) ? body.bets : [];
    return {
      ...base,
      bets: bets.map((bet) => singleItem((bet ?? {}) as Record<string, unknown>)),
    };
  }
  const legs = Array.isArray(body.legs) ? body.legs : [];
  return {
    ...base,
    stake: money(body.stake),
    combined_odds: odds(body.combined_odds),
    legs: legs.map((leg) => parlayLeg((leg ?? {}) as Record<string, unknown>)),
  };
}

function stable(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(stable);
  if (value && typeof value === 'object') {
    const source = value as Record<string, unknown>;
    const out: Record<string, unknown> = {};
    for (const key of Object.keys(source).sort()) out[key] = stable(source[key]);
    return out;
  }
  return value;
}

export function payloadsMatch(left: unknown, right: unknown): boolean {
  return JSON.stringify(stable(left)) === JSON.stringify(stable(right));
}

/**
 * Mirrors claim_bet_submission / peek_bet_submission.
 * A stored row with a null request_payload is a legacy write (the old
 * functions stored the response and nothing else). Replaying it returns
 * that response. A stored payload that differs is a mismatch.
 */
export function submissionDecision(
  existing: StoredSubmission | null,
  request: unknown,
): SubmissionDecision {
  if (!existing) return 'insert';
  if (existing.request_payload == null) return 'replay';
  return payloadsMatch(existing.request_payload, request) ? 'replay' : 'mismatch';
}

export function isPayloadMismatch(error: { message?: string; code?: string } | null): boolean {
  if (!error) return false;
  if (error.code === 'P0422') return true;
  return (error.message || '').includes('idempotency_payload_mismatch');
}
