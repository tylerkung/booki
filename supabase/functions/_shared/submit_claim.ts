import { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';
import {
  PayloadMismatchError,
  SubmitOperation,
  canonicalSubmitPayload,
  isPayloadMismatch,
} from './submit_idempotency.ts';

interface ClaimResult {
  replayed: boolean;
  body: string;
}

function mismatchOrThrow(error: { message?: string; code?: string } | null): void {
  if (!error) return;
  if (isPayloadMismatch(error)) throw new PayloadMismatchError();
  throw new Error(error.message || 'submit idempotency failed');
}

function responseText(data: { response?: unknown } | null): string {
  return JSON.stringify(data?.response ?? null);
}

/**
 * Read a stored submit, if this player (or this user's legacy row) already
 * claimed the key. Returns the original JSON body, or null when the key is
 * free. A different payload throws PayloadMismatchError and writes nothing.
 */
export async function peekSubmission(
  client: SupabaseClient,
  operation: SubmitOperation,
  userId: string,
  playerId: string,
  idempotencyKey: string,
  request: Record<string, unknown>,
): Promise<string | null> {
  const { data, error } = await client.rpc('peek_bet_submission', {
    p_operation: operation,
    p_idempotency_key: idempotencyKey,
    p_user_id: userId,
    p_player_id: playerId,
    p_request: requestPayload(operation, request),
  });
  mismatchOrThrow(error);
  const row = data as { found?: boolean; response?: unknown } | null;
  if (!row?.found) return null;
  return responseText(row);
}

/**
 * Claim the key and insert the bet rows in one database transaction.
 * A concurrent or later call with the same payload returns the original
 * body and inserts nothing.
 */
export async function claimSubmission(
  client: SupabaseClient,
  operation: SubmitOperation,
  userId: string,
  playerId: string,
  bookieId: string,
  idempotencyKey: string,
  request: Record<string, unknown>,
  bets: unknown[],
  extra: Record<string, unknown>,
): Promise<ClaimResult> {
  const { data, error } = await client.rpc('claim_bet_submission', {
    p_operation: operation,
    p_idempotency_key: idempotencyKey,
    p_user_id: userId,
    p_player_id: playerId,
    p_bookie_id: bookieId,
    p_request: requestPayload(operation, request),
    p_bets: bets,
    p_extra: extra,
  });
  mismatchOrThrow(error);
  const row = data as { replayed?: boolean; response?: unknown } | null;
  return { replayed: row?.replayed === true, body: responseText(row) };
}

function requestPayload(operation: SubmitOperation, request: Record<string, unknown>) {
  return canonicalSubmitPayload(operation, request);
}

export async function replayedResponse(
  client: SupabaseClient,
  operation: SubmitOperation,
  userId: string,
  playerId: string,
  idempotencyKey: string,
  request: Record<string, unknown>,
  corsHeaders: Record<string, string>,
): Promise<Response | null> {
  try {
    const replay = await peekSubmission(client, operation, userId, playerId, idempotencyKey, request);
    if (!replay) return null;
    return jsonResponse(replay, corsHeaders);
  } catch (err) {
    if (err instanceof PayloadMismatchError) return mismatchResponse(corsHeaders);
    throw err;
  }
}

export async function claimedResponse(
  client: SupabaseClient,
  operation: SubmitOperation,
  userId: string,
  playerId: string,
  bookieId: string,
  idempotencyKey: string,
  request: Record<string, unknown>,
  bets: unknown[],
  extra: Record<string, unknown>,
  corsHeaders: Record<string, string>,
): Promise<{ replayed: boolean; body: string; http: Response }> {
  try {
    const result = await claimSubmission(
      client, operation, userId, playerId, bookieId, idempotencyKey, request, bets, extra,
    );
    return {
      replayed: result.replayed,
      body: result.body,
      http: jsonResponse(result.body, corsHeaders),
    };
  } catch (err) {
    if (err instanceof PayloadMismatchError) {
      return { replayed: false, body: '', http: mismatchResponse(corsHeaders) };
    }
    throw err;
  }
}

export function mismatchResponse(corsHeaders: Record<string, string>): Response {
  return new Response(
    JSON.stringify({ success: false, error: 'idempotency_payload_mismatch' }),
    { status: 422, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
  );
}

export function jsonResponse(body: string, corsHeaders: Record<string, string>, status = 200): Response {
  return new Response(body, {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
