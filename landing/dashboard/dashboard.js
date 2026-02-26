/**
 * Booki Web Dashboard — Core JS
 * Alpine.js data store + Supabase client
 */

const SUPABASE_URL = 'https://vstfauqufwpdytmvjyfz.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZzdGZhdXF1ZndwZHl0bXZqeWZ6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjkyMjcwNjcsImV4cCI6MjA4NDgwMzA2N30.uwimFkR3pN8BODjjM5KnusptdZz_vcrxKnK_2LKfZHI';

function dashboardApp() {
    return {
        // ── Auth ──
        supabase: null,
        session: null,
        bookie: null,

        // ── Route ──
        route: 'dashboard',
        sidebarOpen: false,
        selectedPlayerId: null,
        selectedBetId: null,

        // ── Dashboard ──
        timeFilter: 'All',
        pnl: 0,
        activeMemberCount: 0,
        openPickCount: 0,
        totalVolume: 0,
        recentActivity: [],

        // ── Members ──
        players: [],
        playerMap: {},
        memberSearch: '',

        // ── Picks ──
        bets: [],
        pickFilter: 'open',
        pickMemberFilter: '',
        pickTypeFilter: '',

        // ── Subscription ──
        isPro: false,
        isCheckingOut: false,
        isOpeningPortal: false,
        subscriptionSuccess: false,
        subscriptionCanceled: false,

        // ── Pick Detail ──
        pickDetail: null,
        isLoadingPickDetail: false,

        // ── Modals ──
        showInviteModal: false,
        inviteEmail: '',
        inviteCreditLimit: 1000,
        inviteCode: '',
        inviteError: '',
        isCreatingInvite: false,

        showSettleModal: false,
        settlePlayer: null,
        settleError: '',
        isSettling: false,

        showAdjustModal: false,
        adjustPlayer: null,
        adjustAmount: '',
        adjustReason: '',
        adjustError: '',
        isAdjusting: false,

        // ── Toasts ──
        toasts: [],

        // ── Init ──
        async init() {
            if (!SUPABASE_ANON_KEY) {
                console.error('Supabase anon key not configured');
                window.location.href = 'index.html';
                return;
            }

            this.supabase = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

            // Check session
            const { data: { session } } = await this.supabase.auth.getSession();
            if (!session) {
                window.location.href = 'index.html';
                return;
            }
            this.session = session;

            // Listen for auth changes
            this.supabase.auth.onAuthStateChange((event, session) => {
                this.session = session;
                if (!session) window.location.href = 'index.html';
            });

            // Load bookie
            await this.loadBookie();
            if (!this.bookie) {
                window.location.href = 'index.html';
                return;
            }

            // Parse route
            this.parseRoute();
            window.addEventListener('hashchange', () => this.parseRoute());

            // Check subscription redirect params
            const params = new URLSearchParams(window.location.hash.split('?')[1] || '');
            if (params.get('success') === 'true') this.subscriptionSuccess = true;
            if (params.get('canceled') === 'true') this.subscriptionCanceled = true;

            // Load data
            await this.loadPlayers();
            await this.loadDashboard();
        },

        // ── Routing ──
        parseRoute() {
            const hash = window.location.hash.replace(/\?.*$/, '');
            const path = hash.replace('#/', '') || 'dashboard';

            // Check parameterized routes
            const memberMatch = path.match(/^members\/(.+)$/);
            const pickMatch = path.match(/^picks\/(.+)$/);

            if (memberMatch) {
                this.route = 'member-detail';
                this.selectedPlayerId = memberMatch[1];
            } else if (pickMatch) {
                this.route = 'pick-detail';
                this.selectedBetId = pickMatch[1];
            } else {
                const routes = ['dashboard', 'members', 'picks', 'subscription', 'settings'];
                this.route = routes.includes(path) ? path : 'dashboard';
                this.selectedPlayerId = null;
                this.selectedBetId = null;
            }

            // Load route-specific data
            if (this.route === 'picks') this.loadPicks();
            if (this.route === 'pick-detail') this.loadPickDetail();
        },

        // ── Auth ──
        async logout() {
            await this.supabase.auth.signOut();
            window.location.href = 'index.html';
        },

        // ── Load Bookie ──
        async loadBookie() {
            const { data, error } = await this.supabase
                .from('bookies')
                .select('*')
                .eq('auth_user_id', this.session.user.id)
                .limit(1);

            if (error || !data?.length) {
                console.error('Failed to load bookie:', error);
                return;
            }

            this.bookie = data[0];
            this.isPro = this.bookie.tier === 'pro';
        },

        // ── Load Players ──
        async loadPlayers() {
            if (!this.bookie) return;

            const { data, error } = await this.supabase
                .from('players')
                .select('*')
                .eq('bookie_id', this.bookie.id)
                .order('name');

            if (error) {
                console.error('Failed to load players:', error);
                return;
            }

            this.players = data || [];
            this.playerMap = {};
            for (const p of this.players) {
                this.playerMap[p.id] = p;
            }

            this.activeMemberCount = this.players.filter(p => p.auth_user_id && p.status === 'active').length;

            // Load balances
            await this.loadPlayerBalances();
        },

        async loadPlayerBalances() {
            if (!this.bookie) return;

            const { data, error } = await this.supabase
                .from('ledger_entries')
                .select('player_id, amount')
                .eq('bookie_id', this.bookie.id);

            if (error) return;

            // Sum balances per player
            const balances = {};
            for (const entry of (data || [])) {
                balances[entry.player_id] = (balances[entry.player_id] || 0) + (entry.amount || 0);
            }

            for (const p of this.players) {
                p.balance = balances[p.id] || 0;
            }
        },

        // ── Dashboard Data ──
        async loadDashboard() {
            if (!this.bookie) return;

            // PnL from ledger entries (exclude paymentLogged)
            let query = this.supabase
                .from('ledger_entries')
                .select('amount, type, created_at')
                .eq('bookie_id', this.bookie.id)
                .neq('type', 'paymentLogged');

            if (this.timeFilter !== 'All') {
                const since = this.timeFilterDate();
                query = query.gte('created_at', since.toISOString());
            }

            const { data: ledger } = await query;
            this.pnl = (ledger || []).reduce((sum, e) => sum + (e.amount || 0), 0);

            // Open picks count
            const { count: openCount } = await this.supabase
                .from('bets')
                .select('id', { count: 'exact', head: true })
                .eq('bookie_id', this.bookie.id)
                .in('status', ['pending', 'accepted']);

            this.openPickCount = openCount || 0;

            // Total volume
            const { data: volumeData } = await this.supabase
                .from('bets')
                .select('stake')
                .eq('bookie_id', this.bookie.id);

            this.totalVolume = (volumeData || []).reduce((sum, b) => sum + (b.stake || 0), 0);

            // Recent activity (last 10 ledger entries)
            const { data: recent } = await this.supabase
                .from('ledger_entries')
                .select('*')
                .eq('bookie_id', this.bookie.id)
                .order('created_at', { ascending: false })
                .limit(10);

            this.recentActivity = recent || [];
        },

        // ── Picks Data ──
        async loadPicks() {
            if (!this.bookie) return;

            let query = this.supabase
                .from('bets')
                .select('*')
                .eq('bookie_id', this.bookie.id)
                .order('created_at', { ascending: false })
                .limit(100);

            if (this.pickFilter === 'open') {
                query = query.in('status', ['pending', 'accepted']);
            } else {
                query = query.in('status', ['won', 'lost', 'push', 'voided', 'graded', 'settled']);
            }

            if (this.pickMemberFilter) {
                query = query.eq('player_id', this.pickMemberFilter);
            }

            if (this.pickTypeFilter === 'single') {
                query = query.eq('bet_type', 'single');
            } else if (this.pickTypeFilter === 'parlay') {
                query = query.eq('bet_type', 'parlay');
            } else if (this.pickTypeFilter === 'futures') {
                query = query.eq('market_type', 'outright');
            }

            const { data, error } = await query;

            if (error) {
                console.error('Failed to load picks:', error);
                return;
            }

            this.bets = data || [];
        },

        // ── Pick Detail ──
        async loadPickDetail() {
            if (!this.selectedBetId || !this.bookie) return;
            this.isLoadingPickDetail = true;
            this.pickDetail = null;

            const { data, error } = await this.supabase
                .from('bets')
                .select('*')
                .eq('id', this.selectedBetId)
                .limit(1);

            if (error || !data?.length) {
                console.error('Failed to load pick detail:', error);
                this.toast('Failed to load pick', 'error');
            } else {
                this.pickDetail = data[0];
            }

            this.isLoadingPickDetail = false;
        },

        calcPotentialReturn(bet) {
            if (!bet) return 0;
            const odds = Number(bet.odds) || 0;
            const stake = Number(bet.stake) || 0;
            if (odds > 0) {
                return stake + stake * (odds / 100);
            } else if (odds < 0) {
                return stake + stake * (100 / Math.abs(odds));
            }
            return stake;
        },

        calcPickPnl(bet) {
            if (!bet) return 0;
            const stake = Number(bet.stake) || 0;
            if (bet.status === 'won' || bet.status === 'settled') {
                return this.calcPotentialReturn(bet) - stake;
            } else if (bet.status === 'lost') {
                return -stake;
            }
            return 0;
        },

        // ── Invite ──
        async createInvite() {
            this.isCreatingInvite = true;
            this.inviteError = '';
            this.inviteCode = '';

            try {
                const response = await this.callEdgeFunction('create_invite', {
                    idempotency_key: crypto.randomUUID(),
                    email: this.inviteEmail || undefined,
                    credit_limit: parseFloat(this.inviteCreditLimit) || 1000,
                });

                if (response.error) {
                    this.inviteError = response.error;
                } else {
                    this.inviteCode = response.code;
                    this.toast('Invite created', 'success');
                }
            } catch (e) {
                this.inviteError = e.message || 'Failed to create invite';
            }

            this.isCreatingInvite = false;
        },

        copyInviteCode() {
            navigator.clipboard.writeText(this.inviteCode);
            this.toast('Code copied', 'success');
        },

        // ── Settle Up ──
        openSettleUp(player) {
            this.settlePlayer = player;
            this.settleError = '';
            this.showSettleModal = true;
        },

        async settleUp() {
            if (!this.settlePlayer || !this.bookie) return;
            this.isSettling = true;
            this.settleError = '';

            try {
                const balance = this.settlePlayer.balance || 0;
                if (balance === 0) {
                    this.settleError = 'Balance is already $0';
                    this.isSettling = false;
                    return;
                }

                await this.callEdgeFunction('adjust_balance', {
                    idempotency_key: crypto.randomUUID(),
                    player_id: this.settlePlayer.id,
                    amount: -balance,
                    type: 'paymentLogged',
                    reason: 'Settle up',
                });

                this.toast(`Settled up with ${this.settlePlayer.name}`, 'success');
                this.showSettleModal = false;
                await this.loadPlayers();
                await this.loadDashboard();
            } catch (e) {
                this.settleError = e.message || 'Failed to settle';
            }

            this.isSettling = false;
        },

        // ── Adjust Balance ──
        openAdjustBalance(player) {
            this.adjustPlayer = player;
            this.adjustAmount = '';
            this.adjustReason = '';
            this.adjustError = '';
            this.showAdjustModal = true;
        },

        async adjustBalance() {
            if (!this.adjustPlayer || !this.bookie) return;
            this.isAdjusting = true;
            this.adjustError = '';

            const amount = parseFloat(this.adjustAmount);
            if (isNaN(amount) || amount === 0) {
                this.adjustError = 'Enter a non-zero amount';
                this.isAdjusting = false;
                return;
            }

            try {
                await this.callEdgeFunction('adjust_balance', {
                    idempotency_key: crypto.randomUUID(),
                    player_id: this.adjustPlayer.id,
                    amount: amount,
                    type: 'adjustment',
                    reason: this.adjustReason || undefined,
                });

                this.toast(`Adjusted balance for ${this.adjustPlayer.name}`, 'success');
                this.showAdjustModal = false;
                await this.loadPlayers();
                await this.loadDashboard();
            } catch (e) {
                this.adjustError = e.message || 'Failed to adjust';
            }

            this.isAdjusting = false;
        },

        // ── Subscription ──
        async startCheckout() {
            this.isCheckingOut = true;

            try {
                const response = await this.callEdgeFunction('create_checkout_session', {
                    success_url: 'https://bookisports.com/dashboard/app.html#/subscription?success=true',
                    cancel_url: 'https://bookisports.com/dashboard/app.html#/subscription?canceled=true',
                });

                if (response.url) {
                    window.location.href = response.url;
                } else {
                    this.toast(response.error || 'Failed to create checkout', 'error');
                }
            } catch (e) {
                this.toast(e.message || 'Checkout failed', 'error');
            }

            this.isCheckingOut = false;
        },

        async openPortal() {
            this.isOpeningPortal = true;

            try {
                const response = await this.callEdgeFunction('create_customer_portal', {});

                if (response.url) {
                    window.open(response.url, '_blank');
                } else {
                    this.toast(response.error || 'Failed to open portal', 'error');
                }
            } catch (e) {
                this.toast(e.message || 'Portal failed', 'error');
            }

            this.isOpeningPortal = false;
        },

        // ── Helpers ──
        async callEdgeFunction(name, body) {
            const res = await fetch(`${SUPABASE_URL}/functions/v1/${name}`, {
                method: 'POST',
                headers: {
                    'Authorization': `Bearer ${this.session.access_token}`,
                    'apikey': SUPABASE_ANON_KEY,
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify(body),
            });

            const data = await res.json();
            if (!res.ok && !data.error) {
                throw new Error(`HTTP ${res.status}`);
            }
            return data;
        },

        getPlayerName(playerId) {
            const p = this.playerMap[playerId];
            return p ? (p.display_name || p.name) : '—';
        },

        get filteredPlayers() {
            const q = this.memberSearch.toLowerCase();
            if (!q) return this.players;
            return this.players.filter(p =>
                (p.name || '').toLowerCase().includes(q) ||
                (p.display_name || '').toLowerCase().includes(q)
            );
        },

        formatCurrency(val) {
            const n = Number(val) || 0;
            const prefix = n < 0 ? '-' : '';
            return prefix + '$' + Math.abs(n).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
        },

        formatDate(iso) {
            if (!iso) return '—';
            const d = new Date(iso);
            return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
        },

        formatOdds(odds) {
            if (!odds) return '—';
            const n = Number(odds);
            return n > 0 ? `+${n}` : String(n);
        },

        statusBadgeClass(status) {
            switch (status) {
                case 'won': case 'settled': return 'badge-success';
                case 'lost': return 'badge-danger';
                case 'pending': case 'accepted': return 'badge-warning';
                default: return 'badge-muted';
            }
        },

        timeFilterDate() {
            const now = new Date();
            switch (this.timeFilter) {
                case '1D': return new Date(now - 24 * 60 * 60 * 1000);
                case '1W': return new Date(now - 7 * 24 * 60 * 60 * 1000);
                case '1M': return new Date(now - 30 * 24 * 60 * 60 * 1000);
                default: return new Date(0);
            }
        },

        // ── Toasts ──
        toast(message, type = 'success') {
            const t = { message, type, visible: true };
            this.toasts.push(t);
            setTimeout(() => {
                t.visible = false;
                setTimeout(() => {
                    this.toasts = this.toasts.filter(x => x !== t);
                }, 300);
            }, 3000);
        },
    };
}
