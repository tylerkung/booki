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

      default:
        return json({ error: `Unknown view: ${view}` }, 400);
    }
  } catch (error) {
    console.error('admin_query error:', error);
    return json({ error: error instanceof Error ? error.message : 'Internal error' }, 500);
  }
});
