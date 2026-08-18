import { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';

/**
 * PostgREST returns at most 1000 rows for a select with no explicit range.
 * There is no error and no warning — the result is silently truncated.
 *
 * That truncation caused a production incident: sync_games used a plain
 * `.in('external_id', ids)` to decide which events already existed. Once the
 * events table grew past 1000 matching rows, everything beyond the cap looked
 * new and was inserted again, duplicating events on every run and leaving the
 * duplicates with no markets attached.
 *
 * Use these helpers for any query whose result set can exceed 1000 rows.
 */

const PAGE_SIZE = 1000;   // PostgREST's cap
const IN_CHUNK = 200;     // keeps the request URL a sane length

/** Shape callers rely on for logging. PostgrestError is assignable to this. */
export interface PostgrestErrorLike {
  message: string;
}

/**
 * Fetch every row of `table` where `column` is one of `values`.
 *
 * Chunks the IN list so the URL stays short, and pages each chunk so a chunk
 * matching more than PAGE_SIZE rows is still returned in full.
 */
export async function selectAllIn<T = Record<string, unknown>>(
  client: SupabaseClient,
  table: string,
  columns: string,
  column: string,
  values: string[],
): Promise<{ data: T[]; error: PostgrestErrorLike | null }> {
  const unique = Array.from(new Set(values.filter(Boolean)));
  const out: T[] = [];

  for (let i = 0; i < unique.length; i += IN_CHUNK) {
    const chunk = unique.slice(i, i + IN_CHUNK);
    let from = 0;

    while (true) {
      const { data, error } = await client
        .from(table)
        .select(columns)
        .in(column, chunk)
        .range(from, from + PAGE_SIZE - 1);

      if (error) return { data: out, error };

      const batch = (data ?? []) as T[];
      out.push(...batch);

      if (batch.length < PAGE_SIZE) break;
      from += PAGE_SIZE;
    }
  }

  return { data: out, error: null };
}

/**
 * Page through an arbitrary filtered select.
 *
 * `build` must return a fresh query each call — PostgREST query builders are
 * single-use, so reusing one across pages throws.
 *
 *   const { data } = await selectAllPaged(() =>
 *     client.from('events').select('id').eq('status', 'scheduled'));
 */
export async function selectAllPaged<T = Record<string, unknown>>(
  build: () => {
    range: (from: number, to: number) => PromiseLike<{ data: unknown; error: PostgrestErrorLike | null }>;
  },
): Promise<{ data: T[]; error: PostgrestErrorLike | null }> {
  const out: T[] = [];
  let from = 0;

  while (true) {
    const { data, error } = await build().range(from, from + PAGE_SIZE - 1);
    if (error) return { data: out, error };

    const batch = (data ?? []) as T[];
    out.push(...batch);

    if (batch.length < PAGE_SIZE) break;
    from += PAGE_SIZE;
  }

  return { data: out, error: null };
}
