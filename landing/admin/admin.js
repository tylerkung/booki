/**
 * Booki platform admin — read-only browser.
 *
 * Every request goes through the admin_query edge function, which resolves the
 * caller's email from their JWT and checks it against a server-side allowlist.
 * Nothing in this file is access control: hiding a nav item in a SPA is not
 * security, and the gate below exists only so a non-admin sees an explanation
 * instead of a broken page.
 */

const SUPABASE_URL = 'https://vstfauqufwpdytmvjyfz.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZzdGZhdXF1ZndwZHl0bXZqeWZ6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjkyMjcwNjcsImV4cCI6MjA4NDgwMzA2N30.uwimFkR3pN8BODjjM5KnusptdZz_vcrxKnK_2LKfZHI';

const money = (n) => {
    if (n === null || n === undefined || n === '') return '—';
    const v = Number(n);
    if (!Number.isFinite(v)) return '—';
    return (v < 0 ? '-$' : '$') + Math.abs(v).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
};
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]
));
const date = (s) => {
    if (!s) return '—';
    const d = new Date(s);
    return Number.isNaN(d.getTime()) ? '—'
        : d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: '2-digit' });
};
const dateTime = (s) => {
    if (!s) return '—';
    const d = new Date(s);
    return Number.isNaN(d.getTime()) ? '—'
        : d.toLocaleString('en-US', { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' });
};
const odds = (n) => (n === null || n === undefined ? '—' : (Number(n) > 0 ? '+' : '') + n);

/** A UUID, shown short but copyable in full. This is the escape hatch back to
 *  Supabase Studio or a log line, so the full value has to survive. */
const uuid = (id) => id
    ? `<code class="admin-uuid" title="${esc(id)}" data-copy="${esc(id)}">${esc(String(id).slice(0, 8))}</code>`
    : '—';

/** US-002: a foreign key renders as a human label, never a bare UUID — and
 *  every resolved label is a link to that record's own view. `kind` is the
 *  detail route it belongs to; omit it for entities with no page yet. */
const entity = (e, fallback = '—', kind = null) => {
    if (!e) return fallback;
    if (e.missing) return `<span class="admin-missing" title="${esc(e.id)}">missing event</span>`;
    const name = e.name || e.label;
    if (!name) return uuid(e.id);
    const sub = e.email && e.email !== name ? `<span class="admin-sub">${esc(e.email)}</span>` : '';
    const inner = `${esc(name)}${sub}`;
    return kind && e.id
        ? `<a class="admin-entity admin-link" href="#/${kind}/${esc(e.id)}">${inner}</a>`
        : `<span class="admin-entity">${inner}</span>`;
};

const badge = (text, tone = 'muted') =>
    `<span class="badge badge-${tone}">${esc(text)}</span>`;

const VIEWS = [
    {
        id: 'overview', label: 'Overview', columns: [],
    },
    {
        id: 'users', label: 'Users',
        columns: [
            { key: 'email', label: 'Email' },
            { key: 'role', label: 'Role', render: (r) => {
                const tone = r.role === 'organizer' ? 'accent'
                    : r.role === 'member' ? 'success'
                    : r.role === 'unlinked' ? 'warning' : 'danger';
                return badge(r.role, tone);
            } },
            { key: 'organizer', label: 'Organizer', render: (r) => entity(r.organizer, '—', 'organizer') },
            { key: 'balance_owed', label: 'Balance', render: (r) => r.balance_owed === null ? '—' : money(r.balance_owed), numeric: true },
            { key: 'email_confirmed', label: 'Verified', render: (r) => r.email_confirmed ? '✓' : badge('no', 'warning') },
            { key: 'last_sign_in_at', label: 'Last seen', render: (r) => date(r.last_sign_in_at) },
            { key: 'created_at', label: 'Joined', render: (r) => date(r.created_at) },
            { key: 'auth_user_id', label: 'ID', render: (r) => uuid(r.auth_user_id) },
        ],
    },
    {
        id: 'organizers', label: 'Organizers',
        columns: [
            { key: 'name', label: 'Organizer', render: (r) => entity({ id: r.id, name: r.name, email: r.email }, '—', 'organizer') },
            { key: 'tier', label: 'Tier', render: (r) => badge(r.tier || 'free', r.tier === 'pro' ? 'accent' : 'muted') },
            { key: 'members', label: 'Members', numeric: true },
            { key: 'pending_invites', label: 'Invites', numeric: true },
            { key: 'open_picks', label: 'Open', numeric: true },
            { key: 'picks', label: 'Picks', numeric: true },
            { key: 'balance_owed', label: 'Owed', render: (r) => money(r.balance_owed), numeric: true },
            { key: 'dormant', label: 'State', render: (r) => r.dormant ? badge('dormant', 'warning') : badge('active', 'success') },
            { key: 'created_at', label: 'Created', render: (r) => date(r.created_at) },
        ],
    },
    {
        id: 'members', label: 'Members',
        columns: [
            { key: 'name', label: 'Member', render: (r) => entity({ id: r.id, name: r.name, email: r.email }, '—', 'member') },
            { key: 'organizer', label: 'Organizer', render: (r) => entity(r.organizer, '—', 'organizer') },
            { key: 'status', label: 'Status', render: (r) => badge(r.status || '—', r.status === 'active' ? 'success' : 'muted') },
            { key: 'linked', label: 'Linked', render: (r) => r.linked ? '✓' : badge('no account', 'warning') },
            { key: 'balance_owed', label: 'Balance', render: (r) => money(r.balance_owed), numeric: true },
            { key: 'credit_limit', label: 'Credit', render: (r) => money(r.credit_limit), numeric: true },
            { key: 'win_limit', label: 'Win limit', render: (r) => r.win_limit == null ? '—' : money(r.win_limit), numeric: true },
            { key: 'created_at', label: 'Joined', render: (r) => date(r.created_at) },
        ],
    },
    {
        id: 'invites', label: 'Pending invites',
        columns: [
            { key: 'invite_code', label: 'Code', render: (r) => `<code class="admin-uuid" data-copy="${esc(r.invite_code)}">${esc(r.invite_code)}</code>` },
            { key: 'kind', label: 'Kind', render: (r) => badge(r.kind, r.kind === 'email' ? 'accent' : 'muted') },
            { key: 'email', label: 'Sent to', render: (r) => r.email ? esc(r.email) : '<span class="admin-sub">shared code</span>' },
            { key: 'organizer', label: 'Organizer', render: (r) => entity(r.organizer, '—', 'organizer') },
            { key: 'age_days', label: 'Age', render: (r) => r.age_days == null ? '—' : `${r.age_days}d`, numeric: true },
            { key: 'expired', label: 'State', render: (r) => r.expired ? badge('expired', 'danger') : badge('pending', 'warning') },
            { key: 'expires_at', label: 'Expires', render: (r) => date(r.expires_at) },
        ],
    },
    {
        id: 'open_bets', label: 'Outstanding picks',
        columns: [
            { key: 'member', label: 'Member', render: (r) => entity(r.member, '—', 'member') },
            { key: 'organizer', label: 'Organizer', render: (r) => entity(r.organizer, '—', 'organizer') },
            { key: 'side', label: 'Pick', render: (r) => {
                const legs = r.is_parlay ? `<span class="admin-sub">${r.parlay_legs}-leg multi</span>` : '';
                return `<span class="admin-entity">${esc(r.side || r.market || '—')}${legs}</span>`;
            } },
            { key: 'event', label: 'Game', render: (r) => entity(r.event) },
            { key: 'odds', label: 'Odds', render: (r) => odds(r.odds), numeric: true },
            { key: 'stake', label: 'Stake', render: (r) => money(r.stake), numeric: true },
            { key: 'status', label: 'Status', render: (r) => badge(r.status, r.status === 'pending' ? 'warning' : 'success') },
            { key: 'created_at', label: 'Placed', render: (r) => dateTime(r.created_at) },
        ],
    },
    {
        id: 'balances', label: 'Balances',
        columns: [
            { key: 'name', label: 'Member', render: (r) => entity({ id: r.id, name: r.name, email: r.email }, '—', 'member') },
            { key: 'organizer', label: 'Organizer', render: (r) => entity(r.organizer, '—', 'organizer') },
            { key: 'balance_owed', label: 'Settled', render: (r) => money(r.balance_owed), numeric: true },
            { key: 'open_stake', label: 'Open stake', render: (r) => money(r.open_stake), numeric: true },
            { key: 'credit_used', label: 'Credit used', render: (r) => money(r.credit_used), numeric: true },
            { key: 'credit_limit', label: 'Limit', render: (r) => money(r.credit_limit), numeric: true },
            { key: 'utilisation', label: 'Used %', render: (r) => {
                if (r.utilisation == null) return '—';
                const tone = r.utilisation >= 90 ? 'danger' : r.utilisation >= 70 ? 'warning' : 'muted';
                return badge(r.utilisation + '%', tone);
            }, numeric: true },
        ],
    },
];

const TITLES = {
    organizer: 'Organizer', member: 'Member', pick: 'Pick',
    search: 'Search', data_quality: 'Data quality', sql: 'SQL',
};

function adminApp() {
    return {
        // exposed so the template can format without duplicating helpers
        fmt: { money, date, dateTime, odds, esc, entity, badge, uuid },

        supabase: null,
        session: null,
        adminEmail: '',
        gate: '',
        loading: false,
        includeTest: false,

        views: VIEWS,
        route: 'overview',
        routeId: null,
        detail: null,
        searchGroups: [],
        searchTerm: '',
        checks: [],
        sqlText: 'select status, count(*)\nfrom bets\ngroup by status\norder by 2 desc',
        sqlResult: null,
        rows: [],
        stats: null,
        meta: {},
        query: '',
        sort: { key: null, dir: -1 },
        page: 1,
        pageSize: 100,
        toasts: [],

        async init() {
            this.supabase = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
            const { data } = await this.supabase.auth.getSession();
            this.session = data.session;

            if (!this.session) {
                this.gate = 'Sign in on the dashboard first — this page uses the same session.';
                return;
            }
            this.adminEmail = this.session.user.email || '';

            this.applyHash();
            window.addEventListener('hashchange', () => {
                this.applyHash();
                this.query = '';
                this.page = 1;
                this.sort = { key: null, dir: -1 };
                this.load();
            });

            // One click anywhere handles every copyable cell, rather than a
            // listener per row — the table re-renders constantly.
            document.addEventListener('click', (e) => {
                const el = e.target.closest('[data-copy]');
                if (!el) return;
                navigator.clipboard.writeText(el.dataset.copy);
                this.toast('Copied ' + el.dataset.copy);
            });

            await this.load();
        },

        /** A hash is either a view (#/members) or a record (#/member/<uuid>). */
        applyHash() {
            const raw = window.location.hash.replace(/^#\//, '');
            const [head, ...rest] = raw.split('/');
            this.route = head || 'overview';
            this.routeId = rest.join('/') || null;
        },

        get currentView() {
            return VIEWS.find((v) => v.id === this.route) || { id: this.route, label: TITLES[this.route] || this.route, columns: [] };
        },

        get isTableView() {
            return VIEWS.some((v) => v.id === this.route) && this.route !== 'overview';
        },

        async post(view, extra = {}) {
            return fetch(`${SUPABASE_URL}/functions/v1/admin_query`, {
                method: 'POST',
                headers: {
                    'Authorization': `Bearer ${this.session.access_token}`,
                    'apikey': SUPABASE_ANON_KEY,
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({ view, include_test: this.includeTest, ...extra }),
            });
        },

        /** Route name -> the edge function view and its parameters. */
        requestFor() {
            switch (this.route) {
                case 'organizer': return ['organizer_detail', { id: this.routeId }];
                case 'member':    return ['member_detail', { id: this.routeId }];
                case 'pick':      return ['pick_detail', { id: this.routeId }];
                case 'search':    return ['search', { q: this.searchTerm }];
                case 'sql':       return ['sql', { sql: this.sqlText }];
                default:          return [this.route, {}];
            }
        },

        async load() {
            this.loading = true;
            try {
                const [view, extra] = this.requestFor();

                // The SQL runner must not fire on navigation — it only runs
                // when the operator asks for it.
                if (view === 'sql' && !this._runSql) { this.loading = false; return; }
                if (view === 'search' && !this.searchTerm) {
                    this.searchGroups = []; this.loading = false; return;
                }

                let res = await this.post(view, extra);

                // 401 and 404 mean different things and must not share a
                // branch. A Supabase access token lasts an hour, so leaving
                // this page open past that returns 401 — which said "not an
                // admin" and locked the operator out of their own tool until
                // they reloaded. Refresh once and retry; only a second 401 is
                // really an auth failure.
                if (res.status === 401) {
                    const { data } = await this.supabase.auth.refreshSession();
                    if (data?.session) {
                        this.session = data.session;
                        res = await this.post(this.route);
                    }
                }

                if (res.status === 401) {
                    this.gate = 'Your session expired. Sign in again on the dashboard.';
                    return;
                }
                // 404 is the allowlist rejecting this caller — deliberately
                // indistinguishable from the endpoint not existing.
                if (res.status === 404) {
                    this.gate = 'This account does not have admin access.';
                    return;
                }

                const body = await res.json();

                // The SQL runner reports its own errors in the results pane —
                // a syntax error is an expected outcome there, not a failure
                // of the page.
                if (view === 'sql') { this.sqlResult = body; return; }
                if (body.error) throw new Error(body.error);

                if (view === 'search') { this.searchGroups = body.groups || []; return; }
                if (view === 'data_quality') { this.checks = body.checks || []; return; }
                if (view.endsWith('_detail')) { this.detail = body; return; }

                this.rows = body.rows || [];
                this.stats = body.stats || null;
                this.meta = { exposure: body.exposure, net_owed: body.net_owed, count: body.count };
            } catch (err) {
                console.error('admin load failed:', err);
                this.toast(err.message || 'Load failed', 'error');
            } finally {
                this.loading = false;
            }
        },

        get overviewTiles() {
            const s = this.stats;
            if (!s) return [];
            return [
                { label: 'Organizers', value: s.organizers, sub: `${s.organizers_pro} on Pro` },
                { label: 'Dormant', value: s.organizers_dormant, sub: 'no members, no invites',
                  tone: s.organizers_dormant ? 'negative' : '' },
                { label: 'Members', value: s.members, sub: `${s.members_unlinked} never linked an account` },
                { label: 'Pending invites', value: s.pending_invites, sub: `${s.expired_invites} expired`,
                  tone: s.expired_invites ? 'negative' : '' },
                { label: 'Open picks', value: s.open_picks, sub: 'pending or accepted' },
                { label: 'Open exposure', value: money(s.open_exposure), sub: 'total stake at risk' },
                { label: 'Net owed', value: money(s.net_owed), sub: 'across every ledger',
                  tone: s.net_owed >= 0 ? 'positive' : 'negative' },
            ];
        },

        get summaryLine() {
            const n = this.filtered.length;
            const parts = [`${n} ${n === 1 ? 'row' : 'rows'}`];
            if (this.route === 'open_bets' && this.meta.exposure != null) {
                parts.push(`${money(this.filtered.reduce((s, r) => s + r.stake, 0))} at risk`);
            }
            if (this.route === 'balances') {
                parts.push(`${money(this.filtered.reduce((s, r) => s + r.balance_owed, 0))} net owed`);
            }
            return parts.join(' · ');
        },

        /** Free-text filter across every rendered value, so pasting a UUID from
         *  a log line finds its row without knowing which column it lives in. */
        get filtered() {
            const q = this.query.trim().toLowerCase();
            let out = this.rows;
            if (q) {
                out = out.filter((r) => JSON.stringify(r).toLowerCase().includes(q));
            }
            if (this.sort.key) {
                const k = this.sort.key;
                out = [...out].sort((a, b) => {
                    const av = a[k], bv = b[k];
                    const an = typeof av === 'number', bn = typeof bv === 'number';
                    if (an && bn) return (av - bv) * this.sort.dir;
                    const as = av && typeof av === 'object' ? (av.name || av.label || '') : String(av ?? '');
                    const bs = bv && typeof bv === 'object' ? (bv.name || bv.label || '') : String(bv ?? '');
                    return as.localeCompare(bs) * this.sort.dir;
                });
            }
            return out;
        },

        get totalPages() {
            return Math.max(1, Math.ceil(this.filtered.length / this.pageSize));
        },

        get paged() {
            const start = (this.page - 1) * this.pageSize;
            return this.filtered.slice(start, start + this.pageSize);
        },

        sortBy(key) {
            if (this.sort.key === key) this.sort.dir *= -1;
            else this.sort = { key, dir: -1 };
        },

        cell(row, col) {
            try {
                return col.render ? col.render(row) : esc(row[col.key] ?? '—');
            } catch (err) {
                console.error('cell render failed', col.key, err);
                return '—';
            }
        },

        exportCsv() {
            const cols = this.currentView.columns;
            const flat = (v) => {
                if (v === null || v === undefined) return '';
                if (typeof v === 'object') return v.name || v.label || v.id || '';
                return String(v);
            };
            const lines = [cols.map((c) => c.label).join(',')];
            for (const r of this.filtered) {
                lines.push(cols.map((c) => {
                    const cell = flat(r[c.key]);
                    return /[",\n]/.test(cell) ? `"${cell.replace(/"/g, '""')}"` : cell;
                }).join(','));
            }
            const blob = new Blob([lines.join('\n')], { type: 'text/csv' });
            const a = document.createElement('a');
            a.href = URL.createObjectURL(blob);
            a.download = `booki-${this.route}-${new Date().toISOString().slice(0, 10)}.csv`;
            a.click();
            URL.revokeObjectURL(a.href);
        },

        async runSql() {
            this._runSql = true;
            try { await this.load(); } finally { this._runSql = false; }
        },

        async runSearch() {
            window.location.hash = '#/search';
            await this.load();
        },

        toast(message, type = 'success') {
            const id = Date.now() + Math.random();
            this.toasts.push({ id, message, type, visible: true });
            setTimeout(() => {
                const t = this.toasts.find((x) => x.id === id);
                if (t) t.visible = false;
            }, 2500);
            setTimeout(() => { this.toasts = this.toasts.filter((x) => x.id !== id); }, 2800);
        },
    };
}
