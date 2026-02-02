import { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';

/**
 * Idempotency helpers for Edge Functions.
 *
 * These helpers provide a consistent way to check and store idempotency keys
 * across all Edge Functions that perform mutations.
 */

/**
 * Check if an idempotency key already exists for the given operation.
 * Returns the cached response if the key exists, null otherwise.
 *
 * @param client - Supabase client (service role)
 * @param key - The idempotency key from the client request
 * @param operation - The operation name (e.g., 'submit_bet', 'accept_bet')
 * @returns The cached response string if key exists, null otherwise
 */
export async function checkIdempotency(
  client: SupabaseClient,
  key: string,
  operation: string
): Promise<string | null> {
  const { data: existingIdempotency } = await client
    .from('idempotency_keys')
    .select('response')
    .eq('key', key)
    .eq('operation', operation)
    .single();

  if (existingIdempotency) {
    return existingIdempotency.response;
  }

  return null;
}

/**
 * Store an idempotency key with its associated response.
 * This should be called after a successful operation to cache the response.
 *
 * Errors are logged but not thrown to avoid failing the main operation
 * (the mutation was already successful at this point).
 *
 * @param client - Supabase client (service role)
 * @param key - The idempotency key from the client request
 * @param operation - The operation name (e.g., 'submit_bet', 'accept_bet')
 * @param userId - The authenticated user's ID
 * @param response - The JSON response string to cache
 */
export async function storeIdempotency(
  client: SupabaseClient,
  key: string,
  operation: string,
  userId: string,
  response: string
): Promise<void> {
  const { error } = await client
    .from('idempotency_keys')
    .insert({
      key: key,
      operation: operation,
      response: response,
      user_id: userId,
    });

  if (error) {
    console.error('Error storing idempotency key:', error);
  }
}
