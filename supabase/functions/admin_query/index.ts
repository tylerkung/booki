import { Client as PgClient } from 'https://deno.land/x/postgres@v0.19.3/mod.ts';
import { corsHeaders } from '../_shared/cors.ts';
import { createServiceClient, getUserIdFromAuthHeader } from '../_shared/supabase.ts';

/**
 * Platform admin browser — read side.
 *
 * One gated function rather than a SECURITY DEFINER RPC per view, per
 * tasks/prd-admin-dashboard.md. The allowlist check happens once here; spread
 * across a dozen RPCs, a single missing check silently leaks every tenant's
 * data to any authenticated user.
 *
 * READ ONLY, deliberately. Bets and ledger entries are written only through
 * edge functions that enforce idempotency, business rules, audit trails and a
 * tamper-evident hash chain. A write path here would bypass all of it: editing
 * a bet's status directly skips the balance recalculation and the audit event,
 * leaving the ledger disagreeing with the bets table — corruption that surfaces
 * weeks later and cannot be untangled. Every query below is a .select().
 */

/** PostgREST silently truncates an unbounded select at 1000 rows. */
const PAGE = 1000;

/** Cap on rows returned to the browser for any one view. */
const MAX_ROWS = 2000;

interface AdminRequest {
  view?: string;
  id?: string;
  q?: string;
  sql?: string;
  sport_key?: string;
  market_sets?: Array<{ label?: string; markets: string; per_event?: boolean }>;
  max_rows?: number;
  return_payload?: boolean;
  /** Include synthetic and load-test accounts. Off by default: they distorted
   *  every count during the 2026-08-18 audit. */
  include_test?: boolean;
}

const TEST_PATTERNS = [/^test_stress_/i, /@example\.com$/i, /^synthetic/i];

function isTestAccount(email: string | null | undefined, name?: string | null): boolean {
  const hay = `${email ?? ''} ${name ?? ''}`.trim();
  if (!hay) return false;
  return TEST_PATTERNS.some((p) => p.test(email ?? '') || p.test(name ?? ''));
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

/** Read an entire table in pages, so no view is silently truncated at 1000. */
async function selectAll<T = Record<string, unknown>>(
  client: ReturnType<typeof createServiceClient>,
  table: string,
  columns: string,
): Promise<T[]> {
  const out: T[] = [];
  let from = 0;
  while (out.length < MAX_ROWS) {
    const { data, error } = await client.from(table).select(columns).range(from, from + PAGE - 1);
    if (error) throw new Error(`${table}: ${error.message}`);
    const batch = (data ?? []) as T[];
    out.push(...batch);
    if (batch.length < PAGE) break;
    from += PAGE;
  }
  return out;
}


/**
 * Run one statement inside a genuine READ ONLY transaction.
 *
 * Migration 038 blocks writes at the parser, by running the query inside a
 * FROM subquery — that stops DML, DDL, a trailing statement and a
 * data-modifying CTE. What it cannot stop is `SELECT some_function()`, which
 * is a legal subquery, and 17 of this database's 20 public functions are
 * SECURITY DEFINER. One of them is delete_bookie_data. A read-only ROLE would
 * not help: SECURITY DEFINER runs as the function's owner, not the caller's.
 *
 * A read-only TRANSACTION does help, because the check lives in the executor
 * and is independent of role — and a function cannot turn it off from the
 * inside, since setting transaction_read_only to off inside a read-only
 * transaction is itself an error.
 *
 * That mode can only be set on a connection, never inside a plpgsql function
 * (Postgres: "cannot be set locally in functions"), which is why this opens
 * its own connection rather than going through PostgREST.
 */
/**
 * Postgres int8 arrives as a JavaScript BigInt, which JSON.stringify throws on
 * rather than skipping — so a single count(*) took down the whole response.
 * Rendered as a string beyond Number.MAX_SAFE_INTEGER so a real bigint is not
 * silently rounded; below that a number keeps the client's formatting working.
 */
/**
 * Is there more than one statement here?
 *
 * This endpoint runs exactly one statement. That is a structural rule about
 * the shape of the input, not a guess at what the SQL does — no keyword list,
 * no regex for DELETE — so it does not reintroduce the approach the PRD rules
 * out.
 *
 * It exists because the driver does not fail gracefully on a multi-statement
 * string: `select 1; drop table x` took the isolate down, so the operator saw
 * a dead request instead of an error message. Nothing executed (the subquery
 * wrapper's parentheses make it a syntax error, and the table was verified
 * still present), but an unexplained connection failure is a bad way to learn
 * you typed two statements.
 *
 * Semicolons inside string literals, dollar-quoted blocks and comments are not
 * separators, so each is skipped rather than counted.
 */
function hasMultipleStatements(sql: string): boolean {
  let i = 0;
  let seenSeparator = false;

  while (i < sql.length) {
    const c = sql[i];

    if (c === '-' && sql[i + 1] === '-') {
      const nl = sql.indexOf('\n', i);
      i = nl === -1 ? sql.length : nl + 1;
      continue;
    }
    if (c === '/' && sql[i + 1] === '*') {
      const close = sql.indexOf('*/', i + 2);
      i = close === -1 ? sql.length : close + 2;
      continue;
    }
    if (c === "'" || c === '"') {
      const quote = c;
      i++;
      while (i < sql.length) {
        if (sql[i] === quote) {
          // A doubled quote is an escaped quote, not the end of the literal.
          if (sql[i + 1] === quote) { i += 2; continue; }
          i++;
          break;
        }
        i++;
      }
      continue;
    }
    if (c === '$') {
      const tag = /^\$[A-Za-z_]*\$/.exec(sql.slice(i));
      if (tag) {
        const close = sql.indexOf(tag[0], i + tag[0].length);
        i = close === -1 ? sql.length : close + tag[0].length;
        continue;
      }
    }
    if (c === ';') {
      // A trailing semicolon is fine; anything after it is a second statement.
      if (sql.slice(i + 1).trim().length > 0) { seenSeparator = true; break; }
    }
    i++;
  }
  return seenSeparator;
}

function toJsonSafe(row: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(row)) {
    if (typeof v === 'bigint') {
      out[k] = v <= BigInt(Number.MAX_SAFE_INTEGER) && v >= -BigInt(Number.MAX_SAFE_INTEGER)
        ? Number(v) : v.toString();
    } else if (v instanceof Date) {
      out[k] = v.toISOString();
    } else if (v instanceof Uint8Array) {
      out[k] = `\\x${Array.from(v).map((b) => b.toString(16).padStart(2, '0')).join('')}`;
    } else {
      out[k] = v;
    }
  }
  return out;
}

async function runReadOnly(
  sql: string,
  maxRows: number,
  timeoutMs = 5000,
): Promise<Record<string, unknown>> {
  const dbUrl = Deno.env.get('SUPABASE_DB_URL');
  if (!dbUrl) {
    return { error: 'SUPABASE_DB_URL is not available to this function', no_connection: true };
  }

  if (hasMultipleStatements(sql)) {
    return {
      error: 'Run one statement at a time.',
      multiple_statements: true,
      write_blocked: true,
    };
  }

  // A trailing semicolon is how most people end a statement, but it lands
  // inside the wrapper's parentheses and makes it a syntax error. Strip it
  // rather than making the operator care where their query is embedded.
  const body = sql.replace(/;\s*$/, '');

  const started = Date.now();
  const client = new PgClient(dbUrl);
  try {
    await client.connect();
    // READ ONLY must be on the BEGIN itself — it cannot be turned on later in
    // a transaction that has already run a command.
    await client.queryArray('BEGIN READ ONLY');
    await client.queryArray(`SET LOCAL statement_timeout = ${Math.min(Math.max(timeoutMs, 100), 15000)}`);

    // Same subquery wrapping as migration 038: two independent controls, one
    // at the parser and one in the executor.
    const wrapped = `SELECT * FROM (${body}) q LIMIT ${Math.min(Math.max(maxRows, 1), 5000)}`;

    // `args: []` forces the EXTENDED query protocol. Without it the driver uses
    // the simple protocol, which accepts a multi-statement string — and on
    // `select 1; drop table x` it did not reject cleanly, it took the isolate
    // down, so the browser saw a connection failure rather than an error. The
    // extended protocol permits exactly one statement and reports the rest as a
    // normal server error. (The table was never dropped either way; the
    // wrapper's parentheses made it a syntax error. The problem was the shape
    // of the failure, not a breach.)
    const res = await client.queryObject({ text: wrapped, args: [] });

    return {
      rows: (res.rows as Record<string, unknown>[]).map(toJsonSafe),
      row_count: res.rows.length,
      truncated: res.rows.length >= maxRows,
      elapsed_ms: Date.now() - started,
      read_only: true,
    };
  } catch (err) {
    // The driver does not always throw an Error, and a thrown non-Error that
    // escapes here would surface as a dead connection rather than a message.
    const message = err instanceof Error
      ? err.message
      : (typeof err === 'object' && err !== null && 'message' in err
          ? String((err as { message: unknown }).message)
          : String(err));
    const code = (err as { fields?: { code?: string } })?.fields?.code ?? null;
    return {
      error: message,
      sqlstate: code,
      // 25006 read-only, 0A000 nested data-modifying CTE, 42601 a write shape
      // that could not parse inside the wrapper.
      write_blocked: ['25006', '0A000', '42601'].includes(String(code)),
      read_only: true,
    };
  } finally {
    // ROLLBACK rather than COMMIT: nothing should have changed, and if
    // somehow it did, this is the last chance to discard it.
    try { await client.queryArray('ROLLBACK'); } catch { /* connection may be gone */ }
    try { await client.end(); } catch { /* ignore */ }
  }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    const authHeader = req.headers.get('Authorization');
    const userId = await getUserIdFromAuthHeader(authHeader);
    if (!userId) return json({ error: 'Unauthorized' }, 401);

    const client = createServiceClient();

    // Resolve the caller's own email from auth, never from the request body.
    const { data: caller } = await client.auth.admin.getUserById(userId);
    const callerEmail = (caller?.user?.email ?? '').trim().toLowerCase();

    // The allowlist is a secret, not a table row and not a constant in the
    // client. Hiding the nav item in the SPA is not access control.
    const allow = (Deno.env.get('ADMIN_EMAILS') ?? '')
      .split(',')
      .map((e) => e.trim().toLowerCase())
      .filter(Boolean);

    if (allow.length === 0) {
      console.error('ADMIN_EMAILS is unset — refusing all admin access');
      return json({ error: 'Not found' }, 404);
    }

    if (!callerEmail || !allow.includes(callerEmail)) {
      // 404 rather than 403: a non-admin learns nothing about whether this
      // endpoint exists, and the body carries no data either way.
      return json({ error: 'Not found' }, 404);
    }

    const body: AdminRequest = req.method === 'POST' ? await req.json() : {};
    const view = body.view ?? 'overview';
    const includeTest = body.include_test === true;

    // ── load the small tables once; every view is a projection of these ──
    const [bookies, players, invites, balances] = await Promise.all([
      // auth_user_id is not optional here: the users view keys organizers by it,
      // and omitting it silently mapped every organizer to the empty string,
      // which reported real organizers as 'unlinked'.
      selectAll(client, 'bookies',
        'id, auth_user_id, name, email, tier, subscription_status, subscription_source, created_at, ' +
        'default_credit_limit, default_win_limit, manual_bet_acceptance, manual_bet_grading'),
      selectAll(client, 'players',
        'id, name, display_name, email, bookie_id, auth_user_id, status, claimed_at, ' +
        'created_at, credit_limit, win_limit, win_limit_action'),
      selectAll(client, 'invites',
        'id, bookie_id, invite_code, email, created_at, expires_at, claimed_at, claimed_by_player_id'),
      selectAll(client, 'player_balances_view', 'player_id, bookie_id, balance_owed'),
    ]);

    const bookieById = new Map(bookies.map((b: any) => [String(b.id).toLowerCase(), b]));
    const playerById = new Map(players.map((p: any) => [String(p.id).toLowerCase(), p]));
    const balanceByPlayer = new Map(
      balances.map((b: any) => [String(b.player_id).toLowerCase(), Number(b.balance_owed) || 0]),
    );

    const orgLabel = (id: string | null) => {
      if (!id) return null;
      const b: any = bookieById.get(String(id).toLowerCase());
      return b ? { id: b.id, name: b.name, email: b.email, tier: b.tier } : { id, name: null, email: null };
    };
    const memberLabel = (id: string | null) => {
      if (!id) return null;
      const p: any = playerById.get(String(id).toLowerCase());
      return p ? { id: p.id, name: p.display_name || p.name, email: p.email } : { id, name: null };
    };

    const hideTest = (email: string | null, name: string | null) =>
      !includeTest && isTestAccount(email, name);

    switch (view) {
      // ── Everyone with an account, and what they resolved to ──────────────
      case 'users': {
        // auth.users is the only complete list. Someone can sign up and end up
        // neither an organizer nor a member — that gap is exactly the failure
        // that stranded three invitees in August, so it has to be visible.
        const authUsers: any[] = [];
        let page = 1;
        while (authUsers.length < MAX_ROWS) {
          const { data, error } = await client.auth.admin.listUsers({ page, perPage: 1000 });
          if (error) throw new Error(`auth.users: ${error.message}`);
          const batch = data?.users ?? [];
          authUsers.push(...batch);
          if (batch.length < 1000) break;
          page++;
        }

        const bookieByAuth = new Map(bookies.map((b: any) => [String(b.auth_user_id ?? '').toLowerCase(), b]));
        const playersByAuth = new Map<string, any[]>();
        for (const p of players as any[]) {
          const k = String(p.auth_user_id ?? '').toLowerCase();
          if (!k) continue;
          if (!playersByAuth.has(k)) playersByAuth.set(k, []);
          playersByAuth.get(k)!.push(p);
        }

        const rows = authUsers
          .filter((u) => !hideTest(u.email ?? null, null))
          .map((u) => {
            const key = String(u.id).toLowerCase();
            const asBookie = bookieByAuth.get(key);
            const asPlayers = playersByAuth.get(key) ?? [];
            const primary = asPlayers[0];
            let role = 'unlinked';
            if (asBookie && primary && String(primary.bookie_id).toLowerCase() !== String(asBookie.id).toLowerCase()) {
              // A player under someone else's book who also owns an empty book
              // of their own — the spurious-organizer shape.
              role = 'member (owns stray book)';
            } else if (asBookie) role = 'organizer';
            else if (primary) role = 'member';

            return {
              auth_user_id: u.id,
              email: u.email ?? null,
              created_at: u.created_at,
              last_sign_in_at: u.last_sign_in_at ?? null,
              email_confirmed: Boolean(u.email_confirmed_at),
              role,
              organizer: asBookie ? orgLabel(asBookie.id) : (primary ? orgLabel(primary.bookie_id) : null),
              member: primary ? memberLabel(primary.id) : null,
              balance_owed: primary ? (balanceByPlayer.get(String(primary.id).toLowerCase()) ?? 0) : null,
            };
          })
          .sort((a, b) => String(b.created_at).localeCompare(String(a.created_at)));

        return json({ view, rows, count: rows.length });
      }

      // ── Organizers and the size of their world ───────────────────────────
      case 'organizers': {
        const betRows = await selectAll(client, 'bets', 'bookie_id, status, stake, ticket_id');
        const picksByOrg = new Map<string, number>();
        const openByOrg = new Map<string, number>();
        for (const b of betRows as any[]) {
          const k = String(b.bookie_id ?? '').toLowerCase();
          picksByOrg.set(k, (picksByOrg.get(k) ?? 0) + 1);
          if (b.status === 'pending' || b.status === 'accepted') {
            openByOrg.set(k, (openByOrg.get(k) ?? 0) + 1);
          }
        }

        const rows = (bookies as any[])
          .filter((b) => !hideTest(b.email, b.name))
          .map((b) => {
            const k = String(b.id).toLowerCase();
            const mine = (players as any[]).filter((p) => String(p.bookie_id ?? '').toLowerCase() === k);
            const active = mine.filter((p) => p.status !== 'archived');
            const pendingInvites = (invites as any[]).filter(
              (i) => String(i.bookie_id ?? '').toLowerCase() === k && !i.claimed_at,
            );
            const owed = mine.reduce(
              (sum, p) => sum + (balanceByPlayer.get(String(p.id).toLowerCase()) ?? 0), 0,
            );
            return {
              id: b.id,
              name: b.name,
              email: b.email,
              tier: b.tier,
              subscription_status: b.subscription_status,
              subscription_source: b.subscription_source,
              created_at: b.created_at,
              members: active.length,
              members_archived: mine.length - active.length,
              pending_invites: pendingInvites.length,
              picks: picksByOrg.get(k) ?? 0,
              open_picks: openByOrg.get(k) ?? 0,
              balance_owed: Math.round(owed * 100) / 100,
              // The dormancy signal the follow-up email targets.
              dormant: active.length === 0 && pendingInvites.length === 0,
            };
          })
          .sort((a, b) => b.members - a.members || String(b.created_at).localeCompare(String(a.created_at)));

        return json({ view, rows, count: rows.length });
      }

      // ── Members, their organizer, their limits and their balance ─────────
      case 'members': {
        const rows = (players as any[])
          .filter((p) => !hideTest(p.email, p.name))
          .map((p) => {
            const owed = balanceByPlayer.get(String(p.id).toLowerCase()) ?? 0;
            return {
              id: p.id,
              name: p.display_name || p.name,
              email: p.email,
              status: p.status,
              claimed: Boolean(p.claimed_at),
              created_at: p.created_at,
              organizer: orgLabel(p.bookie_id),
              credit_limit: p.credit_limit,
              win_limit: p.win_limit,
              win_limit_action: p.win_limit_action,
              balance_owed: owed,
              linked: Boolean(p.auth_user_id),
            };
          })
          .sort((a, b) => Math.abs(b.balance_owed) - Math.abs(a.balance_owed));

        return json({ view, rows, count: rows.length });
      }

      // ── Invites that have not been claimed ───────────────────────────────
      case 'invites': {
        const now = Date.now();
        const rows = (invites as any[])
          .filter((i) => !i.claimed_at)
          .map((i) => {
            const expires = i.expires_at ? new Date(i.expires_at).getTime() : null;
            return {
              id: i.id,
              invite_code: i.invite_code,
              email: i.email,
              kind: i.email ? 'email' : 'code',
              created_at: i.created_at,
              expires_at: i.expires_at,
              expired: expires !== null && expires < now,
              age_days: i.created_at
                ? Math.floor((now - new Date(i.created_at).getTime()) / 86400000)
                : null,
              organizer: orgLabel(i.bookie_id),
            };
          })
          .filter((r) => includeTest || !hideTest(r.email, r.organizer?.name ?? null))
          .sort((a, b) => String(b.created_at).localeCompare(String(a.created_at)));

        return json({ view, rows, count: rows.length });
      }

      // ── Outstanding picks: anything not yet settled ──────────────────────
      case 'open_bets': {
        const betRows = (await selectAll(client, 'bets',
          'id, bookie_id, player_id, event_id, market, side, odds, stake, status, ' +
          'is_parlay, parlay_legs, ticket_id, created_at, grade_result',
        )) as any[];

        const open = betRows.filter((b) => b.status === 'pending' || b.status === 'accepted');

        // Resolve events for just the open picks rather than reading the whole
        // events table, which is far larger than everything else here.
        const eventIds = Array.from(new Set(open.map((b) => b.event_id).filter(Boolean)));
        const eventById = new Map<string, any>();
        for (let i = 0; i < eventIds.length; i += 200) {
          const chunk = eventIds.slice(i, i + 200);
          const { data } = await client
            .from('events')
            .select('id, away_team, home_team, start_time, status, away_score, home_score')
            .in('id', chunk);
          for (const e of data ?? []) eventById.set(String(e.id).toLowerCase(), e);
        }

        const rows = open
          .map((b) => {
            const e = b.event_id ? eventById.get(String(b.event_id).toLowerCase()) : null;
            return {
              id: b.id,
              status: b.status,
              stake: Number(b.stake) || 0,
              odds: b.odds,
              market: b.market,
              side: b.side,
              is_parlay: b.is_parlay,
              parlay_legs: b.parlay_legs,
              ticket_id: b.ticket_id,
              created_at: b.created_at,
              organizer: orgLabel(b.bookie_id),
              member: memberLabel(b.player_id),
              event: e
                ? {
                    id: e.id,
                    label: `${e.away_team} @ ${e.home_team}`,
                    start_time: e.start_time,
                    status: e.status,
                    score: e.away_score != null && e.home_score != null
                      ? `${e.away_score}-${e.home_score}` : null,
                  }
                : (b.event_id ? { id: b.event_id, label: null, missing: true } : null),
            };
          })
          .filter((r) => includeTest || !hideTest(r.member?.email ?? null, r.organizer?.name ?? null))
          .sort((a, b) => String(b.created_at).localeCompare(String(a.created_at)));

        const exposure = rows.reduce((s, r) => s + r.stake, 0);
        return json({ view, rows, count: rows.length, exposure: Math.round(exposure * 100) / 100 });
      }

      // ── Balances, with open stake alongside settled ledger ───────────────
      case 'balances': {
        const betRows = (await selectAll(client, 'bets', 'player_id, status, stake')) as any[];
        const openStake = new Map<string, number>();
        for (const b of betRows) {
          if (b.status !== 'pending' && b.status !== 'accepted') continue;
          const k = String(b.player_id ?? '').toLowerCase();
          openStake.set(k, (openStake.get(k) ?? 0) + (Number(b.stake) || 0));
        }

        const rows = (players as any[])
          .filter((p) => !hideTest(p.email, p.name))
          .map((p) => {
            const k = String(p.id).toLowerCase();
            const owed = balanceByPlayer.get(k) ?? 0;
            const open = openStake.get(k) ?? 0;
            const limit = Number(p.credit_limit) || 0;
            return {
              id: p.id,
              name: p.display_name || p.name,
              email: p.email,
              organizer: orgLabel(p.bookie_id),
              // Positive means the member owes the organizer; this is the
              // internal convention, not the negated player-facing one.
              balance_owed: owed,
              open_stake: Math.round(open * 100) / 100,
              credit_used: Math.round((owed + open) * 100) / 100,
              credit_limit: limit,
              utilisation: limit > 0 ? Math.round(((owed + open) / limit) * 100) : null,
            };
          })
          .filter((r) => r.balance_owed !== 0 || r.open_stake !== 0)
          .sort((a, b) => Math.abs(b.balance_owed) - Math.abs(a.balance_owed));

        const net = rows.reduce((s, r) => s + r.balance_owed, 0);
        return json({ view, rows, count: rows.length, net_owed: Math.round(net * 100) / 100 });
      }

      // ── Counts for the landing view ──────────────────────────────────────
      case 'overview': {
        const betRows = (await selectAll(client, 'bets', 'status, stake, bookie_id, player_id')) as any[];
        const realBookies = (bookies as any[]).filter((b) => !hideTest(b.email, b.name));
        const realPlayers = (players as any[]).filter((p) => !hideTest(p.email, p.name));
        const pendingInvites = (invites as any[]).filter((i) => !i.claimed_at);

        // The test filter has to reach the bets and the ledger too, not just
        // the account lists. Counting every bet here while the Outstanding
        // picks view counts only real ones made the two screens disagree —
        // 24 picks and $230 on the overview against 3 and $55 in the table —
        // and a number that contradicts the page it links to is worse than
        // no number at all.
        const realPlayerIds = new Set(realPlayers.map((p: any) => String(p.id).toLowerCase()));
        const realBookieIds = new Set(realBookies.map((b: any) => String(b.id).toLowerCase()));
        const isRealBet = (b: any) =>
          realPlayerIds.has(String(b.player_id ?? '').toLowerCase()) ||
          realBookieIds.has(String(b.bookie_id ?? '').toLowerCase());

        const open = betRows
          .filter((b) => b.status === 'pending' || b.status === 'accepted')
          .filter((b) => includeTest || isRealBet(b));
        const realBalances = (balances as any[]).filter(
          (b) => includeTest || realPlayerIds.has(String(b.player_id ?? '').toLowerCase()),
        );
        const realInvites = pendingInvites.filter(
          (i: any) => includeTest || realBookieIds.has(String(i.bookie_id ?? '').toLowerCase()),
        );

        return json({
          view,
          stats: {
            organizers: realBookies.length,
            organizers_pro: realBookies.filter((b) => b.tier === 'pro').length,
            organizers_dormant: realBookies.filter((b) => {
              const k = String(b.id).toLowerCase();
              const active = realPlayers.filter(
                (p) => String(p.bookie_id ?? '').toLowerCase() === k && p.status !== 'archived',
              ).length;
              const inv = realInvites.filter((i: any) => String(i.bookie_id ?? '').toLowerCase() === k).length;
              return active === 0 && inv === 0;
            }).length,
            members: realPlayers.filter((p) => p.status !== 'archived').length,
            members_unlinked: realPlayers.filter((p) => !p.auth_user_id).length,
            pending_invites: realInvites.length,
            expired_invites: realInvites.filter(
              (i) => i.expires_at && new Date(i.expires_at).getTime() < Date.now(),
            ).length,
            open_picks: open.length,
            open_exposure: Math.round(open.reduce((s, b) => s + (Number(b.stake) || 0), 0) * 100) / 100,
            net_owed: Math.round(
              realBalances.reduce((s, b) => s + (Number(b.balance_owed) || 0), 0) * 100,
            ) / 100,
          },
        });
      }

      // ── US-005: one box that finds a person, a game or a pick ────────────
      case 'search': {
        const q = (body.q ?? '').trim().toLowerCase();
        if (q.length < 2) return json({ view, groups: [], query: q });

        const hit = (hay: unknown) => String(hay ?? '').toLowerCase().includes(q);
        // A pasted UUID should resolve even though it matches no name. This is
        // the highest-value interaction in the whole tool: paste an id out of
        // a log line and learn what it is and whose it is.
        const isUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(q);

        const groups: Array<{ type: string; rows: unknown[] }> = [];

        const orgHits = (bookies as any[])
          .filter((b) => hit(b.name) || hit(b.email) || (isUuid && String(b.id).toLowerCase() === q))
          .slice(0, 25)
          .map((b) => ({ id: b.id, label: b.name, sub: b.email, tier: b.tier, route: `organizer/${b.id}` }));
        if (orgHits.length) groups.push({ type: 'Organizers', rows: orgHits });

        const memberHits = (players as any[])
          .filter((p) => hit(p.name) || hit(p.display_name) || hit(p.email) ||
                         (isUuid && (String(p.id).toLowerCase() === q ||
                                     String(p.auth_user_id ?? '').toLowerCase() === q)))
          .slice(0, 25)
          .map((p) => ({
            id: p.id,
            label: p.display_name || p.name,
            sub: p.email,
            organizer: orgLabel(p.bookie_id),
            route: `member/${p.id}`,
          }));
        if (memberHits.length) groups.push({ type: 'Members', rows: memberHits });

        // Events and bets are too large to hold in memory, so they are queried.
        const evQuery = isUuid
          ? client.from('events').select('id, away_team, home_team, start_time, status').eq('id', q)
          : client.from('events')
              .select('id, away_team, home_team, start_time, status')
              .or(`away_team.ilike.%${q}%,home_team.ilike.%${q}%`)
              .order('start_time', { ascending: false })
              .limit(25);
        const { data: evs } = await evQuery;
        if (evs?.length) {
          groups.push({
            type: 'Games',
            rows: evs.map((e: any) => ({
              id: e.id,
              label: `${e.away_team} @ ${e.home_team}`,
              sub: `${e.status} · ${e.start_time}`,
              route: null,
            })),
          });
        }

        if (isUuid) {
          // A UUID could also be a bet id or a whole parlay ticket.
          const { data: bets } = await client
            .from('bets')
            .select('id, player_id, bookie_id, side, market, stake, odds, status, ticket_id, created_at')
            .or(`id.eq.${q},ticket_id.eq.${q}`)
            .limit(25);
          if (bets?.length) {
            groups.push({
              type: 'Picks',
              rows: bets.map((b: any) => ({
                id: b.id,
                label: b.side || b.market || 'Pick',
                sub: `${b.status} · $${b.stake}`,
                organizer: orgLabel(b.bookie_id),
                member: memberLabel(b.player_id),
                route: `pick/${b.id}`,
              })),
            });
          }

          const invHit = (invites as any[]).filter((i) => String(i.id).toLowerCase() === q);
          if (invHit.length) {
            groups.push({
              type: 'Invites',
              rows: invHit.map((i) => ({
                id: i.id, label: i.invite_code, sub: i.email || 'shared code',
                organizer: orgLabel(i.bookie_id), route: null,
              })),
            });
          }
        }

        return json({ view, query: q, is_uuid: isUuid, groups });
      }

      // ── US-003: an organizer and their whole world ───────────────────────
      case 'organizer_detail': {
        const id = String(body.id ?? '').toLowerCase();
        const b: any = bookieById.get(id);
        if (!b) return json({ error: 'Organizer not found' }, 404);

        const mine = (players as any[]).filter((p) => String(p.bookie_id ?? '').toLowerCase() === id);
        const { data: bets } = await client
          .from('bets')
          .select('id, player_id, event_id, side, market, odds, stake, status, is_parlay, parlay_legs, ticket_id, created_at, grade_result')
          .eq('bookie_id', b.id)
          .order('created_at', { ascending: false })
          .limit(50);
        const { data: ledger } = await client
          .from('ledger_entries')
          .select('id, player_id, amount, type, description, created_at')
          .eq('bookie_id', b.id)
          .order('created_at', { ascending: false })
          .limit(50);

        return json({
          view,
          organizer: {
            ...b,
            members: mine.filter((p) => p.status !== 'archived').length,
            balance_owed: Math.round(
              mine.reduce((s, p) => s + (balanceByPlayer.get(String(p.id).toLowerCase()) ?? 0), 0) * 100) / 100,
          },
          members: mine.map((p) => ({
            id: p.id, name: p.display_name || p.name, email: p.email, status: p.status,
            credit_limit: p.credit_limit, win_limit: p.win_limit,
            balance_owed: balanceByPlayer.get(String(p.id).toLowerCase()) ?? 0,
          })),
          invites: (invites as any[])
            .filter((i) => String(i.bookie_id ?? '').toLowerCase() === id && !i.claimed_at)
            .map((i) => ({ id: i.id, invite_code: i.invite_code, email: i.email, expires_at: i.expires_at })),
          picks: (bets ?? []).map((x: any) => ({ ...x, member: memberLabel(x.player_id) })),
          ledger: (ledger ?? []).map((x: any) => ({ ...x, member: memberLabel(x.player_id) })),
        });
      }

      // ── US-004: trace one member without writing a join ──────────────────
      case 'member_detail': {
        const id = String(body.id ?? '').toLowerCase();
        const p: any = playerById.get(id);
        if (!p) return json({ error: 'Member not found' }, 404);

        const { data: bets } = await client
          .from('bets')
          .select('id, event_id, side, market, odds, stake, status, is_parlay, parlay_legs, ticket_id, created_at, grade_result')
          .eq('player_id', p.id)
          .order('created_at', { ascending: false })
          .limit(100);
        const { data: ledger } = await client
          .from('ledger_entries')
          .select('id, amount, type, description, created_at, bet_id')
          .eq('player_id', p.id)
          .order('created_at', { ascending: true });

        // Running balance, oldest first, so a number can be traced to the entry
        // that produced it rather than inferred from a total.
        let running = 0;
        const chain = (ledger ?? []).map((e: any) => {
          running += Number(e.amount) || 0;
          return { ...e, running_balance: Math.round(running * 100) / 100 };
        }).reverse();

        return json({
          view,
          member: {
            ...p,
            name: p.display_name || p.name,
            organizer: orgLabel(p.bookie_id),
            balance_owed: balanceByPlayer.get(id) ?? 0,
            open_stake: (bets ?? [])
              .filter((b: any) => b.status === 'pending' || b.status === 'accepted')
              .reduce((s: number, b: any) => s + (Number(b.stake) || 0), 0),
          },
          picks: bets ?? [],
          ledger: chain,
        });
      }

      // ── US-004: one pick, with its siblings if it is a parlay ────────────
      case 'pick_detail': {
        const id = String(body.id ?? '').toLowerCase();
        const { data: bet } = await client
          .from('bets')
          .select('*')
          .eq('id', id)
          .maybeSingle();
        if (!bet) return json({ error: 'Pick not found' }, 404);

        // Legs of a parlay are rows sharing a ticket_id, including this one.
        let legs: any[] = [];
        if (bet.ticket_id) {
          const { data } = await client.from('bets').select('*').eq('ticket_id', bet.ticket_id);
          legs = data ?? [];
        }

        const eventIds = Array.from(new Set([bet, ...legs].map((b) => b.event_id).filter(Boolean)));
        const eventById = new Map<string, any>();
        if (eventIds.length) {
          const { data } = await client
            .from('events')
            .select('id, away_team, home_team, start_time, status, away_score, home_score, league, sport')
            .in('id', eventIds);
          for (const e of data ?? []) eventById.set(String(e.id).toLowerCase(), e);
        }
        const withEvent = (b: any) => ({
          ...b,
          event: b.event_id
            ? (eventById.get(String(b.event_id).toLowerCase()) ?? { id: b.event_id, missing: true })
            : null,
        });

        const { data: ledger } = await client
          .from('ledger_entries')
          .select('id, amount, type, description, created_at')
          .eq('bet_id', bet.id);

        return json({
          view,
          pick: {
            ...withEvent(bet),
            organizer: orgLabel(bet.bookie_id),
            member: memberLabel(bet.player_id),
          },
          legs: legs.filter((l) => l.id !== bet.id).map(withEvent),
          ledger: ledger ?? [],
        });
      }

      // ── US-007: the integrity checks that have already caught real bugs ──
      case 'data_quality': {
        // Expressed as SQL rather than pulled into memory: these are aggregate
        // questions over the events and bets tables, which are far larger than
        // everything else this function reads.
        const checks: Array<{ key: string; label: string; note: string; sql: string }> = [
          {
            key: 'duplicate_events',
            label: 'Duplicate events by external_id',
            note: 'Should be 0 since migration 032 added the unique index. Mass duplication once put 25,133 rows behind 5,964 real games.',
            sql: `SELECT external_id, count(*) AS copies, min(created_at) AS first_seen
                  FROM events WHERE external_id IS NOT NULL
                  GROUP BY external_id HAVING count(*) > 1
                  ORDER BY count(*) DESC`,
          },
          {
            key: 'orphan_bets',
            label: 'Picks referencing a missing event',
            note: 'A pick whose event row is gone cannot be graded or displayed.',
            sql: `SELECT b.id, b.bookie_id, b.player_id, b.event_id, b.status, b.stake, b.created_at
                  FROM bets b LEFT JOIN events e ON e.id = b.event_id
                  WHERE b.event_id IS NOT NULL AND e.id IS NULL
                  ORDER BY b.created_at DESC`,
          },
          {
            key: 'markets_on_final',
            label: 'Markets still attached to finished games',
            note: 'The prune sweep should keep this near 0; growth means a finalisation path is not being swept.',
            sql: `SELECT m.id, m.event_id, m.type, e.away_team, e.home_team, e.status
                  FROM markets m JOIN events e ON e.id = m.event_id
                  WHERE e.status = 'final' AND e.away_team <> 'Outright'
                  ORDER BY m.updated_at DESC`,
          },
          {
            key: 'stale_scheduled',
            label: 'Games past start still marked scheduled',
            note: 'Either the score refresh missed them or they never started. Members can still see them as bettable.',
            sql: `SELECT id, away_team, home_team, start_time, status, league
                  FROM events
                  WHERE status = 'scheduled' AND start_time < now() - interval '6 hours'
                    AND away_team <> 'Outright'
                  ORDER BY start_time DESC`,
          },
          {
            key: 'unlinked_accounts',
            label: 'Accounts that are neither organizer nor member',
            note: 'Signed up and stranded — the shape that left three invitees as their own organizers in August.',
            sql: `SELECT u.id, u.email, u.created_at, u.last_sign_in_at
                  FROM auth.users u
                  LEFT JOIN bookies b ON b.auth_user_id = u.id
                  LEFT JOIN players p ON p.auth_user_id = u.id
                  WHERE b.id IS NULL AND p.id IS NULL
                  ORDER BY u.created_at DESC`,
          },
        ];

        const results = [];
        for (const c of checks) {
          const { data, error } = await client.rpc('admin_run_select', {
            p_query: c.sql, p_max_rows: 100,
          });
          if (error) {
            results.push({ ...c, sql: undefined, error: error.message, unavailable: true });
            continue;
          }
          results.push({
            key: c.key, label: c.label, note: c.note,
            error: (data as any)?.error ?? null,
            count: (data as any)?.row_count ?? 0,
            truncated: (data as any)?.truncated ?? false,
            rows: (data as any)?.rows ?? [],
          });
        }

        // The hash chain has its own validator from migration 018; run it for
        // every ledger that actually has entries.
        const { data: chainPairs, error: pairsError } = await client
          .rpc('admin_run_select', {
            p_query: `SELECT DISTINCT bookie_id, player_id FROM ledger_entries`,
            p_max_rows: 500,
          });
        const bad: unknown[] = [];
        let checked = 0;
        // A check that could not run must not report clean. Without this the
        // pair list came back empty from a failed RPC and the chain check
        // announced "0 problems" having verified nothing — the most dangerous
        // possible output for an integrity check.
        if (pairsError) {
          results.push({
            key: 'ledger_chain',
            label: 'Ledger hash-chain validity',
            note: 'Could not run — the ledger pair list is unavailable.',
            error: pairsError.message,
            unavailable: true,
            count: null,
            rows: [],
          });
          return json({ view, checks: results });
        }
        for (const pair of ((chainPairs as any)?.rows ?? [])) {
          const { data: verdict } = await client.rpc('validate_ledger_chain', {
            p_bookie_id: pair.bookie_id, p_player_id: pair.player_id,
          });
          checked++;
          if (verdict && (verdict as any).valid === false) {
            bad.push({ ...pair, ...(verdict as any), member: memberLabel(pair.player_id), organizer: orgLabel(pair.bookie_id) });
          }
        }
        results.push({
          key: 'ledger_chain',
          label: 'Ledger hash-chain validity',
          note: `Tamper-evident chain from migration 017/018. ${checked} ledgers checked.`,
          count: bad.length,
          rows: bad,
        });

        return json({ view, checks: results });
      }

      // ── US-006: the escape hatch ─────────────────────────────────────────
      case 'sql': {
        const sqlText = String(body.sql ?? '').trim();
        if (!sqlText) return json({ error: 'Empty query' }, 400);

        const out = await runReadOnly(sqlText, Math.min(Number(body.max_rows) || 500, 5000));

        // If the connection is unavailable the query is NOT quietly run
        // through the weaker path — that would silently drop the control the
        // page tells the operator is protecting them.
        if ((out as any).no_connection) {
          return json({
            error: 'Read-only connection unavailable, so the query was not run.',
            no_connection: true,
          }, 503);
        }
        return json({ view, ...out });
      }

      // ── Odds API market discovery + cost measurement (PRD US-001) ────────
      //
      // Answers "what markets can we actually sell, and what would they cost"
      // with measurements instead of estimates. The last attempt to reason
      // about Odds API cost was ~40% high, so every number here comes from the
      // x-requests-last header on a real response.
      //
      // This SPENDS CREDITS. Discovery is 1 credit per event; a cost probe is
      // (markets returned x regions) per event. Both are bounded below.
      case 'odds_probe': {
        const apiKey = Deno.env.get('ODDS_API_KEY');
        if (!apiKey) return json({ error: 'ODDS_API_KEY not set' }, 500);

        const sportKey = String(body.sport_key ?? 'americanfootball_nfl');
        const region = 'us';
        const base = 'https://api.the-odds-api.com/v4/sports';

        // Resolve one real, upcoming event to probe against.
        const evRes = await fetch(`${base}/${sportKey}/events?apiKey=${apiKey}`);
        const evCost = Number(evRes.headers.get('x-requests-last') ?? 0);
        if (!evRes.ok) {
          return json({ error: `events lookup failed: ${evRes.status}`, detail: await evRes.text() }, 502);
        }
        const events = await evRes.json();
        if (!Array.isArray(events) || events.length === 0) {
          return json({ error: `no upcoming events for ${sportKey}` }, 404);
        }
        const target = events[0];

        // 1 credit: which market keys does each bookmaker currently offer?
        const mkRes = await fetch(
          `${base}/${sportKey}/events/${target.id}/markets?apiKey=${apiKey}&regions=${region}`,
        );
        const mkCost = Number(mkRes.headers.get('x-requests-last') ?? 0);
        const mkBody = mkRes.ok ? await mkRes.json() : null;

        // Flatten to a distinct key list with how many books offer each — a key
        // one book quotes is not the same product as one twenty books quote.
        const byKey = new Map<string, number>();
        for (const bm of (mkBody?.bookmakers ?? [])) {
          for (const m of (bm.markets ?? [])) {
            byKey.set(m.key, (byKey.get(m.key) ?? 0) + 1);
          }
        }
        const available = Array.from(byKey.entries())
          .map(([key, books]) => ({ key, books }))
          .sort((a, b) => b.books - a.books || a.key.localeCompare(b.key));

        // Raw bundle, on request, so the sync mapper can be exercised offline
        // against a genuine payload instead of a hand-written fixture.
        let rawBundle: unknown = null;
        if (body.return_payload === true) {
          const rawRes = await fetch(
            `${base}/${sportKey}/events/${target.id}/odds/?apiKey=${apiKey}&regions=${region}` +
            `&markets=alternate_spreads,alternate_totals,team_totals,odd_even&oddsFormat=american`,
          );
          rawBundle = rawRes.ok ? await rawRes.json() : { error: await rawRes.text() };
        }

        const result: Record<string, unknown> = {
          raw_bundle: rawBundle,
          sport_key: sportKey,
          event: { id: target.id, label: `${target.away_team} @ ${target.home_team}`,
                   start: target.commence_time },
          discovery_credits: evCost + mkCost,
          markets_available: available,
          markets_count: available.length,
        };

        // Optional cost probe: only when explicitly asked, since it spends more.
        if (Array.isArray(body.market_sets) && body.market_sets.length) {
          const measured = [];
          for (const set of body.market_sets.slice(0, 8)) {
            const markets = String(set.markets ?? '');
            if (!markets) continue;
            const url = set.per_event === false
              ? `${base}/${sportKey}/odds?apiKey=${apiKey}&regions=${region}&markets=${markets}`
              : `${base}/${sportKey}/events/${target.id}/odds?apiKey=${apiKey}&regions=${region}&markets=${markets}`;
            const res = await fetch(url);
            const text = await res.text();
            let returnedMarkets = 0;
            // Distinct (market, line) pairs, because that is what a stored row
            // is: markets are keyed event + type + LINE VALUE, so one
            // alternate_spreads market becomes as many rows as it has lines.
            // Credits measure the API bill; rows measure the Supabase one, and
            // egress is the constraint that has already been breached once.
            let distinctLines = 0;
            try {
              const parsed = JSON.parse(text);
              const rows = Array.isArray(parsed) ? parsed : [parsed];
              const keys = new Set<string>();
              const lines = new Set<string>();
              for (const row of rows) {
                for (const bm of (row?.bookmakers ?? [])) {
                  for (const m of (bm.markets ?? [])) {
                    keys.add(m.key);
                    for (const o of (m.outcomes ?? [])) {
                      lines.add(`${m.key}|${o.description ?? ''}|${o.point ?? ''}`);
                    }
                  }
                }
              }
              returnedMarkets = keys.size;
              distinctLines = lines.size;
            } catch { /* error body */ }

            measured.push({
              label: set.label ?? markets,
              per_event: set.per_event !== false,
              requested: markets.split(',').length,
              returned_markets: returnedMarkets,
              rows_per_game: distinctLines,
              status: res.status,
              credits: Number(res.headers.get('x-requests-last') ?? 0),
              bytes: text.length,
              remaining: Number(res.headers.get('x-requests-remaining') ?? 0),
              error: res.ok ? null : text.slice(0, 200),
            });
          }
          result.cost_probes = measured;
        }

        return json({ view, ...result });
      }

      default:
        return json({ error: `Unknown view: ${view}` }, 400);
    }
  } catch (error) {
    console.error('admin_query error:', error);
    return json({ error: error instanceof Error ? error.message : 'Internal error' }, 500);
  }
});
