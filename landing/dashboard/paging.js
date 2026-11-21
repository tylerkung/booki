/**
 * Page a PostgREST select past the silent 1000-row cap.
 *
 * There is no error when the cap cuts a response off. build() must return a
 * fresh query each call — the builder is single-use.
 *
 *   const { data, error } = await BookiPaging.fetchAllRows(() =>
 *     supabase.from('events').select('*').order('start_time'));
 */
async function fetchAllRows(build, pageSize) {
    const size = pageSize || 1000;
    const out = [];
    let from = 0;
    for (;;) {
        const { data, error } = await build().range(from, from + size - 1);
        if (error) return { data: out, error };
        const batch = data || [];
        for (let i = 0; i < batch.length; i++) out.push(batch[i]);
        if (batch.length < size) return { data: out, error: null };
        from += size;
    }
}

globalThis.BookiPaging = { fetchAllRows };
