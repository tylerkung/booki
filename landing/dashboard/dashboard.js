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
        pickBackRoute: '#/picks',
        pickBackLabel: 'Back to Picks',

        // ── Dashboard ──
        timeFilter: 'All',
        pnl: 0,
        activeMemberCount: 0,
        openPickCount: 0,
        totalVolume: 0,
        recentActivity: [],
        netExposure: 0,
        topRiskMember: null,
        dashboardMembers: [],
        sportPerformance: [],
        futuresActivity: { openCount: 0, totalStaked: 0, topSelections: [] },

        // ── Members ──
        players: [],
        playerMap: {},
        memberSearch: '',
        allLedgerEntries: [],
        tagTooltip: null,

        // ── Picks ──
        bets: [],
        pickFilter: 'open',
        pickMemberFilter: '',
        pickTypeFilter: '',
        picksOffset: 0,
        hasMorePicks: false,

        // ── Members Sorting ──
        memberSortColumn: 'name',
        memberSortAsc: true,

        // ── Subscription ──
        isPro: false,
        isCheckingOut: false,
        isOpeningPortal: false,
        subscriptionSuccess: false,
        subscriptionCanceled: false,

        // ── Realtime ──
        realtimeChannel: null,
        _realtimeDebounceTimers: {},

        // ── Loading States ──
        isLoadingDashboard: true,
        isLoadingPlayers: true,
        isLoadingPicks: false,

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

        // ── Events ──
        events: [],
        isLoadingEvents: false,
        eventSearch: '',
        eventSportFilter: '',

        // ── Event Detail ──
        selectedEventId: null,
        eventDetail: null,
        eventDetailBets: [],
        eventDetailMarkets: [],
        isLoadingEventDetail: false,

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

            // Load bookie — sign out non-organizers to prevent redirect loop
            await this.loadBookie();
            if (!this.bookie) {
                await this.supabase.auth.signOut();
                window.location.href = 'index.html';
                return;
            }

            // Subscribe to realtime updates
            this.subscribeToRealtime();

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
            const prevRoute = this.route;
            const hash = window.location.hash.replace(/\?.*$/, '');
            const path = hash.replace('#/', '') || 'dashboard';

            // Check parameterized routes
            const memberMatch = path.match(/^members\/(.+)$/);
            const pickMatch = path.match(/^picks\/(.+)$/);
            const eventMatch = path.match(/^events\/(.+)$/);

            if (eventMatch) {
                this.route = 'event-detail';
                this.selectedEventId = eventMatch[1];
            } else if (memberMatch) {
                this.route = 'member-detail';
                this.selectedPlayerId = memberMatch[1];
            } else if (pickMatch) {
                // Set back route based on where we came from
                if (prevRoute === 'member-detail' && this.selectedPlayerId) {
                    const name = this.memberDetail?.display_name || this.memberDetail?.name || this.playerMap[this.selectedPlayerId]?.name || 'Member';
                    this.pickBackRoute = '#/members/' + this.selectedPlayerId;
                    this.pickBackLabel = 'Back to ' + name;
                } else if (prevRoute !== 'pick-detail') {
                    // Don't reset if we're already on pick-detail (e.g. navigating between picks)
                    this.pickBackRoute = '#/picks';
                    this.pickBackLabel = 'Back to Picks';
                }
                this.route = 'pick-detail';
                this.selectedBetId = pickMatch[1];
            } else {
                const routes = ['dashboard', 'members', 'picks', 'events', 'subscription', 'settings'];
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
            if (this.route === 'events') this.loadEvents();
            if (this.route === 'event-detail') this.loadEventDetail();
        },

        // ── Auth ──
        async logout() {
            this.unsubscribeFromRealtime();
            await this.supabase.auth.signOut();
            window.location.href = 'index.html';
        },

        // ── Realtime Subscriptions ──
        _debouncedReload(key, fn, delay = 300) {
            if (this._realtimeDebounceTimers[key]) {
                clearTimeout(this._realtimeDebounceTimers[key]);
            }
            this._realtimeDebounceTimers[key] = setTimeout(() => {
                fn();
                delete this._realtimeDebounceTimers[key];
            }, delay);
        },

        subscribeToRealtime() {
            if (!this.bookie || this.realtimeChannel) return;

            const bookieId = this.bookie.id;

            this.realtimeChannel = this.supabase
                .channel('bookie-changes')
                .on('postgres_changes', {
                    event: '*',
                    schema: 'public',
                    table: 'bets',
                    filter: `bookie_id=eq.${bookieId}`
                }, () => {
                    this._debouncedReload('bets', () => {
                        this.loadDashboard();
                        if (this.route === 'picks') this.loadPicks();
                    });
                })
                .on('postgres_changes', {
                    event: '*',
                    schema: 'public',
                    table: 'players',
                    filter: `bookie_id=eq.${bookieId}`
                }, () => {
                    this._debouncedReload('players', () => {
                        this.loadPlayers();
                    });
                })
                .on('postgres_changes', {
                    event: '*',
                    schema: 'public',
                    table: 'ledger_entries',
                    filter: `bookie_id=eq.${bookieId}`
                }, () => {
                    this._debouncedReload('ledger', () => {
                        this.loadPlayers();
                        this.loadDashboard();
                    });
                })
                .subscribe();
        },

        unsubscribeFromRealtime() {
            if (this.realtimeChannel) {
                this.supabase.removeChannel(this.realtimeChannel);
                this.realtimeChannel = null;
            }
            // Clear any pending debounce timers
            for (const key in this._realtimeDebounceTimers) {
                clearTimeout(this._realtimeDebounceTimers[key]);
            }
            this._realtimeDebounceTimers = {};
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
            this.isLoadingPlayers = true;

            const { data, error } = await this.supabase
                .from('players')
                .select('*')
                .eq('bookie_id', this.bookie.id)
                .order('name');

            if (error) {
                console.error('Failed to load players:', error);
                this.isLoadingPlayers = false;
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
            this.isLoadingPlayers = false;
        },

        async loadPlayerBalances() {
            if (!this.bookie) return;

            const { data, error } = await this.supabase
                .from('ledger_entries')
                .select('player_id, amount, type, created_at')
                .eq('bookie_id', this.bookie.id);

            if (error) return;

            this.allLedgerEntries = data || [];

            // Sum balances per player
            const balances = {};
            for (const entry of this.allLedgerEntries) {
                balances[entry.player_id] = (balances[entry.player_id] || 0) + (entry.amount || 0);
            }

            for (const p of this.players) {
                p.balance = balances[p.id] || 0;
            }
        },

        // ── Dashboard Data ──
        async loadDashboard() {
            if (!this.bookie) return;
            this.isLoadingDashboard = true;

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

            // Recent activity: merge ledger entries + bet placements chronologically
            const { data: recentLedger } = await this.supabase
                .from('ledger_entries')
                .select('*')
                .eq('bookie_id', this.bookie.id)
                .order('created_at', { ascending: false })
                .limit(10);

            const { data: recentBets, error: betsErr } = await this.supabase
                .from('bets')
                .select('id, player_id, stake, odds, status, market, side, is_parlay, parlay_legs, created_at')
                .eq('bookie_id', this.bookie.id)
                .order('created_at', { ascending: false })
                .limit(10);

            if (betsErr) console.error('Recent bets query failed:', betsErr);

            // Normalize both into a common shape and merge
            const ledgerTypeLabels = { settlement: 'graded', paymentLogged: 'settle up', adjustment: 'adjustment' };
            const ledgerItems = (recentLedger || []).map(e => ({
                id: 'ledger-' + e.id,
                created_at: e.created_at,
                type: ledgerTypeLabels[e.type] || e.type,
                description: e.description || '',
                player_id: e.player_id,
                amount: e.amount,
                _source: 'ledger',
            }));
            const betItems = (recentBets || []).map(b => ({
                id: 'bet-' + b.id,
                created_at: b.created_at,
                type: b.is_parlay ? 'multi-pick' : 'pick',
                description: (b.side || '') + ' ' + this.formatOdds(b.odds),
                player_id: b.player_id,
                amount: b.stake,
                _source: 'bet',
            }));

            const merged = [...ledgerItems, ...betItems]
                .sort((a, b) => new Date(b.created_at) - new Date(a.created_at))
                .slice(0, 10);

            this.recentActivity = merged;

            // Exposure: fetch open bets for potential payout calculation
            const { data: openBets } = await this.supabase
                .from('bets')
                .select('stake, odds, player_id, status')
                .eq('bookie_id', this.bookie.id)
                .in('status', ['pending', 'accepted']);

            const openBetsList = openBets || [];
            // Net exposure = sum of potential payouts (what bookie would pay out)
            this.netExposure = openBetsList.reduce((sum, b) => {
                const payout = this.calcPotentialReturn(b) - (Number(b.stake) || 0);
                return sum + payout;
            }, 0);

            // Per-member exposure
            const memberExposureMap = {};
            for (const b of openBetsList) {
                if (!b.player_id) continue;
                if (!memberExposureMap[b.player_id]) {
                    memberExposureMap[b.player_id] = { exposure: 0, openPicks: 0 };
                }
                const payout = this.calcPotentialReturn(b) - (Number(b.stake) || 0);
                memberExposureMap[b.player_id].exposure += payout;
                memberExposureMap[b.player_id].openPicks += 1;
            }

            // Build dashboard members list sorted by exposure desc
            this.dashboardMembers = this.players
                .map(p => ({
                    ...p,
                    exposure: memberExposureMap[p.id]?.exposure || 0,
                    openPicks: memberExposureMap[p.id]?.openPicks || 0,
                }))
                .filter(p => p.status !== 'archived')
                .sort((a, b) => b.exposure - a.exposure);

            // Top risk member
            this.topRiskMember = this.dashboardMembers.length > 0 && this.dashboardMembers[0].exposure > 0
                ? this.dashboardMembers[0]
                : null;

            // Sport Performance breakdown + attention tags data
            const { data: allBets } = await this.supabase
                .from('bets')
                .select('event_id, stake, odds, status, market, side, player_id, is_parlay, created_at')
                .eq('bookie_id', this.bookie.id);

            // Build event → sport lookup
            const eventIds = [...new Set((allBets || []).map(b => b.event_id).filter(Boolean))];
            let eventSportMap = {};
            if (eventIds.length > 0) {
                const { data: events } = await this.supabase
                    .from('events')
                    .select('id, sport')
                    .in('id', eventIds);
                for (const e of (events || [])) {
                    eventSportMap[e.id] = e.sport;
                }
            }

            const sportMap = {};
            for (const b of (allBets || [])) {
                const sport = eventSportMap[b.event_id] || 'Unknown';
                if (!sportMap[sport]) {
                    sportMap[sport] = { sport, picks: 0, staked: 0, pnl: 0, wins: 0, losses: 0 };
                }
                sportMap[sport].picks += 1;
                sportMap[sport].staked += Number(b.stake) || 0;
                if (b.grade_result === 'win') {
                    const returnAmt = this.calcPotentialReturn(b);
                    sportMap[sport].pnl += (Number(b.stake) || 0) - returnAmt; // bookie perspective
                    sportMap[sport].wins += 1;
                } else if (b.grade_result === 'loss') {
                    sportMap[sport].pnl += Number(b.stake) || 0;
                    sportMap[sport].losses += 1;
                }
            }
            this.sportPerformance = Object.values(sportMap).sort((a, b) => b.picks - a.picks);

            // Futures Activity
            const futureBets = (allBets || []).filter(b => b.market === 'outright' && ['pending', 'accepted'].includes(b.status));
            const selectionCount = {};
            for (const b of futureBets) {
                const sel = b.side || 'Unknown';
                selectionCount[sel] = (selectionCount[sel] || 0) + 1;
            }
            const topSelections = Object.entries(selectionCount)
                .sort((a, b) => b[1] - a[1])
                .slice(0, 3)
                .map(([name, count]) => ({ name, count }));

            this.futuresActivity = {
                openCount: futureBets.length,
                totalStaked: futureBets.reduce((s, b) => s + (Number(b.stake) || 0), 0),
                topSelections,
            };

            // Compute attention tags for dashboard members
            const allBetsList = allBets || [];
            const groupAvgStake = allBetsList.length > 0
                ? allBetsList.reduce((s, b) => s + (Number(b.stake) || 0), 0) / allBetsList.length
                : 0;
            for (const member of this.dashboardMembers) {
                const playerBets = allBetsList.filter(b => b.player_id === member.id);
                const playerLedger = this.allLedgerEntries.filter(e => e.player_id === member.id);
                member.attentionTags = this.computeAttentionTags(member, playerBets, playerLedger, groupAvgStake);
            }
            this.isLoadingDashboard = false;
        },

        // ── Events Data ──
        async loadEvents() {
            this.isLoadingEvents = true;

            const fourteenDaysAgo = new Date(Date.now() - 14 * 24 * 60 * 60 * 1000).toISOString();

            const { data, error } = await this.supabase
                .from('events')
                .select('*')
                .is('bookie_id', null)
                .gte('start_time', fourteenDaysAgo)
                .order('start_time', { ascending: true });

            if (error) {
                console.error('Failed to load events:', error);
                this.isLoadingEvents = false;
                return;
            }

            this.events = data || [];
            this.isLoadingEvents = false;
        },

        formatSportName(sport) {
            if (!sport) return 'Unknown';
            const map = {
                'americanfootball_nfl': 'Football',
                'americanfootball_ncaaf': 'Football',
                'basketball_nba': 'Basketball',
                'basketball_ncaab': 'Basketball',
                'baseball_mlb': 'Baseball',
                'icehockey_nhl': 'Hockey',
                'soccer_epl': 'Soccer',
                'soccer_usa_mls': 'Soccer',
                'golf_pga': 'Golf',
                'mma_ufc': 'MMA',
                'tennis_atp': 'Tennis',
                'tennis_wta': 'Tennis',
            };
            return map[sport] || sport.split('_').map(s => s.charAt(0).toUpperCase() + s.slice(1)).join(' ');
        },

        formatLeagueName(sport) {
            if (!sport) return '';
            const parts = sport.split('_');
            return parts.length > 1 ? parts.slice(1).join(' ').toUpperCase() : sport.toUpperCase();
        },

        eventStatusBadgeClass(status) {
            switch (status) {
                case 'scheduled': return 'badge-muted';
                case 'in_progress': return 'badge-warning';
                case 'final': return 'badge-success';
                case 'canceled': return 'badge-danger';
                default: return 'badge-muted';
            }
        },

        get filteredEvents() {
            const q = this.eventSearch.toLowerCase();
            const sportFilter = this.eventSportFilter;
            const now = Date.now();
            const twoDaysMs = 48 * 60 * 60 * 1000;

            return this.events.filter(ev => {
                // Hide final events older than 48h unless search is active
                if (!q && ev.status === 'final') {
                    const startTime = new Date(ev.start_time).getTime();
                    if (now - startTime > twoDaysMs) return false;
                }

                // Search filter
                if (q) {
                    const home = (ev.home_team || '').toLowerCase();
                    const away = (ev.away_team || '').toLowerCase();
                    if (!home.includes(q) && !away.includes(q)) return false;
                }

                // Sport filter
                if (sportFilter) {
                    const sportName = this.formatSportName(ev.sport);
                    if (sportName !== sportFilter) return false;
                }

                return true;
            }).sort((a, b) => new Date(a.start_time) - new Date(b.start_time));
        },

        get groupedFilteredEvents() {
            const groups = {};
            for (const ev of this.filteredEvents) {
                const sport = this.formatSportName(ev.sport);
                const league = this.formatLeagueName(ev.sport);
                const key = sport + ' — ' + league;
                if (!groups[key]) {
                    groups[key] = { sport, league, key, events: [] };
                }
                groups[key].events.push(ev);
            }
            return Object.values(groups);
        },

        get eventSportOptions() {
            const sports = new Set();
            for (const ev of this.events) {
                sports.add(this.formatSportName(ev.sport));
            }
            return [...sports].sort();
        },

        formatEventTime(iso) {
            if (!iso) return '—';
            const d = new Date(iso);
            return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' }) + ' ' +
                   d.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' });
        },

        // ── Event Detail ──
        async loadEventDetail() {
            if (!this.selectedEventId || !this.bookie) return;
            this.isLoadingEventDetail = true;
            this.eventDetail = null;
            this.eventDetailBets = [];
            this.eventDetailMarkets = [];

            // Fetch event
            const { data: evtData, error: evtErr } = await this.supabase
                .from('events')
                .select('*')
                .eq('id', this.selectedEventId)
                .limit(1);

            if (evtErr || !evtData?.length) {
                console.error('Failed to load event detail:', evtErr);
                this.toast('Failed to load event', 'error');
                this.isLoadingEventDetail = false;
                return;
            }

            this.eventDetail = evtData[0];

            // Fetch markets for this event (shared markets have bookie_id NULL)
            const { data: mkts } = await this.supabase
                .from('markets')
                .select('*')
                .eq('event_id', this.selectedEventId)
                .is('bookie_id', null);

            this.eventDetailMarkets = mkts || [];

            // Fetch bets on this event for this bookie
            const { data: betsData } = await this.supabase
                .from('bets')
                .select('*')
                .eq('event_id', this.selectedEventId)
                .eq('bookie_id', this.bookie.id)
                .order('created_at', { ascending: false });

            this.eventDetailBets = betsData || [];
            this.isLoadingEventDetail = false;
        },

        get eventExposureBreakdown() {
            const sides = {};
            for (const bet of this.eventDetailBets) {
                if (!['pending', 'accepted', 'readyToGrade'].includes(bet.status)) continue;
                const side = bet.side || 'Unknown';
                if (!sides[side]) sides[side] = { side, count: 0, totalStake: 0 };
                sides[side].count += 1;
                sides[side].totalStake += Number(bet.stake) || 0;
            }
            const arr = Object.values(sides).sort((a, b) => b.totalStake - a.totalStake);
            const maxStake = arr.length > 0 ? arr[0].totalStake : 0;
            for (const s of arr) {
                s.isHighest = s.totalStake === maxStake && arr.length > 1;
            }
            return arr;
        },

        get eventTotalExposure() {
            return this.eventExposureBreakdown.reduce((sum, s) => sum + s.totalStake, 0);
        },

        // ── Picks Data ──
        async loadPicks(append = false) {
            if (!this.bookie) return;
            this.isLoadingPicks = true;

            if (!append) {
                this.picksOffset = 0;
            }

            let query = this.supabase
                .from('bets')
                .select('*')
                .eq('bookie_id', this.bookie.id)
                .order('created_at', { ascending: false })
                .range(this.picksOffset, this.picksOffset + 49);

            if (this.pickFilter === 'open') {
                query = query.in('status', ['pending', 'accepted', 'readyToGrade']);
            } else {
                query = query.in('status', ['graded', 'settled', 'void', 'declined']);
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
                this.isLoadingPicks = false;
                return;
            }

            const results = data || [];
            if (append) {
                this.bets = [...this.bets, ...results];
            } else {
                this.bets = results;
            }
            this.hasMorePicks = results.length === 50;
            this.isLoadingPicks = false;
        },

        async loadMorePicks() {
            this.picksOffset += 50;
            await this.loadPicks(true);
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

            // Enrich with event data (side/market are on bets, event name is on events)
            if (this.pickDetail.event_id) {
                const { data: evtData } = await this.supabase
                    .from('events')
                    .select('home_team, away_team, sport, start_time')
                    .eq('id', this.pickDetail.event_id)
                    .limit(1);
                if (evtData && evtData.length > 0) {
                    const evt = evtData[0];
                    this.pickDetail.event_name = evt.away_team
                        ? `${evt.away_team} @ ${evt.home_team}`
                        : evt.home_team;
                    this.pickDetail.sport = evt.sport;
                }
            }

            // Fetch parlay legs if applicable
            if (this.pickDetail.bet_type === 'parlay' && this.pickDetail.ticket_id) {
                const { data: legs } = await this.supabase
                    .from('bets')
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

            // Compute attention tags for member detail
            const allBetsForAvg = this.allLedgerEntries.length > 0 ? this.memberDetailBets : [];
            // Use group avg from all bets if available, otherwise just this player
            let groupAvgStake = 0;
            if (this.dashboardMembers.length > 0 && this.bets.length > 0) {
                // Approximate: use already loaded data
                const totalStake = this.dashboardMembers.reduce((s, m) => s + (m.exposure || 0), 0);
                groupAvgStake = totalStake > 0 ? totalStake / this.dashboardMembers.length : 0;
            }
            // Fetch group average stake from all bets for accurate tag computation
            const { data: avgData } = await this.supabase
                .from('bets')
                .select('stake')
                .eq('bookie_id', this.bookie.id);
            if (avgData && avgData.length > 0) {
                groupAvgStake = avgData.reduce((s, b) => s + (Number(b.stake) || 0), 0) / avgData.length;
            }
            this.memberDetail.attentionTags = this.computeAttentionTags(
                this.memberDetail,
                this.memberDetailBets,
                this.memberDetailLedger,
                groupAvgStake
            );

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
            const wins = bets.filter(b => b.grade_result === 'win').length;
            const losses = bets.filter(b => b.grade_result === 'loss').length;
            const pushes = bets.filter(b => b.grade_result === 'push').length;
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
                return this.memberDetailBets.filter(b => ['pending', 'accepted', 'readyToGrade'].includes(b.status));
            }
            return this.memberDetailBets.filter(b => ['graded', 'settled', 'void', 'declined'].includes(b.status));
        },

        /// Group bets by ticket_id into tickets for activity display
        _groupBetsIntoTickets(bets) {
            const ticketMap = {};
            for (const bet of bets) {
                const key = bet.ticket_id || bet.id;
                if (!ticketMap[key]) ticketMap[key] = [];
                ticketMap[key].push(bet);
            }
            return Object.entries(ticketMap).map(([ticketId, legs]) => {
                const isParlay = legs.length > 1;
                const first = legs[0];
                return { ticketId, legs, isParlay, created_at: first.created_at };
            });
        },

        _ticketGradeResult(ticket) {
            // If any leg has no grade_result, ticket is still open
            if (ticket.legs.some(l => !l.grade_result)) return null;
            // If any leg lost, ticket lost
            if (ticket.legs.some(l => l.grade_result === 'loss')) return 'loss';
            // If all pushed, ticket pushed
            if (ticket.legs.every(l => l.grade_result === 'push')) return 'push';
            // Otherwise won (all win or mix of win+push)
            return 'win';
        },

        _ticketPnl(ticket) {
            if (ticket.isParlay) {
                const result = this._ticketGradeResult(ticket);
                const stake = Number(ticket.legs[0].stake) || 0;
                if (result === 'loss') return -stake;
                if (result === 'push') return 0;
                if (result === 'win') {
                    // Combined decimal odds
                    let combinedDecimal = 1;
                    for (const leg of ticket.legs) {
                        const odds = Number(leg.odds) || 0;
                        combinedDecimal *= odds > 0 ? (1 + odds / 100) : (1 + 100 / Math.abs(odds));
                    }
                    return stake * combinedDecimal - stake;
                }
                return 0;
            }
            // Single bet
            return this.calcPickPnl(ticket.legs[0]);
        },

        get memberRecentActivity() {
            const items = [];

            // Group bets into tickets (parlays grouped, singles standalone)
            const tickets = this._groupBetsIntoTickets(this.memberDetailBets);

            for (const ticket of tickets) {
                const result = this._ticketGradeResult(ticket);
                const isSettled = ticket.legs.some(l => ['settled', 'graded'].includes(l.status));
                const isOpen = ticket.legs.some(l => ['pending', 'accepted', 'readyToGrade'].includes(l.status));

                let type, amount;
                if (result === 'win') {
                    type = 'won';
                    amount = this._ticketPnl(ticket);
                } else if (result === 'loss') {
                    type = 'lost';
                    amount = this._ticketPnl(ticket);
                } else if (result === 'push') {
                    type = 'push';
                    amount = 0;
                } else if (isOpen) {
                    type = 'bet_placed';
                    amount = -(Number(ticket.legs[0].stake) || 0);
                } else {
                    type = 'bet_placed';
                    amount = -(Number(ticket.legs[0].stake) || 0);
                }

                let description;
                if (ticket.isParlay) {
                    const legCount = ticket.legs.length;
                    // Combined odds
                    let combinedDecimal = 1;
                    for (const leg of ticket.legs) {
                        const odds = Number(leg.odds) || 0;
                        combinedDecimal *= odds > 0 ? (1 + odds / 100) : (1 + 100 / Math.abs(odds));
                    }
                    const combinedAmerican = combinedDecimal >= 2
                        ? '+' + Math.round((combinedDecimal - 1) * 100)
                        : Math.round(-100 / (combinedDecimal - 1));
                    description = legCount + '-leg Multi-Pick ' + combinedAmerican;
                } else {
                    const bet = ticket.legs[0];
                    description = (bet.side || 'Pick') + ' ' + this.formatOdds(bet.odds);
                }

                items.push({
                    date: ticket.created_at,
                    type,
                    description,
                    amount,
                    source: 'bet',
                    betId: ticket.legs[0].id,
                });
            }

            // Normalize ledger entries into activity items
            // Skip 'settlement' type entries — they duplicate bet results (auto-created when bets are graded)
            for (const entry of this.memberDetailLedger) {
                if (entry.type === 'settlement') continue;
                items.push({
                    date: entry.created_at,
                    type: entry.type || 'adjustment',
                    description: entry.reason || (entry.type === 'paymentLogged' ? 'Settle Up' : 'Balance adjustment'),
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
                case 'bet_placed': return { label: 'Open', cls: 'badge-warning' };
                case 'won': return { label: 'Won', cls: 'badge-success' };
                case 'lost': return { label: 'Lost', cls: 'badge-danger' };
                case 'push': return { label: 'Push', cls: 'badge-muted' };
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
            if (bet.grade_result === 'win') {
                return this.calcPotentialReturn(bet) - stake;
            } else if (bet.grade_result === 'loss') {
                return -stake;
            }
            return 0;
        },

        // ── Attention Tags ──
        computeAttentionTags(player, playerBets, playerLedger, groupAvgStake) {
            const tags = [];
            const now = Date.now();
            const sevenDaysMs = 7 * 24 * 60 * 60 * 1000;

            // Picks Pending: has pending bets
            if (playerBets.some(b => b.status === 'pending')) {
                tags.push({ key: 'pending', label: 'Picks Pending', color: 'yellow', desc: 'Has unreviewed picks waiting for acceptance.' });
            }

            // Overdue: positive balance (player owes bookie) with no payment in 7+ days
            if ((player.balance || 0) > 0) {
                const lastPayment = playerLedger
                    .filter(e => e.type === 'paymentLogged')
                    .sort((a, b) => new Date(b.created_at) - new Date(a.created_at))[0];
                const isOverdue = !lastPayment || (now - new Date(lastPayment.created_at).getTime()) > sevenDaysMs;
                if (isOverdue) {
                    tags.push({ key: 'overdue', label: 'Overdue', color: 'red', desc: 'Owes a balance with no payment in 7+ days.' });
                }
            }

            // Graded bets sorted by date for streak detection
            const gradedBets = playerBets
                .filter(b => b.grade_result)
                .sort((a, b) => new Date(b.created_at) - new Date(a.created_at));

            // On Heater: 3+ consecutive wins (most recent)
            if (gradedBets.length >= 3) {
                let winStreak = 0;
                for (const b of gradedBets) {
                    if (b.grade_result === 'win') winStreak++;
                    else break;
                }
                if (winStreak >= 3) {
                    tags.push({ key: 'heater', label: 'On Heater', color: 'green', desc: winStreak + ' consecutive wins — this member is on a hot streak.' });
                }
            }

            // Cold Streak: 3+ consecutive losses (most recent)
            if (gradedBets.length >= 3) {
                let lossStreak = 0;
                for (const b of gradedBets) {
                    if (b.grade_result === 'loss') lossStreak++;
                    else break;
                }
                if (lossStreak >= 3) {
                    tags.push({ key: 'cold', label: 'Cold Streak', color: 'blue', desc: lossStreak + ' consecutive losses — this member is struggling.' });
                }
            }

            // Whale: avg stake > 2x group average
            if (groupAvgStake > 0 && playerBets.length >= 3) {
                const playerAvgStake = playerBets.reduce((s, b) => s + (Number(b.stake) || 0), 0) / playerBets.length;
                if (playerAvgStake > 2 * groupAvgStake) {
                    tags.push({ key: 'whale', label: 'Whale', color: 'purple', desc: 'Average stake is 2x+ higher than the group average.' });
                }
            }

            // Degen: 5+ bets in any 24h window
            if (playerBets.length >= 5) {
                const sortedByDate = [...playerBets].sort((a, b) => new Date(a.created_at) - new Date(b.created_at));
                const dayMs = 24 * 60 * 60 * 1000;
                let isDegen = false;
                for (let i = 0; i <= sortedByDate.length - 5; i++) {
                    const windowStart = new Date(sortedByDate[i].created_at).getTime();
                    const windowEnd = new Date(sortedByDate[i + 4].created_at).getTime();
                    if (windowEnd - windowStart <= dayMs) {
                        isDegen = true;
                        break;
                    }
                }
                if (isDegen) {
                    tags.push({ key: 'degen', label: 'Degen', color: 'orange', desc: 'Placed 5+ picks within a 24-hour window.' });
                }
            }

            // Parlay Demon: 60%+ of bets are parlays
            if (playerBets.length >= 5) {
                const parlayCount = playerBets.filter(b => b.bet_type === 'parlay').length;
                if (parlayCount / playerBets.length >= 0.6) {
                    tags.push({ key: 'parlay', label: 'Parlay Demon', color: 'pink', desc: Math.round(parlayCount / playerBets.length * 100) + '% of picks are multi-picks.' });
                }
            }

            return tags;
        },

        showTagTooltip(tag, event) {
            const rect = event.target.getBoundingClientRect();
            this.tagTooltip = {
                label: tag.label,
                desc: tag.desc,
                x: rect.left + rect.width / 2,
                y: rect.bottom + 8,
            };
        },

        hideTagTooltip() {
            this.tagTooltip = null;
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
            let result = this.players;
            if (q) {
                result = result.filter(p =>
                    (p.name || '').toLowerCase().includes(q) ||
                    (p.display_name || '').toLowerCase().includes(q)
                );
            }
            // Sort
            const col = this.memberSortColumn;
            const asc = this.memberSortAsc;
            result = [...result].sort((a, b) => {
                let va, vb;
                if (col === 'name') {
                    va = (a.display_name || a.name || '').toLowerCase();
                    vb = (b.display_name || b.name || '').toLowerCase();
                } else if (col === 'balance') {
                    va = Number(a.balance) || 0;
                    vb = Number(b.balance) || 0;
                } else if (col === 'credit') {
                    va = Number(a.credit_limit) || 0;
                    vb = Number(b.credit_limit) || 0;
                } else if (col === 'status') {
                    va = a.auth_user_id ? 1 : 0;
                    vb = b.auth_user_id ? 1 : 0;
                } else {
                    return 0;
                }
                if (va < vb) return asc ? -1 : 1;
                if (va > vb) return asc ? 1 : -1;
                return 0;
            });
            return result;
        },

        sortMembers(column) {
            if (this.memberSortColumn === column) {
                this.memberSortAsc = !this.memberSortAsc;
            } else {
                this.memberSortColumn = column;
                this.memberSortAsc = true;
            }
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

        formatMarketType(market) {
            if (!market) return '';
            const map = { h2h: 'Moneyline', spreads: 'Spread', totals: 'Total', outright: 'Futures' };
            return map[market] || market;
        },

        formatOdds(odds) {
            if (!odds) return '—';
            const n = Number(odds);
            return n > 0 ? `+${n}` : String(n);
        },

        statusBadgeClass(bet) {
            if (typeof bet === 'string') bet = { status: bet };
            if (bet.grade_result === 'win') return 'badge-success';
            if (bet.grade_result === 'loss') return 'badge-danger';
            if (bet.grade_result === 'push') return 'badge-muted';
            switch (bet.status) {
                case 'settled': case 'graded': return 'badge-muted';
                case 'pending': case 'accepted': case 'readyToGrade': return 'badge-warning';
                case 'void': case 'declined': return 'badge-danger';
                default: return 'badge-muted';
            }
        },

        statusDisplayText(bet) {
            if (typeof bet === 'string') return bet;
            if (bet.grade_result === 'win') return 'Won';
            if (bet.grade_result === 'loss') return 'Lost';
            if (bet.grade_result === 'push') return 'Push';
            switch (bet.status) {
                case 'pending': return 'Pending';
                case 'accepted': return 'Open';
                case 'readyToGrade': return 'Awaiting Grade';
                case 'graded': return 'Graded';
                case 'settled': return 'Settled';
                case 'void': return 'Void';
                case 'declined': return 'Declined';
                default: return bet.status;
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
            const id = Date.now() + Math.random();
            this.toasts.push({ id, message, type });
            setTimeout(() => {
                this.toasts = this.toasts.filter(x => x.id !== id);
            }, 3000);
        },
    };
}
