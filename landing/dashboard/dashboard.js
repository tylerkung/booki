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
        pickDetailLegs: [],
        pickDetailTimeline: [],
        isLoadingPickDetail: false,

        // ── Grading ──
        showGradeModal: false,
        gradingOutcome: '',
        isGrading: false,
        showVoidModal: false,
        isVoiding: false,

        // ── Member Detail ──
        memberDetail: null,
        isLoadingMemberDetail: false,
        showArchiveModal: false,
        showRemoveModal: false,
        isArchiving: false,
        isRemoving: false,
        showMemberOverflow: false,
        memberDetailBets: [],
        memberDetailLedger: [],
        memberPickFilter: 'open',
        memberActivityExpanded: false,

        // ── Inline Editing ──
        isEditingName: false,
        isEditingCredit: false,
        editNameValue: '',
        editCreditValue: '',

        startEditingName() {
            this.editNameValue = this.memberDetail.display_name || this.memberDetail.name || '';
            this.isEditingName = true;
            this.$nextTick(() => {
                const el = document.getElementById('edit-name-input');
                if (el) { el.focus(); el.select(); }
            });
        },

        startEditingCredit() {
            this.editCreditValue = String(this.memberDetail.credit_limit || 0);
            this.isEditingCredit = true;
            this.$nextTick(() => {
                const el = document.getElementById('edit-credit-input');
                if (el) { el.focus(); el.select(); }
            });
        },

        async saveMemberName() {
            if (!this.memberDetail) return;
            const newName = this.editNameValue.trim();
            if (!newName) {
                this.isEditingName = false;
                return;
            }

            const oldName = this.memberDetail.display_name || this.memberDetail.name;
            if (newName === oldName) {
                this.isEditingName = false;
                return;
            }

            const { error } = await this.supabase
                .from('players')
                .update({ display_name: newName })
                .eq('id', this.memberDetail.id);

            if (error) {
                this.toast('Failed to update name', 'error');
            } else {
                this.memberDetail.display_name = newName;
                // Sync playerMap and players array
                if (this.playerMap[this.memberDetail.id]) {
                    this.playerMap[this.memberDetail.id].display_name = newName;
                }
                const idx = this.players.findIndex(p => p.id === this.memberDetail.id);
                if (idx >= 0) this.players[idx].display_name = newName;
                this.toast('Name updated', 'success');
            }

            this.isEditingName = false;
        },

        async saveMemberCredit() {
            if (!this.memberDetail) return;
            const newLimit = parseFloat(this.editCreditValue);
            if (isNaN(newLimit) || newLimit < 0) {
                this.toast('Invalid credit limit', 'error');
                this.isEditingCredit = false;
                return;
            }

            if (newLimit === (this.memberDetail.credit_limit || 0)) {
                this.isEditingCredit = false;
                return;
            }

            const { error } = await this.supabase
                .from('players')
                .update({ credit_limit: newLimit })
                .eq('id', this.memberDetail.id);

            if (error) {
                this.toast('Failed to update credit limit', 'error');
            } else {
                this.memberDetail.credit_limit = newLimit;
                // Sync playerMap and players array
                if (this.playerMap[this.memberDetail.id]) {
                    this.playerMap[this.memberDetail.id].credit_limit = newLimit;
                }
                const idx = this.players.findIndex(p => p.id === this.memberDetail.id);
                if (idx >= 0) this.players[idx].credit_limit = newLimit;
                this.toast('Credit limit updated', 'success');
            }

            this.isEditingCredit = false;
        },

        // ── Settings ──
        settingsName: '',
        settingsEmail: '',
        isSavingProfile: false,
        currentPassword: '',
        newPassword: '',
        confirmPassword: '',
        isChangingPassword: false,
        passwordError: '',
        settingsDefaultCreditLimit: 1000,
        isSavingCreditLimit: false,
        settingsAllowFuturesParlays: false,

        // ── Danger Zone ──
        showStepDownModal: false,
        isSteppingDown: false,
        showDeleteStep1: false,
        showDeleteStep2: false,
        deleteConfirmText: '',
        isDeleting: false,

        // ── Override / Reverse ──
        showOverrideModal: false,
        overrideOutcome: 'won',
        overrideReason: '',
        isOverriding: false,
        showReverseModal: false,
        isReversing: false,

        // ── Invites ──
        invites: [],
        isDeletingInvite: null,

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
            if (this.route === 'members') this.loadInvites();
            if (this.route === 'member-detail') this.loadMemberDetail();
            if (this.route === 'settings') this.loadSettings();
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
            this.pickDetailLegs = [];
            this.pickDetailTimeline = [];

            const { data, error } = await this.supabase
                .from('bets')
                .select('*')
                .eq('id', this.selectedBetId)
                .limit(1);

            if (error || !data?.length) {
                console.error('Failed to load pick detail:', error);
                this.toast('Failed to load pick', 'error');
                this.isLoadingPickDetail = false;
                return;
            }

            this.pickDetail = data[0];

            // Fetch parlay legs if applicable
            if (this.pickDetail.bet_type === 'parlay' && this.pickDetail.ticket_id) {
                const { data: legs } = await this.supabase
                    .from('bet_legs')
                    .select('*')
                    .eq('ticket_id', this.pickDetail.ticket_id)
                    .order('created_at');
                this.pickDetailLegs = legs || [];
            }

            // Fetch activity timeline from settlement_events
            const { data: events } = await this.supabase
                .from('settlement_events')
                .select('*')
                .eq('bet_id', this.selectedBetId)
                .order('created_at');

            if (events && events.length > 0) {
                this.pickDetailTimeline = events;
            } else {
                // Fallback: show created_at as the only timeline entry
                this.pickDetailTimeline = [{
                    id: 'created',
                    event_type: 'created',
                    description: 'Pick placed',
                    created_at: this.pickDetail.created_at,
                }];
            }

            this.isLoadingPickDetail = false;
        },

        // ── Member Detail ──
        async loadMemberDetail() {
            if (!this.selectedPlayerId || !this.bookie) return;
            this.isLoadingMemberDetail = true;
            this.memberDetail = null;
            this.showMemberOverflow = false;
            this.isEditingName = false;
            this.isEditingCredit = false;
            this.memberActivityExpanded = false;

            // Look up from playerMap first, then fetch from Supabase
            let player = this.playerMap[this.selectedPlayerId];
            if (!player) {
                const { data, error } = await this.supabase
                    .from('players')
                    .select('*')
                    .eq('id', this.selectedPlayerId)
                    .limit(1);

                if (error || !data?.length) {
                    console.error('Failed to load member detail:', error);
                    this.toast('Failed to load member', 'error');
                    this.isLoadingMemberDetail = false;
                    return;
                }
                player = data[0];
            }

            // Load balance from ledger entries
            const { data: ledger } = await this.supabase
                .from('ledger_entries')
                .select('amount')
                .eq('player_id', this.selectedPlayerId)
                .eq('bookie_id', this.bookie.id);

            const balance = (ledger || []).reduce((sum, e) => sum + (e.amount || 0), 0);
            player.balance = balance;

            this.memberDetail = player;

            // Load bets and ledger for performance/picks
            await this.loadMemberBetsAndLedger();

            this.isLoadingMemberDetail = false;
        },

        async loadMemberBetsAndLedger() {
            if (!this.selectedPlayerId || !this.bookie) return;

            const [betsRes, ledgerRes] = await Promise.all([
                this.supabase
                    .from('bets')
                    .select('*')
                    .eq('player_id', this.selectedPlayerId)
                    .eq('bookie_id', this.bookie.id)
                    .order('created_at', { ascending: false }),
                this.supabase
                    .from('ledger_entries')
                    .select('*')
                    .eq('player_id', this.selectedPlayerId)
                    .eq('bookie_id', this.bookie.id),
            ]);

            this.memberDetailBets = betsRes.data || [];
            this.memberDetailLedger = ledgerRes.data || [];
        },

        get memberRecord() {
            const bets = this.memberDetailBets;
            const wins = bets.filter(b => b.status === 'won' || b.status === 'settled').length;
            const losses = bets.filter(b => b.status === 'lost').length;
            const pushes = bets.filter(b => b.status === 'push').length;
            return { wins, losses, pushes };
        },

        get memberPnl() {
            return this.memberDetailLedger
                .filter(e => e.type !== 'paymentLogged')
                .reduce((sum, e) => sum + (e.amount || 0), 0);
        },

        get memberWinRate() {
            const { wins, losses } = this.memberRecord;
            const total = wins + losses;
            if (total === 0) return null;
            return Math.round((wins / total) * 100);
        },

        get memberFilteredPicks() {
            if (this.memberPickFilter === 'open') {
                return this.memberDetailBets.filter(b => ['pending', 'accepted'].includes(b.status));
            }
            return this.memberDetailBets.filter(b => ['won', 'lost', 'push', 'void', 'voided', 'settled', 'graded'].includes(b.status));
        },

        get memberRecentActivity() {
            const items = [];

            // Normalize bets into activity items
            for (const bet of this.memberDetailBets) {
                items.push({
                    date: bet.created_at,
                    type: bet.status === 'won' || bet.status === 'settled' ? 'won'
                        : bet.status === 'lost' ? 'lost'
                        : 'bet_placed',
                    description: (bet.team_name || bet.selection || 'Pick') + ' ' + this.formatOdds(bet.odds),
                    amount: bet.status === 'lost' ? -(Number(bet.stake) || 0)
                        : (bet.status === 'won' || bet.status === 'settled') ? this.calcPickPnl(bet)
                        : -(Number(bet.stake) || 0),
                    source: 'bet',
                });
            }

            // Normalize ledger entries into activity items
            for (const entry of this.memberDetailLedger) {
                items.push({
                    date: entry.created_at,
                    type: entry.type || 'adjustment',
                    description: entry.reason || (entry.type === 'paymentLogged' ? 'Settlement' : 'Balance adjustment'),
                    amount: entry.amount || 0,
                    source: 'ledger',
                });
            }

            // Sort by date descending
            items.sort((a, b) => new Date(b.date) - new Date(a.date));
            return items;
        },

        activityTypeBadge(type) {
            switch (type) {
                case 'bet_placed': return { label: 'Pick', cls: 'badge-warning' };
                case 'won': return { label: 'Won', cls: 'badge-success' };
                case 'lost': return { label: 'Lost', cls: 'badge-danger' };
                case 'paymentLogged': return { label: 'Settlement', cls: 'badge-success' };
                case 'adjustment': return { label: 'Adjustment', cls: 'badge-muted' };
                default: return { label: type, cls: 'badge-muted' };
            }
        },

        async archiveMember() {
            if (!this.memberDetail) return;
            this.isArchiving = true;

            const { error } = await this.supabase
                .from('players')
                .update({ status: 'archived' })
                .eq('id', this.memberDetail.id);

            if (error) {
                this.toast('Failed to archive member', 'error');
            } else {
                this.toast(`${this.memberDetail.display_name || this.memberDetail.name} archived`, 'success');
                this.showArchiveModal = false;
                this.memberDetail.status = 'archived';
                // Update playerMap
                if (this.playerMap[this.memberDetail.id]) {
                    this.playerMap[this.memberDetail.id].status = 'archived';
                }
                await this.loadPlayers();
            }

            this.isArchiving = false;
        },

        async removeMember() {
            if (!this.memberDetail) return;
            this.isRemoving = true;

            const { error } = await this.supabase
                .from('players')
                .update({ bookie_id: null, auth_user_id: null })
                .eq('id', this.memberDetail.id);

            if (error) {
                this.toast('Failed to remove member', 'error');
            } else {
                this.toast(`${this.memberDetail.display_name || this.memberDetail.name} removed`, 'success');
                this.showRemoveModal = false;
                await this.loadPlayers();
                window.location.hash = '#/members';
            }

            this.isRemoving = false;
        },

        getMemberCreditUtilization() {
            if (!this.memberDetail) return 0;
            const balance = this.memberDetail.balance || 0;
            const limit = this.memberDetail.credit_limit || 1;
            // Utilization: how much of credit is used (balance as % of limit)
            return Math.min(100, Math.max(0, (Math.abs(balance) / limit) * 100));
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

        // ── Grading Actions ──
        confirmGrade(outcome) {
            this.gradingOutcome = outcome;
            this.showGradeModal = true;
        },

        async gradePick() {
            if (!this.pickDetail || !this.gradingOutcome) return;
            this.isGrading = true;

            try {
                const response = await this.callEdgeFunction('grade_bet', {
                    bet_id: this.pickDetail.id,
                    outcome: this.gradingOutcome,
                    idempotency_key: crypto.randomUUID(),
                });

                if (response.error) {
                    this.toast(response.error, 'error');
                } else {
                    this.toast(`Pick graded as ${this.gradingOutcome}`, 'success');
                    this.showGradeModal = false;
                    await this.loadPickDetail();
                }
            } catch (e) {
                this.toast(e.message || 'Failed to grade pick', 'error');
            }

            this.isGrading = false;
        },

        confirmVoid() {
            this.showVoidModal = true;
        },

        async voidPick() {
            if (!this.pickDetail) return;
            this.isVoiding = true;

            try {
                const response = await this.callEdgeFunction('grade_bet', {
                    bet_id: this.pickDetail.id,
                    outcome: 'void',
                    idempotency_key: crypto.randomUUID(),
                });

                if (response.error) {
                    this.toast(response.error, 'error');
                } else {
                    this.toast('Pick voided', 'success');
                    this.showVoidModal = false;
                    await this.loadPickDetail();
                }
            } catch (e) {
                this.toast(e.message || 'Failed to void pick', 'error');
            }

            this.isVoiding = false;
        },

        // ── Override Grade ──
        openOverrideModal() {
            this.overrideOutcome = 'won';
            this.overrideReason = '';
            this.showOverrideModal = true;
        },

        async overrideGrade() {
            if (!this.pickDetail || !this.overrideReason.trim()) return;
            this.isOverriding = true;

            try {
                const response = await this.callEdgeFunction('override_grade', {
                    bet_id: this.pickDetail.id,
                    new_outcome: this.overrideOutcome,
                    reason: this.overrideReason.trim(),
                    idempotency_key: crypto.randomUUID(),
                });

                if (response.error) {
                    this.toast(response.error, 'error');
                } else {
                    this.toast('Grade overridden successfully', 'success');
                    this.showOverrideModal = false;
                    await this.loadPickDetail();
                }
            } catch (e) {
                this.toast(e.message || 'Failed to override grade', 'error');
            }

            this.isOverriding = false;
        },

        // ── Reverse Settlement ──
        confirmReverse() {
            this.showReverseModal = true;
        },

        async reverseSettlement() {
            if (!this.pickDetail) return;
            this.isReversing = true;

            try {
                const response = await this.callEdgeFunction('reverse_settlement', {
                    bet_id: this.pickDetail.id,
                    idempotency_key: crypto.randomUUID(),
                });

                if (response.error) {
                    this.toast(response.error, 'error');
                } else {
                    this.toast('Settlement reversed', 'success');
                    this.showReverseModal = false;
                    await this.loadPickDetail();
                }
            } catch (e) {
                this.toast(e.message || 'Failed to reverse settlement', 'error');
            }

            this.isReversing = false;
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
                    this.loadInvites();
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

        copyInviteCodeValue(code) {
            navigator.clipboard.writeText(code);
            this.toast('Code copied', 'success');
        },

        copyInviteLink(code) {
            navigator.clipboard.writeText(`Download Booki and use invite code: ${code}`);
            this.toast('Link copied', 'success');
        },

        async loadInvites() {
            if (!this.bookie) return;

            const { data, error } = await this.supabase
                .from('invites')
                .select('*')
                .eq('bookie_id', this.bookie.id)
                .is('claimed_at', null)
                .order('created_at', { ascending: false });

            if (error) {
                console.error('Failed to load invites:', error);
                return;
            }

            this.invites = data || [];
        },

        async deleteInvite(inviteId) {
            this.isDeletingInvite = inviteId;

            const { error } = await this.supabase
                .from('invites')
                .delete()
                .eq('id', inviteId);

            if (error) {
                this.toast('Failed to delete invite', 'error');
                console.error('Delete invite error:', error);
            } else {
                this.invites = this.invites.filter(i => i.id !== inviteId);
                this.toast('Invite deleted', 'success');
            }

            this.isDeletingInvite = null;
        },

        get memberCapacityLimit() {
            return this.isPro ? 50 : 3;
        },

        get memberCapacityPercent() {
            return Math.min(100, Math.round((this.activeMemberCount / this.memberCapacityLimit) * 100));
        },

        get isAtMemberCapacity() {
            return this.activeMemberCount >= this.memberCapacityLimit;
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

        // ── Settings ──
        loadSettings() {
            if (!this.bookie) return;
            this.settingsName = this.bookie.name || '';
            this.settingsEmail = this.session?.user?.email || '';
            this.currentPassword = '';
            this.newPassword = '';
            this.confirmPassword = '';
            this.passwordError = '';
            this.settingsDefaultCreditLimit = this.bookie.default_credit_limit ?? 1000;
            this.settingsAllowFuturesParlays = this.bookie.allow_futures_parlays ?? false;
        },

        async saveProfile() {
            if (!this.bookie) return;
            const name = this.settingsName.trim();
            if (!name) {
                this.toast('Name cannot be empty', 'error');
                return;
            }
            if (name === this.bookie.name) return;

            this.isSavingProfile = true;
            const { error } = await this.supabase
                .from('bookies')
                .update({ name })
                .eq('id', this.bookie.id);

            if (error) {
                this.toast('Failed to update name', 'error');
            } else {
                this.bookie.name = name;
                this.toast('Profile updated', 'success');
            }
            this.isSavingProfile = false;
        },

        async saveDefaultCreditLimit() {
            if (!this.bookie) return;
            const val = parseInt(this.settingsDefaultCreditLimit, 10);
            if (isNaN(val) || val < 0) {
                this.toast('Credit limit must be a positive number', 'error');
                return;
            }
            this.isSavingCreditLimit = true;
            const { error } = await this.supabase
                .from('bookies')
                .update({ default_credit_limit: val })
                .eq('id', this.bookie.id);

            if (error) {
                this.toast('Failed to update default credit limit', 'error');
            } else {
                this.bookie.default_credit_limit = val;
                this.toast('Default credit limit updated', 'success');
            }
            this.isSavingCreditLimit = false;
        },

        async toggleAllowFuturesParlays() {
            if (!this.bookie || !this.isPro) return;
            const newVal = !this.settingsAllowFuturesParlays;
            const { error } = await this.supabase
                .from('bookies')
                .update({ allow_futures_parlays: newVal })
                .eq('id', this.bookie.id);

            if (error) {
                this.toast('Failed to update setting', 'error');
            } else {
                this.settingsAllowFuturesParlays = newVal;
                this.bookie.allow_futures_parlays = newVal;
                this.toast('Setting updated', 'success');
            }
        },

        async changePassword() {
            this.passwordError = '';

            if (!this.currentPassword) {
                this.passwordError = 'Current password is required';
                return;
            }
            if (this.newPassword.length < 6) {
                this.passwordError = 'New password must be at least 6 characters';
                return;
            }
            if (this.newPassword !== this.confirmPassword) {
                this.passwordError = 'Passwords do not match';
                return;
            }

            this.isChangingPassword = true;

            // Re-authenticate with current password
            const { error: signInError } = await this.supabase.auth.signInWithPassword({
                email: this.session.user.email,
                password: this.currentPassword,
            });

            if (signInError) {
                this.passwordError = 'Current password is incorrect';
                this.isChangingPassword = false;
                return;
            }

            // Update password
            const { error } = await this.supabase.auth.updateUser({
                password: this.newPassword,
            });

            if (error) {
                this.passwordError = error.message || 'Failed to update password';
            } else {
                this.toast('Password updated', 'success');
                this.currentPassword = '';
                this.newPassword = '';
                this.confirmPassword = '';
            }

            this.isChangingPassword = false;
        },

        // ── Danger Zone ──
        async stepDown() {
            this.isSteppingDown = true;

            try {
                const response = await this.callEdgeFunction('step_down_organizer', {
                    idempotency_key: crypto.randomUUID(),
                });

                if (response.error) {
                    if (response.error.includes('has_members_or_invites') || response.error.includes('members') || response.error.includes('invites')) {
                        this.toast('Please remove all members and invites before stepping down.', 'error');
                    } else {
                        this.toast(response.error, 'error');
                    }
                } else {
                    this.toast('Stepped down from organizer', 'success');
                    this.showStepDownModal = false;
                    await this.supabase.auth.signOut();
                    window.location.href = 'index.html';
                }
            } catch (e) {
                this.toast(e.message || 'Failed to step down', 'error');
            }

            this.isSteppingDown = false;
        },

        async deleteAccount() {
            if (this.deleteConfirmText !== 'DELETE') return;
            this.isDeleting = true;

            try {
                const response = await this.callEdgeFunction('delete_account', {
                    idempotency_key: crypto.randomUUID(),
                });

                if (response.error) {
                    this.toast(response.error, 'error');
                } else {
                    this.toast('Account deleted', 'success');
                    this.showDeleteStep2 = false;
                    await this.supabase.auth.signOut();
                    window.location.href = 'index.html';
                }
            } catch (e) {
                this.toast(e.message || 'Failed to delete account', 'error');
            }

            this.isDeleting = false;
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
