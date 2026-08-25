/**
 * Booki Web Dashboard — Core JS
 * Alpine.js data store + Supabase client
 */

const SUPABASE_URL = 'https://vstfauqufwpdytmvjyfz.supabase.co';
/**
 * The only market types the game board renders: one moneyline, one spread and
 * one total per game. Alternate lines, team totals and odd/even are loaded per
 * game by the detail view, never in bulk — a single NFL game carries ~160
 * market rows, so pulling them into the board would truncate the query and
 * bloat every member's payload for lines the board cannot display anyway.
 */
const BOARD_MARKET_TYPES = ['moneyline', 'spread', 'total'];

const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZzdGZhdXF1ZndwZHl0bXZqeWZ6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjkyMjcwNjcsImV4cCI6MjA4NDgwMzA2N30.uwimFkR3pN8BODjjM5KnusptdZz_vcrxKnK_2LKfZHI';

/**
 * How far ahead members can see and bet games.
 *
 * Members rarely bet more than two days out, and beyond that a line is
 * speculative rather than useful. sync_games stores odds for 7 days — wider,
 * so a game already has a price the moment it becomes visible here.
 *
 * Outrights are exempt. Futures (championship winners and similar) are drawn
 * from the same events query the sport pages use, so bounding it by start_time
 * alone would hide every future — 9 live ones sit beyond 48h today. They are
 * matched back in by away_team, which is the sentinel the sync writes for an
 * outright.
 */
const ODDS_DISPLAY_WINDOW_MS = 48 * 60 * 60 * 1000;

function oddsDisplayCutoff() {
    return new Date(Date.now() + ODDS_DISPLAY_WINDOW_MS).toISOString();
}

/** PostgREST filter: inside the display window, OR an outright. */
function oddsDisplayFilter() {
    return `start_time.lte.${oddsDisplayCutoff()},away_team.eq.Outright`;
}

function dashboardApp() {
    return {
        // ── Auth ──
        supabase: null,
        session: null,
        bookie: null,

        // ── Dual-Role ──
        userRole: '', // '' (loading) | 'organizer' | 'player' | 'standalone'
        playerId: null,
        playerBookieId: null,
        playerRecord: null,
        playerBookie: null,

        // ── Route ──
        route: '',
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
        dashboardOpenBets: [],
        tonightEvents: [],

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

        // ── Onboarding ──
        onboardingRole: '',
        onboardingUseCase: '',
        onboardingGroupSize: '',
        onboardingReferral: '',
        isSubmittingOnboarding: false,

        async submitOnboarding() {
            this.isSubmittingOnboarding = true;
            const responses = {
                role_intent: this.onboardingRole,
                use_case: this.onboardingUseCase,
                group_size: this.onboardingGroupSize,
                referral_source: this.onboardingReferral,
                onboarded_at: new Date().toISOString(),
            };

            // Save to user_metadata (always works, no migration needed)
            try {
                await this.supabase.auth.updateUser({
                    data: { onboarding: responses }
                });
            } catch (e) {
                console.error('Failed to save onboarding to user_metadata:', e);
            }

            // Also try to save to onboarding_responses table (may not exist yet)
            try {
                await this.supabase.from('onboarding_responses').insert({
                    auth_user_id: this.session.user.id,
                    role_intent: this.onboardingRole || 'skipped',
                    use_case: this.onboardingUseCase || 'skipped',
                    group_size: this.onboardingGroupSize || 'skipped',
                    referral_source: this.onboardingReferral || 'skipped',
                });
            } catch (e) {
                // Table may not exist yet — that's fine
            }

            // Send welcome email (non-blocking)
            this.callEdgeFunction('send_welcome_email', {}).catch(() => {});

            this.isSubmittingOnboarding = false;
            this.route = 'organizer-welcome';
            window.location.hash = '#/organizer-welcome';
        },

        skipOnboarding() {
            // Send welcome email even if they skip (non-blocking)
            this.callEdgeFunction('send_welcome_email', {}).catch(() => {});
            this.route = 'organizer-welcome';
            window.location.hash = '#/organizer-welcome';
        },

        // ── Inline Editing ──
        isEditingName: false,
        isEditingCredit: false,
        isEditingWinLimit: false,
        editNameValue: '',
        editCreditValue: '',
        editWinLimitValue: '',

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

        startEditingWinLimit() {
            this.editWinLimitValue = this.memberDetail.win_limit != null ? String(this.memberDetail.win_limit) : '';
            this.isEditingWinLimit = true;
            this.$nextTick(() => {
                const el = document.getElementById('edit-winlimit-input');
                if (el) { el.focus(); el.select(); }
            });
        },

        async saveMemberWinLimit() {
            if (!this.memberDetail) return;
            const raw = this.editWinLimitValue.trim();

            // Empty = remove limit
            const newLimit = raw === '' ? null : parseFloat(raw);
            if (newLimit !== null && (isNaN(newLimit) || newLimit < 0)) {
                this.toast('Invalid win limit', 'error');
                this.isEditingWinLimit = false;
                return;
            }

            if (newLimit === (this.memberDetail.win_limit || null)) {
                this.isEditingWinLimit = false;
                return;
            }

            const { error } = await this.supabase
                .from('players')
                .update({ win_limit: newLimit })
                .eq('id', this.memberDetail.id);

            if (error) {
                this.toast('Failed to update win limit', 'error');
            } else {
                this.memberDetail.win_limit = newLimit;
                if (this.playerMap[this.memberDetail.id]) {
                    this.playerMap[this.memberDetail.id].win_limit = newLimit;
                }
                const idx = this.players.findIndex(p => p.id === this.memberDetail.id);
                if (idx >= 0) this.players[idx].win_limit = newLimit;
                this.toast(newLimit !== null ? 'Win limit updated' : 'Win limit removed', 'success');
            }

            this.isEditingWinLimit = false;
        },

        async saveMemberWinLimitAction(action) {
            if (!this.memberDetail) return;
            const { error } = await this.supabase
                .from('players')
                .update({ win_limit_action: action })
                .eq('id', this.memberDetail.id);

            if (error) {
                this.toast('Failed to update action', 'error');
            } else {
                this.memberDetail.win_limit_action = action;
                if (this.playerMap[this.memberDetail.id]) {
                    this.playerMap[this.memberDetail.id].win_limit_action = action;
                }
                const idx = this.players.findIndex(p => p.id === this.memberDetail.id);
                if (idx >= 0) this.players[idx].win_limit_action = action;
            }
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

        // ── Notification Preferences ──
        notifPrefs: { new_members: true, pick_submissions: false, risk_alerts: true, game_results: true },
        isLoadingNotifPrefs: false,

        // ── Acceptance Policy ──
        acceptancePolicy: null,
        isLoadingAcceptancePolicy: false,
        isSavingAcceptancePolicy: false,

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

        // ── Event Actions (Batch Grading) ──
        showBatchGradeModal: false,
        batchGradeOutcome: '',
        isBatchGrading: false,
        batchGradeProgress: '',
        showBatchVoidModal: false,
        isBatchVoiding: false,
        batchVoidProgress: '',
        showFinalScoreModal: false,
        finalScoreAway: '',
        finalScoreHome: '',
        isSavingFinalScore: false,
        showChangeStatusModal: false,
        eventNewStatus: '',
        isSavingStatus: false,
        showCancelWarning: false,

        // ── Attention Feed ──
        attentionExpanded: false,

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
        // Line-change confirmation. Populated when the server reports that a
        // price moved between the member seeing it and submitting.
        lineChanges: [],          // [{ market_id, submitted_odds, current_odds, current_side }]
        isConfirmingLineChange: false,
        showInviteModal: false,
        // '' until the organizer picks. An emailed invite and a shareable link
        // are different objects on the server — one is addressed to a verified
        // person and never expires for them, the other is a bearer code that
        // does — so the choice is made up front rather than inferred from
        // whether an optional field happened to be filled in.
        inviteMethod: '',
        inviteEmail: '',
        inviteCode: '',
        inviteUrl: '',
        inviteSentTo: '',
        inviteExpiresAt: '',
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

        // ── Settlement Snapshot (Dashboard) ──
        showSnapshotPayModal: false,
        snapshotPayPlayer: null,
        isSnapshotPaying: false,

        // ── Settlement ──
        settlementWeek: null,
        isLoadingSettlement: false,
        settlementReports: [],
        settlementFilter: 'all',
        showSettlementPayModal: false,
        settlementPayPlayer: null,
        isSettlementPaying: false,

        // ── Accept/Decline Picks ──
        acceptingBetId: null,
        decliningBetId: null,
        showDeclineModal: false,
        declineBetId: null,

        // ── Player Home ──
        playerLedgerEntries: [],
        playerBets: [],
        playerOpenStakes: 0,
        isLoadingPlayerHome: true,

        // ── Player Games ──
        playerEvents: [],
        playerMarkets: [],

        // Game detail — the full board for ONE game, loaded on demand.
        selectedGameId: null,
        gameDetail: null,
        gameDetailMarkets: [],
        isLoadingGameDetail: false,
        betSlipSelections: [],
        isLoadingPlayerEvents: true,
        playerEventSearch: '',
        playerSportFilter: '',
        playerTimeFilter: 'all',
        showBetSlip: false,
        collapsedSports: {},
        collapsedLeagues: {},
        _loadedMarketSports: {},
        _loadingMarketSports: {},

        // ── Player Sport Page ──
        selectedSportPage: '',
        selectedLeagueTab: '',
        isLoadingSportPage: false,
        sportPageOutrightMarkets: [],
        sportCategories: {
            basketball: { displayName: 'Basketball', leagues: [{id:'nba',displayName:'NBA'},{id:'ncaab',displayName:'NCAAB'},{id:'wnba',displayName:'WNBA'}] },
            football: { displayName: 'Football', leagues: [{id:'nfl',displayName:'NFL'},{id:'ncaaf',displayName:'NCAAF'}] },
            baseball: { displayName: 'Baseball', leagues: [{id:'mlb',displayName:'MLB'}] },
            hockey: { displayName: 'Hockey', leagues: [{id:'nhl',displayName:'NHL'}] },
            soccer: { displayName: 'Soccer', leagues: [{id:'epl',displayName:'EPL'},{id:'mls',displayName:'MLS'}] },
            mma: { displayName: 'MMA', leagues: [{id:'ufc',displayName:'UFC'}] },
            tennis: { displayName: 'Tennis', leagues: [{id:'atp',displayName:'ATP'},{id:'wta',displayName:'WTA'}] },
            golf: { displayName: 'Golf', leagues: [{id:'pga',displayName:'PGA'},{id:'masters',displayName:'Masters'},{id:'the_open',displayName:'The Open'},{id:'us_open',displayName:'US Open'}] },
        },

        // ── Player Track ──
        playerTrackFilter: 'all',
        isLoadingPlayerTrack: true,
        playerTrackEvents: {},

        // ── Player Ticket Detail ──
        playerTicketDetail: null,
        playerTicketLegs: [],
        isLoadingPlayerTicket: false,

        // ── Player Account ──
        isLoadingPlayerAccount: false,
        isBecomingOrganizer: false,
        playerActivityFilter: 'all',
        playerActivity: [],
        playerAccountNotifPrefs: { picks_graded: true, balance_changes: true, game_results: true },
        isLoadingPlayerNotifPrefs: false,
        isEditingPlayerName: false,
        editPlayerNameValue: '',
        playerCurrentPassword: '',
        playerNewPassword: '',
        playerConfirmPassword: '',
        isChangingPlayerPassword: false,
        playerPasswordError: '',
        showPlayerDeleteStep1: false,
        showPlayerDeleteStep2: false,
        playerDeleteConfirmText: '',
        isDeletingPlayerAccount: false,

        // ── Bet Slip ──
        betSlipMode: 'singles', // 'singles' | 'multi'
        betSlipStakes: {},
        betSlipMultiStake: '',
        betSlipActiveField: null, // tracks which input is focused: 'stake-{idx}', 'potential-{idx}', 'multi-stake', 'multi-potential'
        isSubmittingBets: false,
        betSlipSuccess: false,
        betSlipSuccessMessage: '',
        betSlipLastSelections: [],
        betSlipLastMode: 'singles',

        // ── Toasts ──
        toasts: [],

        // ── Init ──
        async init() {
            if (!SUPABASE_ANON_KEY) {
                console.error('Supabase anon key not configured');
                window.location.href = 'login.html';
                return;
            }

            this.supabase = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

            // Check session
            const { data: { session } } = await this.supabase.auth.getSession();
            if (!session) {
                window.location.href = 'login.html';
                return;
            }
            this.session = session;
            document.body.style.visibility = 'visible';

            // Listen for auth changes
            this.supabase.auth.onAuthStateChange((event, session) => {
                this.session = session;
                if (!session) window.location.href = 'login.html';
            });

            // Detect user role
            await this.detectUserRole();

            // Subscribe to realtime updates
            this.subscribeToRealtime();

            // Parse route
            this.parseRoute();
            window.addEventListener('hashchange', () => this.parseRoute());

            // Check subscription redirect params
            const params = new URLSearchParams(window.location.hash.split('?')[1] || '');
            if (params.get('success') === 'true') this.subscriptionSuccess = true;
            if (params.get('canceled') === 'true') this.subscriptionCanceled = true;

            // Load data based on role
            if (this.userRole === 'organizer') {
                await this.loadPlayers();
                await this.loadDashboard();
            } else if (this.userRole === 'player' || this.userRole === 'standalone') {
                await this.loadPlayerHome();
            }
        },

        // ── Routing ──
        isValidUUID(str) {
            return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(str);
        },

        parseRoute() {
            const prevRoute = this.route;
            const hash = window.location.hash.replace(/\?.*$/, '');
            const path = hash.replace('#/', '') || (this.userRole === 'organizer' ? 'dashboard' : 'player-games');

            // Organizer parameterized routes
            const memberMatch = path.match(/^members\/(.+)$/);
            const pickMatch = path.match(/^picks\/(.+)$/);
            const eventMatch = path.match(/^events\/(.+)$/);

            // Player parameterized routes
            const playerTicketMatch = path.match(/^player-ticket\/(.+)$/);
            const playerSportMatch = path.match(/^player-sport\/(.+)$/);
            const playerGameMatch = path.match(/^player-game\/(.+)$/);

            // Organizer routes
            const organizerRoutes = ['dashboard', 'members', 'picks', 'events', 'settlement', 'subscription', 'settings', 'onboarding', 'organizer-welcome', 'pro'];
            // Player routes
            const playerRoutes = ['player-games', 'player-track', 'player-account', 'player-sport', 'player-game', 'become-organizer', 'player-activity', 'player-change-password'];

            if (playerGameMatch) {
                if (!this.isValidUUID(playerGameMatch[1])) {
                    window.location.hash = '#/player-games';
                    return;
                }
                this.route = 'player-game';
                this.selectedGameId = playerGameMatch[1];
            } else if (eventMatch) {
                if (!this.isValidUUID(eventMatch[1])) {
                    window.location.hash = '#/events';
                    return;
                }
                this.route = 'event-detail';
                this.selectedEventId = eventMatch[1];
            } else if (memberMatch && this.userRole === 'organizer') {
                if (!this.isValidUUID(memberMatch[1])) {
                    window.location.hash = '#/members';
                    return;
                }
                this.route = 'member-detail';
                this.selectedPlayerId = memberMatch[1];
            } else if (pickMatch && this.userRole === 'organizer') {
                if (!this.isValidUUID(pickMatch[1])) {
                    window.location.hash = '#/picks';
                    return;
                }
                // Set back route based on where we came from
                if (prevRoute === 'member-detail' && this.selectedPlayerId) {
                    const name = this.memberDetail?.display_name || this.memberDetail?.name || this.playerMap[this.selectedPlayerId]?.name || 'Member';
                    this.pickBackRoute = '#/members/' + this.selectedPlayerId;
                    this.pickBackLabel = 'Back to ' + name;
                } else if (prevRoute !== 'pick-detail') {
                    this.pickBackRoute = '#/picks';
                    this.pickBackLabel = 'Back to Picks';
                }
                this.route = 'pick-detail';
                this.selectedBetId = pickMatch[1];
            } else if (playerTicketMatch && (this.userRole === 'player' || this.userRole === 'standalone')) {
                if (!this.isValidUUID(playerTicketMatch[1])) {
                    window.location.hash = '#/player-track';
                    return;
                }
                this.route = 'player-ticket';
                this.selectedBetId = playerTicketMatch[1];
            } else if (playerSportMatch && (this.userRole === 'player' || this.userRole === 'standalone')) {
                const sport = playerSportMatch[1].toLowerCase();
                if (!this.sportCategories[sport]) {
                    window.location.hash = '#/player-games';
                    return;
                }
                this.route = 'player-sport';
                this.selectedSportPage = sport;
                const sportLeagues = this.sportCategories[sport].leagues;
                if (!this.selectedLeagueTab || !sportLeagues.find(l => l.id === this.selectedLeagueTab)) {
                    this.selectedLeagueTab = sportLeagues[0]?.id || 'futures';
                }
            } else {
                // Validate route against user role
                if (this.userRole === 'organizer') {
                    this.route = organizerRoutes.includes(path) ? path : 'dashboard';
                } else {
                    this.route = playerRoutes.includes(path) ? path : 'player-games';
                }
                this.selectedPlayerId = null;
                this.selectedBetId = null;
            }

            // Load route-specific data (organizer)
            if (this.route === 'picks') this.loadPicks();
            if (this.route === 'pick-detail') this.loadPickDetail();
            if (this.route === 'members') this.loadInvites();
            if (this.route === 'member-detail') this.loadMemberDetail();
            if (this.route === 'settings') this.loadSettings();
            if (this.route === 'events') this.loadEvents();
            if (this.route === 'event-detail') this.loadEventDetail();
            if (this.route === 'settlement') this.loadSettlement();

            // Load route-specific data (player)
            if (this.route === 'player-games') this.loadPlayerGames();
            if (this.route === 'player-track') this.loadPlayerTrack();
            if (this.route === 'player-ticket') this.loadPlayerTicketDetail();
            if (this.route === 'player-account') this.loadPlayerAccount();
            if (this.route === 'player-activity') this.loadPlayerAccount();
            if (this.route === 'player-sport') this.loadSportPage();
            if (this.route === 'player-game') this.loadGameDetail(this.selectedGameId);
        },

        // ── Auth ──
        async logout() {
            this.unsubscribeFromRealtime();
            await this.supabase.auth.signOut();
            window.location.href = 'login.html';
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
            if (this.realtimeChannel) return;

            // Player realtime: subscribe to own ledger entries for live balance updates
            if (this.userRole === 'player' && this.playerId) {
                this.realtimeChannel = this.supabase
                    .channel('player-changes')
                    .on('postgres_changes', {
                        event: '*',
                        schema: 'public',
                        table: 'ledger_entries',
                        filter: `player_id=eq.${this.playerId}`
                    }, () => {
                        this._debouncedReload('player-ledger', () => {
                            this.loadPlayerHome();
                        });
                    })
                    .subscribe();
                return;
            }

            if (!this.bookie) return;

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

        // ── Role Detection ──
        async detectUserRole() {
            const userId = this.session.user.id;

            // 1. Check for bookie record
            const { data: bookieData } = await this.supabase
                .from('bookies')
                .select('*')
                .eq('auth_user_id', userId)
                .limit(1);

            // 2. Check for player record
            const { data: playerData } = await this.supabase
                .from('players')
                .select('*')
                .eq('auth_user_id', userId)
                .limit(1);

            const hasBookie = bookieData && bookieData.length > 0;
            const hasPlayer = playerData && playerData.length > 0;

            // Guard against spurious bookie records: if user is a player
            // under a DIFFERENT bookie, they're not a real organizer
            let isRealOrganizer = hasBookie;
            if (hasBookie && hasPlayer) {
                if (playerData[0].bookie_id !== bookieData[0].id) {
                    isRealOrganizer = false;
                }
            }

            if (isRealOrganizer) {
                // Route as organizer
                this.userRole = 'organizer';
                this.bookie = bookieData[0];
                this.isPro = this.bookie.tier === 'pro';
            } else if (hasPlayer && playerData[0].bookie_id) {
                // Route as player
                this.userRole = 'player';
                this.playerRecord = playerData[0];
                this.playerId = playerData[0].id;
                this.playerBookieId = playerData[0].bookie_id;

                // Fetch bookie settings for the player's organizer
                const { data: bookieSettings } = await this.supabase
                    .from('bookies')
                    .select('id, name, tier, allow_futures_parlays')
                    .eq('id', playerData[0].bookie_id)
                    .limit(1);

                if (bookieSettings && bookieSettings.length > 0) {
                    this.playerBookie = bookieSettings[0];
                }
            } else {
                // Before assuming this is a new organizer, check whether someone
                // already invited this address. Three people were invited, could
                // not claim the link because the invite page was broken, and
                // signed up directly the same day — at which point this branch
                // made each of them their own organizer instead of a member of
                // the book that invited them. Three groups became six empty ones.
                try {
                    const { data: claimed } = await this.supabase.functions.invoke('claim_invite', {
                        body: { auth_user_id: userId },
                    });
                    if (claimed && claimed.success && !this._reresolvingRole) {
                        // The player row now exists, so re-run detection rather
                        // than duplicating the routing branch. It cannot recurse
                        // past this point: the second pass takes the player
                        // branch above and never reaches here.
                        this._reresolvingRole = true;
                        try {
                            await this.detectUserRole();
                        } finally {
                            this._reresolvingRole = false;
                        }
                        return;
                    }
                } catch (err) {
                    // No pending invite is the normal case — fall through to
                    // creating an organizer account.
                    console.debug('No pending invite for this address');
                }

                // No bookie, no player, and nobody invited them — a genuine new
                // organizer signing up from the landing page.
                try {
                    const userName = this.session.user.user_metadata?.name
                        || this.session.user.email?.split('@')[0]
                        || 'My Book';
                    const { data: newBookie, error: createError } = await this.supabase
                        .from('bookies')
                        .insert({
                            auth_user_id: userId,
                            name: userName,
                            email: this.session.user.email,
                            tier: 'free',
                            default_credit_limit: 1000,
                            allow_futures_parlays: false,
                        })
                        .select()
                        .single();

                    if (createError) throw createError;

                    this.bookie = newBookie;
                    this.userRole = 'organizer';
                    this.isPro = false;

                    // Route to onboarding questionnaire for first-time organizers
                    this.route = 'onboarding';
                    window.location.hash = '#/onboarding';
                    return;
                } catch (err) {
                    console.error('Auto-create organizer failed:', err);
                    // Fallback to standalone if creation fails
                    this.userRole = 'standalone';
                }
            }

            // Default route based on role
            if (this.userRole === 'player') {
                const hash = window.location.hash.replace(/\?.*$/, '');
                if (!hash || hash === '#/' || hash === '#/dashboard') {
                    window.location.hash = '#/player-games';
                }
            } else if (this.userRole === 'standalone') {
                const hash = window.location.hash.replace(/\?.*$/, '');
                if (!hash || hash === '#/' || hash === '#/dashboard') {
                    window.location.hash = '#/player-games';
                }
            }
        },

        // ── Player Home ──
        async loadPlayerHome() {
            if (!this.playerId) return;
            this.isLoadingPlayerHome = true;

            // Fetch ledger entries for this player
            const { data: ledger } = await this.supabase
                .from('ledger_entries')
                .select('id, amount, type, description, bet_id, created_at')
                .eq('player_id', this.playerId)
                .order('created_at', { ascending: false });

            this.playerLedgerEntries = ledger || [];

            // Fetch bets for this player
            const { data: bets } = await this.supabase
                .from('bets')
                .select('id, event_id, side, odds, stake, status, grade_result, market, is_parlay, ticket_id, parlay_legs, created_at')
                .eq('player_id', this.playerId)
                .order('created_at', { ascending: false });

            this.playerBets = bets || [];

            // Calculate open stakes
            this.playerOpenStakes = this.playerBets
                .filter(b => ['pending', 'accepted'].includes(b.status))
                .reduce((sum, b) => sum + (Number(b.stake) || 0), 0);

            this.isLoadingPlayerHome = false;
        },

        get playerBalance() {
            // Sum all ledger entries for this player (internal: positive = player owes bookie)
            return this.playerLedgerEntries.reduce((sum, e) => sum + (Number(e.amount) || 0), 0);
        },

        get playerDisplayBalance() {
            // Negate for player display: positive = bookie owes player (credit)
            return -this.playerBalance;
        },

        computePlayerRecord() {
            const settled = this.playerBets.filter(b => b.status === 'settled' || b.grade_result);
            const wins = settled.filter(b => b.grade_result === 'win').length;
            const losses = settled.filter(b => b.grade_result === 'loss').length;
            const pushes = settled.filter(b => b.grade_result === 'push').length;
            return { wins, losses, pushes };
        },

        get playerWinRate() {
            const rec = this.computePlayerRecord();
            const total = rec.wins + rec.losses;
            return total > 0 ? Math.round((rec.wins / total) * 100) : 0;
        },

        get playerPnl() {
            // Sum ledger entries excluding paymentLogged (settle ups) for performance
            return this.playerLedgerEntries
                .filter(e => e.type !== 'paymentLogged')
                .reduce((sum, e) => sum + (Number(e.amount) || 0), 0);
        },

        get playerDisplayPnl() {
            // Negate for player display
            return -this.playerPnl;
        },

        get playerOpenPicksCount() {
            return this.playerBets.filter(b => ['pending', 'accepted', 'readyToGrade', 'graded'].includes(b.status)).length;
        },

        get playerCreditLimit() {
            return this.playerRecord?.credit_limit || 0;
        },

        get playerCreditUtilization() {
            if (!this.playerCreditLimit) return 0;
            const used = Math.max(0, this.playerBalance) + this.playerOpenStakes;
            return Math.min(100, Math.max(0, (used / this.playerCreditLimit) * 100));
        },

        get playerAvailableCredit() {
            if (!this.playerCreditLimit) return 0;
            return Math.max(0, this.playerCreditLimit - Math.max(0, this.playerBalance) - this.playerOpenStakes);
        },

        get playerWinLimit() {
            return this.playerRecord?.win_limit || null;
        },

        get playerNetWinnings() {
            return -this.playerBalance;
        },

        get isPlayerWinLimitReached() {
            if (this.playerWinLimit === null) return false;
            return this.playerNetWinnings >= this.playerWinLimit;
        },

        get playerWinLimitAction() {
            return this.playerRecord?.win_limit_action || 'block';
        },

        get playerRecentActivity() {
            // Last 10 ledger entries
            return this.playerLedgerEntries.slice(0, 10);
        },

        playerActivityTypeColor(entry) {
            if (entry.type === 'settlement') {
                // Check if it was a win or loss based on amount (internal: positive = player owes bookie = loss)
                return (entry.amount || 0) > 0 ? 'var(--danger)' : 'var(--success)';
            }
            if (entry.type === 'paymentLogged') return 'var(--accent-secondary)';
            if (entry.type === 'adjustment') return 'var(--warning)';
            return 'var(--text-muted)';
        },

        playerActivityTypeBadge(entry) {
            if (entry.type === 'settlement') return 'Graded';
            if (entry.type === 'paymentLogged') return 'Settlement';
            if (entry.type === 'adjustment') return 'Adjustment';
            return entry.type || '—';
        },

        playerActivityDescription(entry) {
            // Use stored description if it's already rich (not generic)
            if (entry.description && !['Bet won', 'Bet lost', 'Bet pushed', 'Parlay won', 'Parlay lost', 'Parlay pushed'].includes(entry.description)) {
                return entry.description;
            }

            // Enrich from linked bet
            if (entry.bet_id && entry.type === 'settlement') {
                const bet = this.playerBets.find(b => b.id === entry.bet_id || b.ticket_id === entry.bet_id);
                if (bet) {
                    const isWin = (entry.amount || 0) < 0; // internal: negative = bookie owes player = win
                    const isPush = bet.grade_result === 'push';
                    const result = isPush ? 'Push' : isWin ? 'Won' : 'Lost';

                    if (bet.is_parlay && bet.parlay_legs) {
                        const legCount = Array.isArray(bet.parlay_legs) ? bet.parlay_legs.length : 0;
                        const odds = bet.odds ? ' (' + this.formatOdds(bet.odds) + ')' : '';
                        return 'Multi-Pick \u00b7 ' + legCount + ' legs' + odds + ' \u2014 ' + result;
                    }

                    // Singles — show team + odds
                    const side = bet.side || '';
                    const odds = bet.odds ? ' (' + this.formatOdds(bet.odds) + ')' : '';
                    return side + odds + ' \u2014 ' + result;
                }

                // Check if bet_id is a ticket_id for a parlay
                const parlayBets = this.playerBets.filter(b => b.ticket_id === entry.bet_id);
                if (parlayBets.length > 0) {
                    const isWin = (entry.amount || 0) < 0;
                    const result = isWin ? 'Won' : 'Lost';
                    return 'Multi-Pick \u00b7 ' + parlayBets.length + ' legs \u2014 ' + result;
                }
            }

            // Fallback
            return entry.description || this.playerActivityTypeBadge(entry);
        },

        creditUtilizationColor(pct) {
            if (pct >= 100) return 'var(--danger)';
            if (pct >= 80) return '#FF8C00';
            if (pct >= 50) return 'var(--warning)';
            return 'var(--accent)';
        },

        // ── Player Track ──
        async loadPlayerTrack() {
            if (!this.playerId) return;
            this.isLoadingPlayerTrack = true;

            // Ensure player bets are loaded (reuse loadPlayerHome data)
            if (this.playerBets.length === 0 && !this.isLoadingPlayerHome) {
                await this.loadPlayerHome();
            }

            // Fetch events for bet enrichment (final scores, team names)
            const eventIds = [...new Set(this.playerBets.map(b => b.event_id).filter(Boolean))];
            if (eventIds.length > 0) {
                const { data: events } = await this.supabase
                    .from('events')
                    .select('id, home_team, away_team, start_time, status, sport, league, final_score')
                    .in('id', eventIds);

                this.playerTrackEvents = {};
                for (const ev of (events || [])) {
                    this.playerTrackEvents[ev.id] = ev;
                }
            }

            this.isLoadingPlayerTrack = false;
        },

        get playerTickets() {
            const ticketMap = {};
            for (const bet of this.playerBets) {
                const key = bet.ticket_id || bet.id;
                if (!ticketMap[key]) ticketMap[key] = [];
                ticketMap[key].push(bet);
            }
            return Object.entries(ticketMap).map(([ticketId, legs]) => {
                const isParlay = legs.length > 1 || legs[0]?.is_parlay;
                const first = legs[0];
                const stake = Number(first.stake) || 0;

                // Ticket-level grade result
                // If ANY leg has lost, the parlay is lost (no need to wait for all legs)
                let gradeResult = null;
                if (legs.some(l => l.grade_result === 'loss')) {
                    gradeResult = 'loss';
                } else if (legs.every(l => l.grade_result)) {
                    if (legs.every(l => l.grade_result === 'push')) gradeResult = 'push';
                    else gradeResult = 'win';
                }

                // Status
                const isOpen = legs.some(l => ['pending', 'accepted', 'readyToGrade', 'graded'].includes(l.status));
                const isVoid = legs.every(l => l.status === 'void');
                const status = isVoid ? 'void' : (gradeResult ? 'settled' : (isOpen ? 'open' : first.status));

                // Combined odds for parlays
                let combinedOdds = Number(first.odds) || 0;
                if (isParlay && legs.length > 1) {
                    let dec = 1;
                    for (const l of legs) {
                        dec *= this.americanToDecimal(l.odds);
                    }
                    combinedOdds = this.decimalToAmerican(dec);
                }

                // PnL
                let pnl = 0;
                if (gradeResult === 'win') {
                    if (isParlay && legs.length > 1) {
                        let dec = 1;
                        for (const l of legs) {
                            if (l.grade_result !== 'push') dec *= this.americanToDecimal(l.odds);
                        }
                        pnl = stake * dec - stake;
                    } else {
                        pnl = this.calcPickPnl(first);
                    }
                } else if (gradeResult === 'loss') {
                    pnl = -stake;
                }

                // Potential return (for open picks)
                let potentialReturn = 0;
                if (!gradeResult) {
                    if (isParlay && legs.length > 1) {
                        let dec = 1;
                        for (const l of legs) dec *= this.americanToDecimal(l.odds);
                        potentialReturn = stake * dec - stake;
                    } else {
                        potentialReturn = this.calcPotentialReturn(first) - stake;
                    }
                }

                // Event enrichment for singles
                const event = this.playerTrackEvents[first.event_id] || null;

                return {
                    ticketId,
                    legs,
                    isParlay,
                    gradeResult,
                    status,
                    stake,
                    combinedOdds,
                    pnl,
                    potentialReturn,
                    event,
                    created_at: first.created_at,
                    title: isParlay ? (legs.length + '-leg Multi-Pick') : (first.side || 'Pick'),
                    subtitle: isParlay ? '' : (event ? (event.away_team + ' @ ' + event.home_team) : ''),
                    finalScore: (!isParlay && event && event.final_score) ? event.final_score : null,
                };
            }).sort((a, b) => new Date(b.created_at) - new Date(a.created_at));
        },

        get playerTrackStats() {
            const rec = this.computePlayerRecord();
            const totalStaked = this.playerBets.reduce((sum, b) => sum + (Number(b.stake) || 0), 0);
            return {
                wins: rec.wins,
                losses: rec.losses,
                pushes: rec.pushes,
                totalStaked,
                pnl: this.playerDisplayPnl,
            };
        },

        get playerTrackFilterCounts() {
            const tickets = this.playerTickets;
            return {
                all: tickets.length,
                open: tickets.filter(t => t.status === 'open').length,
                won: tickets.filter(t => t.gradeResult === 'win').length,
                lost: tickets.filter(t => t.gradeResult === 'loss').length,
                pushed: tickets.filter(t => t.gradeResult === 'push').length,
            };
        },

        get filteredPlayerTickets() {
            const tickets = this.playerTickets;
            switch (this.playerTrackFilter) {
                case 'open': return tickets.filter(t => t.status === 'open');
                case 'won': return tickets.filter(t => t.gradeResult === 'win');
                case 'lost': return tickets.filter(t => t.gradeResult === 'loss');
                case 'pushed': return tickets.filter(t => t.gradeResult === 'push');
                default: return tickets;
            }
        },

        playerTicketStatusBadgeClass(ticket) {
            if (ticket.gradeResult === 'win') return 'badge-success';
            if (ticket.gradeResult === 'loss') return 'badge-danger';
            if (ticket.gradeResult === 'push') return 'badge-muted';
            if (ticket.status === 'void') return 'badge-danger';
            return 'badge-warning';
        },

        playerTicketStatusText(ticket) {
            if (ticket.gradeResult === 'win') return 'Won';
            if (ticket.gradeResult === 'loss') return 'Lost';
            if (ticket.gradeResult === 'push') return 'Push';
            if (ticket.status === 'void') return 'Void';
            return 'Open';
        },

        playerLegDotColor(leg) {
            if (leg.grade_result === 'win') return 'var(--accent)';
            if (leg.grade_result === 'loss') return 'var(--danger)';
            if (leg.grade_result === 'push') return 'var(--warning)';
            if (leg.status === 'void') return 'var(--text-muted)';
            return 'var(--text-muted)';
        },

        // ── Player Ticket Detail ──
        async loadPlayerTicketDetail() {
            if (!this.selectedBetId || !this.playerId) return;
            this.isLoadingPlayerTicket = true;
            this.playerTicketDetail = null;
            this.playerTicketLegs = [];

            // Fetch the bet by ID
            let { data, error } = await this.supabase
                .from('bets')
                .select('*')
                .eq('id', this.selectedBetId)
                .eq('player_id', this.playerId)
                .limit(1);

            // If not found by id, try ticket_id (parlay ticket links use ticket_id)
            if ((!data || data.length === 0) && !error) {
                const res = await this.supabase
                    .from('bets')
                    .select('*')
                    .eq('ticket_id', this.selectedBetId)
                    .eq('player_id', this.playerId)
                    .order('created_at')
                    .limit(10);
                data = res.data;
                error = res.error;
            }

            if (error || !data?.length) {
                console.error('Failed to load ticket detail');
                this.toast('Failed to load pick', 'error');
                this.isLoadingPlayerTicket = false;
                return;
            }

            const bet = data[0];

            // For parlays, fetch all legs by ticket_id (if we haven't already)
            let legs = data.length > 1 ? data : [bet];
            if (legs.length === 1 && bet.is_parlay && bet.ticket_id) {
                const { data: parlayLegs } = await this.supabase
                    .from('bets')
                    .select('*')
                    .eq('ticket_id', bet.ticket_id)
                    .eq('player_id', this.playerId)
                    .order('created_at');
                if (parlayLegs && parlayLegs.length > 0) {
                    legs = parlayLegs;
                }
            }

            // Enrich legs with event data
            const eventIds = [...new Set(legs.map(l => l.event_id).filter(Boolean))];
            const eventMap = {};
            if (eventIds.length > 0) {
                const { data: events } = await this.supabase
                    .from('events')
                    .select('id, home_team, away_team, sport, league, start_time, status, final_score')
                    .in('id', eventIds);
                for (const ev of (events || [])) {
                    eventMap[ev.id] = ev;
                }
            }

            // Enrich each leg with event info
            for (const leg of legs) {
                const ev = eventMap[leg.event_id];
                if (ev) {
                    leg._event_name = ev.away_team ? (ev.away_team + ' @ ' + ev.home_team) : ev.home_team;
                    leg._sport = ev.sport;
                    leg._league = ev.league;
                    leg._final_score = ev.final_score;
                    leg._start_time = ev.start_time;
                }
            }

            const isParlay = legs.length > 1 || bet.is_parlay;
            const stake = Number(bet.stake) || 0;

            // Combined odds for parlays
            let combinedOdds = Number(bet.odds) || 0;
            if (isParlay && legs.length > 1) {
                let dec = 1;
                for (const l of legs) {
                    dec *= this.americanToDecimal(l.odds);
                }
                combinedOdds = this.decimalToAmerican(dec);
            }

            // Ticket-level grade result
            // If ANY leg has lost, the parlay is lost (no need to wait for all legs)
            let gradeResult = null;
            if (legs.some(l => l.grade_result === 'loss')) {
                gradeResult = 'loss';
            } else if (legs.every(l => l.grade_result)) {
                if (legs.every(l => l.grade_result === 'push')) gradeResult = 'push';
                else gradeResult = 'win';
            }

            // PnL
            let pnl = 0;
            if (gradeResult === 'win') {
                if (isParlay && legs.length > 1) {
                    let dec = 1;
                    for (const l of legs) {
                        if (l.grade_result !== 'push') dec *= this.americanToDecimal(l.odds);
                    }
                    pnl = stake * dec - stake;
                } else {
                    pnl = this.calcPickPnl(bet);
                }
            } else if (gradeResult === 'loss') {
                pnl = -stake;
            }

            // Potential return (for open picks)
            let potentialReturn = 0;
            if (!gradeResult) {
                if (isParlay && legs.length > 1) {
                    let dec = 1;
                    for (const l of legs) dec *= this.americanToDecimal(l.odds);
                    potentialReturn = stake * dec;
                } else {
                    potentialReturn = this.calcPotentialReturn(bet);
                }
            }

            // Status
            const isOpen = legs.some(l => ['pending', 'accepted', 'readyToGrade', 'graded'].includes(l.status));
            const isVoid = legs.every(l => l.status === 'void');
            const status = isVoid ? 'void' : (gradeResult ? 'settled' : (isOpen ? 'open' : bet.status));

            // Build timeline
            const timeline = [];
            timeline.push({ type: 'placed', label: 'Pick Placed', date: bet.created_at });
            if (gradeResult) {
                const gradedAt = bet.updated_at;
                timeline.push({
                    type: 'graded',
                    label: gradeResult === 'win' ? 'Won' : gradeResult === 'loss' ? 'Lost' : 'Pushed',
                    date: gradedAt || bet.updated_at,
                });
            }

            this.playerTicketDetail = {
                bet,
                legs,
                isParlay,
                gradeResult,
                status,
                stake,
                combinedOdds,
                pnl,
                potentialReturn,
                timeline,
                title: isParlay ? (legs.length + '-leg Multi-Pick') : (bet.side || 'Pick'),
                subtitle: isParlay ? '' : (legs[0]._event_name || ''),
                finalScore: (!isParlay && legs[0]._final_score) ? legs[0]._final_score : null,
            };
            this.playerTicketLegs = legs;
            this.isLoadingPlayerTicket = false;
        },

        // ── Player Account ──
        async loadPlayerAccount() {
            this.isLoadingPlayerAccount = true;
            this.playerPasswordError = '';
            this.playerCurrentPassword = '';
            this.playerNewPassword = '';
            this.playerConfirmPassword = '';

            // Ensure player data is loaded
            if (this.playerBets.length === 0 && this.playerLedgerEntries.length === 0 && !this.isLoadingPlayerHome) {
                await this.loadPlayerHome();
            }

            // Load full activity (all ledger entries)
            this.playerActivity = this.playerLedgerEntries;

            // Load notification preferences
            await this.loadPlayerNotifPrefs();

            this.isLoadingPlayerAccount = false;
        },

        get filteredPlayerActivity() {
            if (this.playerActivityFilter === 'all') return this.playerActivity;
            if (this.playerActivityFilter === 'graded') return this.playerActivity.filter(e => e.type === 'settlement');
            if (this.playerActivityFilter === 'adjustments') return this.playerActivity.filter(e => e.type === 'adjustment');
            if (this.playerActivityFilter === 'settled') return this.playerActivity.filter(e => e.type === 'paymentLogged');
            return this.playerActivity;
        },

        get playerMemberSince() {
            if (!this.playerRecord?.created_at) return '';
            return new Date(this.playerRecord.created_at).toLocaleDateString('en-US', { month: 'long', year: 'numeric' });
        },

        async loadPlayerNotifPrefs() {
            if (!this.session?.user?.id) return;
            this.isLoadingPlayerNotifPrefs = true;
            const { data } = await this.supabase
                .from('notification_preferences')
                .select('picks_graded, balance_changes, game_results')
                .eq('user_id', this.session.user.id)
                .maybeSingle();
            if (data) {
                this.playerAccountNotifPrefs = {
                    picks_graded: data.picks_graded ?? true,
                    balance_changes: data.balance_changes ?? true,
                    game_results: data.game_results ?? true,
                };
            }
            this.isLoadingPlayerNotifPrefs = false;
        },

        async togglePlayerNotifPref(field) {
            if (!this.session?.user?.id) return;
            this.playerAccountNotifPrefs[field] = !this.playerAccountNotifPrefs[field];
            const { error } = await this.supabase
                .from('notification_preferences')
                .upsert({ user_id: this.session.user.id, [field]: this.playerAccountNotifPrefs[field] }, { onConflict: 'user_id' });
            if (error) {
                this.playerAccountNotifPrefs[field] = !this.playerAccountNotifPrefs[field];
                this.toast('Failed to update preference', 'error');
            } else {
                this.toast('Preference updated', 'success');
            }
        },

        startEditingPlayerName() {
            this.editPlayerNameValue = this.playerRecord?.display_name || this.playerRecord?.name || '';
            this.isEditingPlayerName = true;
            this.$nextTick(() => {
                const el = document.getElementById('edit-player-name-input');
                if (el) { el.focus(); el.select(); }
            });
        },

        async savePlayerName() {
            const newName = this.editPlayerNameValue.trim();
            if (!newName) {
                this.isEditingPlayerName = false;
                return;
            }
            const oldName = this.playerRecord?.display_name || this.playerRecord?.name;
            if (newName === oldName) {
                this.isEditingPlayerName = false;
                return;
            }

            // Use claim_player-style approach — direct update may be blocked by RLS
            const { error } = await this.supabase
                .from('players')
                .update({ display_name: newName })
                .eq('id', this.playerId);

            if (error) {
                // Fall back: try name column
                const { error: err2 } = await this.supabase
                    .from('players')
                    .update({ name: newName })
                    .eq('id', this.playerId);
                if (err2) {
                    this.toast('Failed to update name', 'error');
                    this.isEditingPlayerName = false;
                    return;
                }
                this.playerRecord.name = newName;
            } else {
                this.playerRecord.display_name = newName;
            }
            this.toast('Name updated', 'success');
            this.isEditingPlayerName = false;
        },

        async becomeOrganizer() {
            if (this.isBecomingOrganizer) return;
            this.isBecomingOrganizer = true;
            try {
                const userId = this.session.user.id;
                const userName = this.session.user.user_metadata?.full_name || this.session.user.email?.split('@')[0] || 'My Book';

                // Create bookie record
                const { data, error } = await this.supabase
                    .from('bookies')
                    .insert({
                        auth_user_id: userId,
                        name: userName,
                        email: this.session.user.email,
                        tier: 'free',
                        default_credit_limit: 1000,
                        allow_futures_parlays: false,
                    })
                    .select()
                    .single();

                if (error) throw error;

                // Switch to organizer role
                this.bookie = data;
                this.userRole = 'organizer';
                this.isPro = false;

                // Navigate to onboarding questionnaire
                this.route = 'onboarding';
                window.location.hash = '#/onboarding';
            } catch (err) {
                console.error('Become organizer error');
                this.toast('Failed to create organizer account. Please try again.', 'error');
            } finally {
                this.isBecomingOrganizer = false;
            }
        },

        async changePlayerPassword() {
            this.playerPasswordError = '';

            if (!this.playerCurrentPassword) {
                this.playerPasswordError = 'Current password is required';
                return;
            }
            if (this.playerNewPassword.length < 6) {
                this.playerPasswordError = 'New password must be at least 6 characters';
                return;
            }
            if (this.playerNewPassword !== this.playerConfirmPassword) {
                this.playerPasswordError = 'Passwords do not match';
                return;
            }

            this.isChangingPlayerPassword = true;

            const { error: signInError } = await this.supabase.auth.signInWithPassword({
                email: this.session.user.email,
                password: this.playerCurrentPassword,
            });

            if (signInError) {
                this.playerPasswordError = 'Current password is incorrect';
                this.isChangingPlayerPassword = false;
                return;
            }

            const { error } = await this.supabase.auth.updateUser({
                password: this.playerNewPassword,
            });

            if (error) {
                this.playerPasswordError = error.message || 'Failed to update password';
            } else {
                this.toast('Password updated', 'success');
                this.playerCurrentPassword = '';
                this.playerNewPassword = '';
                this.playerConfirmPassword = '';
            }

            this.isChangingPlayerPassword = false;
        },

        async deletePlayerAccount() {
            if (this.playerDeleteConfirmText !== 'DELETE') return;
            this.isDeletingPlayerAccount = true;

            try {
                const response = await this.callEdgeFunction('delete_account', {
                    idempotency_key: crypto.randomUUID(),
                });

                if (response.error) {
                    this.toast(response.error, 'error');
                } else {
                    this.toast('Account deleted', 'success');
                    this.showPlayerDeleteStep2 = false;
                    await this.supabase.auth.signOut();
                    window.location.href = 'login.html';
                }
            } catch (e) {
                this.toast(e.message || 'Failed to delete account', 'error');
            }

            this.isDeletingPlayerAccount = false;
        },

        // ── Player Games ──
        async loadPlayerGames() {
            this.isLoadingPlayerEvents = true;

            // Ensure balance/bets data is loaded for the balance bar
            if (this.playerBets.length === 0 && this.playerLedgerEntries.length === 0 && !this.isLoadingPlayerHome) {
                await this.loadPlayerHome();
            }

            // Fetch only event summaries (no markets — loaded lazily per sport)
            const now = new Date().toISOString();
            const { data: events } = await this.supabase
                .from('events')
                .select('id, home_team, away_team, start_time, status, sport, league')
                .is('bookie_id', null)
                .not('status', 'eq', 'final').not('status', 'eq', 'canceled')
                .gte('start_time', now)
                .or(oddsDisplayFilter())
                .order('start_time', { ascending: true });

            this.playerEvents = events || [];
            this.playerMarkets = [];
            this._loadedMarketSports = {};
            this._loadingMarketSports = {};

            // Auto-load markets for the first 2 visible sports
            const sportGroups = this.groupedPlayerEvents;
            const autoLoadSports = sportGroups.slice(0, 2).map(g => g.sport);
            await Promise.all(autoLoadSports.map(s => this.ensureMarketsForSport(s)));

            this.isLoadingPlayerEvents = false;
        },

        async ensureMarketsForSport(sportName) {
            if (this._loadedMarketSports[sportName] || this._loadingMarketSports[sportName]) return;
            this._loadingMarketSports[sportName] = true;

            const eventIds = this.playerEvents
                .filter(ev => this.formatSportName(ev.sport) === sportName && ev.away_team !== 'Outright')
                .map(ev => ev.id);

            if (eventIds.length > 0) {
                const BATCH = 50;
                const batches = [];
                for (let i = 0; i < eventIds.length; i += BATCH) {
                    batches.push(
                        this.supabase
                            // Board queries fetch ONLY the three types the
                            // board renders. The deep markets add ~160 rows a
                            // game, so a batch of four games would blow past
                            // this .limit() and silently drop core lines for
                            // everything after it. The full set is loaded per
                            // game by the game detail view instead, which also
                            // keeps them out of every member's sync payload.
                            .from('markets')
                            .select('id, event_id, type, side_a, side_b, odds_a, odds_b')
                            .in('event_id', eventIds.slice(i, i + BATCH))
                            .in('type', BOARD_MARKET_TYPES)
                            .limit(500)
                    );
                }
                const results = await Promise.all(batches);
                const newMarkets = results.flatMap(r => r.data || []);
                // Append to existing markets (don't replace)
                this.playerMarkets = [...this.playerMarkets, ...newMarkets];
            }

            this._loadedMarketSports[sportName] = true;
            this._loadingMarketSports[sportName] = false;
        },

        toggleSportCollapse(sport) {
            this.collapsedSports[sport] = !this.collapsedSports[sport];
            // Load markets when expanding
            if (!this.collapsedSports[sport]) {
                this.ensureMarketsForSport(sport);
            }
        },

        toggleLeagueCollapse(key) {
            this.collapsedLeagues[key] = !this.collapsedLeagues[key];
        },

        navigateToSportLeague(sportKey, leagueName) {
            // Find matching league tab ID from sportCategories
            const cat = this.sportCategories[sportKey];
            if (cat) {
                const match = cat.leagues.find(l =>
                    l.displayName.toUpperCase() === leagueName.toUpperCase() ||
                    l.id.toUpperCase() === leagueName.toUpperCase()
                );
                if (match) this.selectedLeagueTab = match.id;
            }
            window.location.hash = '#/player-sport/' + sportKey;
        },

        async loadSportPage() {
            this.isLoadingSportPage = true;
            const cat = this.sportCategories[this.selectedSportPage];
            if (!cat) { this.isLoadingSportPage = false; return; }

            // Ensure events are loaded
            if (this.playerEvents.length === 0) {
                // Fetch events inline instead of calling loadPlayerGames
                const now = new Date().toISOString();
                const { data: events } = await this.supabase
                    .from('events')
                    .select('id, home_team, away_team, start_time, status, sport, league')
                    .is('bookie_id', null)
                    .not('status', 'eq', 'final').not('status', 'eq', 'canceled')
                    .gte('start_time', now)
                    .or(oddsDisplayFilter())
                    .order('start_time', { ascending: true });
                this.playerEvents = events || [];
            }

            // Filter events for this sport client-side
            const sportName = cat.displayName; // e.g. "Basketball"
            const sportEventIds = this.playerEvents
                .filter(ev => this.formatSportName(ev.sport) === sportName && ev.away_team !== 'Outright')
                .map(ev => ev.id);

            const outrightEventIds = this.playerEvents
                .filter(ev => this.formatSportName(ev.sport) === sportName && ev.away_team === 'Outright')
                .map(ev => ev.id);

            // Fetch sport-specific markets + outrights in parallel
            const fetches = [];
            if (sportEventIds.length > 0) {
                fetches.push(
                    this.supabase
                        .from('markets')
                        .select('id, event_id, type, side_a, side_b, odds_a, odds_b')
                        .in('event_id', sportEventIds)
                        .in('type', BOARD_MARKET_TYPES)
                        .limit(500)
                );
            } else {
                fetches.push(Promise.resolve({ data: [] }));
            }
            if (outrightEventIds.length > 0) {
                fetches.push(
                    this.supabase
                        .from('markets')
                        .select('id, event_id, type, side_a, side_b, odds_a, odds_b')
                        .in('event_id', outrightEventIds)
                        .eq('type', 'outright')
                        .limit(1000)
                );
            } else {
                fetches.push(Promise.resolve({ data: [] }));
            }

            const [marketsRes, outrightsRes] = await Promise.all(fetches);
            this.playerMarkets = marketsRes.data || [];
            this.sportPageOutrightMarkets = outrightsRes.data || [];

            this.isLoadingSportPage = false;
        },

        sportToKey(displayName) {
            return Object.entries(this.sportCategories).find(([k, v]) => v.displayName === displayName)?.[0] || null;
        },

        get sportPageCurrentCat() {
            return this.sportCategories[this.selectedSportPage] || null;
        },

        get sportPageIsGolf() {
            return this.selectedSportPage === 'golf';
        },

        get sportPageLeagueEvents() {
            const cat = this.sportPageCurrentCat;
            if (!cat) return [];
            const league = cat.leagues.find(l => l.id === this.selectedLeagueTab);
            if (!league) return [];
            const now = new Date();
            return this.playerEvents.filter(ev => {
                if (ev.away_team === 'Outright') return false;
                if (this.formatSportName(ev.sport) !== cat.displayName) return false;
                if (ev.league !== league.displayName) return false;
                if (new Date(ev.start_time) <= now) return false;
                return true;
            });
        },

        get sportPageFuturesGrouped() {
            const cat = this.sportPageCurrentCat;
            if (!cat) return [];
            const outrightEvents = this.playerEvents.filter(ev =>
                ev.away_team === 'Outright' && this.formatSportName(ev.sport) === cat.displayName
            );
            const result = [];
            for (const ev of outrightEvents) {
                const markets = this.sportPageOutrightMarkets
                    .filter(m => m.event_id === ev.id)
                    .sort((a, b) => a.odds_a - b.odds_a);
                if (markets.length > 0) {
                    result.push({ eventName: ev.home_team, event: ev, markets });
                }
            }
            return result;
        },

        get sportPageLeagueOutrights() {
            // For golf: outright markets for the currently selected league tab
            const cat = this.sportPageCurrentCat;
            if (!cat) return [];
            const league = cat.leagues.find(l => l.id === this.selectedLeagueTab);
            if (!league) return [];
            const outrightEvents = this.playerEvents.filter(ev =>
                ev.away_team === 'Outright' &&
                this.formatSportName(ev.sport) === cat.displayName &&
                ev.league === league.displayName
            );
            const result = [];
            for (const ev of outrightEvents) {
                const markets = this.sportPageOutrightMarkets
                    .filter(m => m.event_id === ev.id)
                    .sort((a, b) => a.odds_a - b.odds_a);
                if (markets.length > 0) {
                    result.push({ eventName: ev.home_team, event: ev, markets });
                }
            }
            return result;
        },

        get playerMarketsByEvent() {
            const aliasMap = { moneyline: 'h2h', spread: 'spreads', total: 'totals' };
            const map = {};
            for (const m of this.playerMarkets) {
                if (!map[m.event_id]) map[m.event_id] = {};
                map[m.event_id][m.type] = m;
                if (aliasMap[m.type]) map[m.event_id][aliasMap[m.type]] = m;
            }
            return map;
        },

        get filteredPlayerEvents() {
            const q = this.playerEventSearch.toLowerCase();
            const sportFilter = this.playerSportFilter;
            const timeFilter = this.playerTimeFilter;

            const now = new Date();
            const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
            const todayEnd = new Date(todayStart.getTime() + 24 * 60 * 60 * 1000);
            const tomorrowEnd = new Date(todayStart.getTime() + 2 * 24 * 60 * 60 * 1000);
            const weekEnd = new Date(todayStart.getTime() + 7 * 24 * 60 * 60 * 1000);

            return this.playerEvents.filter(ev => {
                if (q) {
                    const home = (ev.home_team || '').toLowerCase();
                    const away = (ev.away_team || '').toLowerCase();
                    if (!home.includes(q) && !away.includes(q)) return false;
                }
                if (sportFilter) {
                    if (this.formatSportName(ev.sport) !== sportFilter) return false;
                }
                if (timeFilter !== 'all') {
                    const startTime = new Date(ev.start_time);
                    if (timeFilter === 'today' && (startTime < todayStart || startTime >= todayEnd)) return false;
                    if (timeFilter === 'tomorrow' && (startTime < todayEnd || startTime >= tomorrowEnd)) return false;
                    if (timeFilter === 'thisWeek' && startTime >= weekEnd) return false;
                }
                return true;
            });
        },

        get groupedPlayerEvents() {
            const sportMap = {};
            for (const ev of this.filteredPlayerEvents) {
                const sport = this.formatSportName(ev.sport);
                const league = this.formatLeagueName(ev.sport, ev.league);
                if (!sportMap[sport]) sportMap[sport] = { sport, sportKey: this.sportToKey(sport), leagues: {} };
                if (!sportMap[sport].leagues[league]) sportMap[sport].leagues[league] = [];
                sportMap[sport].leagues[league].push(ev);
            }
            return Object.values(sportMap).map(s => {
                const cat = s.sportKey ? this.sportCategories[s.sportKey] : null;
                const leagueEntries = Object.entries(s.leagues).map(([league, events]) => ({ league, events }));
                if (cat) {
                    // Sort leagues to match sportCategories tab order
                    const tabOrder = cat.leagues.map(l => l.displayName.toUpperCase());
                    leagueEntries.sort((a, b) => {
                        const ai = tabOrder.indexOf(a.league.toUpperCase());
                        const bi = tabOrder.indexOf(b.league.toUpperCase());
                        return (ai === -1 ? 999 : ai) - (bi === -1 ? 999 : bi);
                    });
                }
                return { ...s, leagues: leagueEntries };
            });
        },

        get playerSportOptions() {
            // Preserve order sports appear in the event list (by earliest start_time)
            const seen = new Set();
            const ordered = [];
            for (const ev of this.playerEvents) {
                const sport = this.formatSportName(ev.sport);
                if (!seen.has(sport)) {
                    seen.add(sport);
                    ordered.push(sport);
                }
            }
            return ordered;
        },

        isEventLocked(ev) {
            return new Date(ev.start_time) <= Date.now();
        },

        /**
         * Loads every market for a single game.
         *
         * Deliberately per-game and on demand. The board query is capped to
         * three types precisely so this data never travels in bulk; an NFL
         * game carries ~160 market rows and nobody needs them until they ask
         * for this screen.
         */
        async loadGameDetail(eventId) {
            if (!eventId) return;
            this.isLoadingGameDetail = true;
            this.gameDetail = null;
            this.gameDetailMarkets = [];
            try {
                const [{ data: ev }, { data: mk }] = await Promise.all([
                    this.supabase.from('events')
                        .select('id, away_team, home_team, start_time, status, league, sport, away_score, home_score')
                        .eq('id', eventId).maybeSingle(),
                    this.supabase.from('markets')
                        .select('id, event_id, type, side_a, side_b, odds_a, odds_b')
                        .eq('event_id', eventId)
                        .limit(1000),
                ]);
                if (!ev) { this.toast('Game not found', 'error'); return; }
                this.gameDetail = ev;
                this.gameDetailMarkets = mk || [];
            } catch (err) {
                console.error('loadGameDetail failed:', err);
                this.toast('Could not load this game', 'error');
            } finally {
                this.isLoadingGameDetail = false;
            }
        },

        /**
         * Groups a game's markets into the sections the screen renders.
         *
         * Ordering is by line value, not by insertion: the API returns
         * alternate lines in whatever order the book listed them, and a ladder
         * that jumps around is unreadable. Team totals sort by team first so a
         * team's ladder stays together.
         */
        get gameDetailSections() {
            const all = this.gameDetailMarkets;
            if (!all.length) return [];
            const byType = (t) => all.filter((m) => m.type === t);
            const lineOf = (m) => {
                const n = Number(this.extractLine(m.side_a));
                return Number.isFinite(n) ? n : 0;
            };
            const teamOf = (m) => String(m.side_a || '').replace(/\s+(Over|Under)\s+[-+\d.]+$/i, '');

            const sections = [];
            const main = ['moneyline', 'spread', 'total']
                .map((t) => byType(t)[0]).filter(Boolean);
            if (main.length) sections.push({ key: 'main', title: 'Main lines', markets: main });

            const alts = byType('alternate_spread').sort((a, b) => lineOf(a) - lineOf(b));
            if (alts.length) sections.push({ key: 'alt_spread', title: 'Alternate spreads', markets: alts });

            const altTotals = byType('alternate_total').sort((a, b) => lineOf(a) - lineOf(b));
            if (altTotals.length) sections.push({ key: 'alt_total', title: 'Alternate totals', markets: altTotals });

            const teamTotals = byType('team_total').sort((a, b) =>
                teamOf(a).localeCompare(teamOf(b)) || lineOf(a) - lineOf(b));
            if (teamTotals.length) sections.push({ key: 'team_total', title: 'Team totals', markets: teamTotals });

            const oddEven = byType('odd_even');
            if (oddEven.length) sections.push({ key: 'odd_even', title: 'Odd / Even', markets: oddEven });

            const outrights = byType('outright');
            if (outrights.length) sections.push({ key: 'outright', title: 'Futures', markets: outrights });

            return sections;
        },

        /**
         * Every game opens its detail view, whether or not it has extra lines.
         *
         * A per-game count on the board would need the market rows the board
         * deliberately does not load, and deriving "this league has deep
         * markets" client-side would duplicate the sync's allowlist and drift
         * from it. The detail view is worth opening regardless — it carries the
         * main lines, the start time and the score.
         */
        getMarketForEvent(eventId, marketType) {
            return this.playerMarketsByEvent[eventId]?.[marketType] || null;
        },

        formatSpreadLine(line) {
            if (line == null) return '';
            const n = Number(line);
            return n > 0 ? '+' + n : String(n);
        },

        // Extract numeric line from side_a/side_b strings like "Lakers -3.5" or "Over 215.5"
        extractLine(sideStr) {
            if (!sideStr) return null;
            const match = sideStr.match(/([+-]?\d+\.?\d*)$/);
            return match ? Number(match[1]) : null;
        },

        // Extract team name from side_a/side_b (everything before the line number)
        extractTeam(sideStr) {
            if (!sideStr) return '';
            return sideStr.replace(/\s*[+-]?\d+\.?\d*$/, '').trim();
        },

        get _selectionKeys() {
            const set = new Set();
            for (const s of this.betSlipSelections) {
                set.add(s.event_id + '|' + s.market_id + '|' + s.side_indicator);
            }
            return set;
        },

        isSelectionActive(eventId, marketId, sideIndicator) {
            return this._selectionKeys.has(eventId + '|' + marketId + '|' + sideIndicator);
        },

        toggleSelection(event, market, sideIndicator, side, odds) {
            if (!market || !odds) return;
            if (this.isEventLocked(event)) return;

            const idx = this.betSlipSelections.findIndex(
                s => s.event_id === event.id && s.market_id === market.id && s.side_indicator === sideIndicator
            );

            if (idx >= 0) {
                // Remove
                this.betSlipSelections.splice(idx, 1);
            } else {
                // Add
                this.betSlipSelections.push({
                    event_id: event.id,
                    market_id: market.id,
                    side,
                    side_indicator: sideIndicator,
                    odds: Number(odds),
                    event_name: (event.away_team || '') + ' @ ' + (event.home_team || ''),
                    market_type: market.type,
                });
            }
        },

        // ── Bet Slip ──
        removeSelection(index) {
            this.betSlipSelections.splice(index, 1);
            delete this.betSlipStakes[index];
            // Re-key stakes
            const newStakes = {};
            Object.keys(this.betSlipStakes).forEach(k => {
                const ki = Number(k);
                if (ki > index) newStakes[ki - 1] = this.betSlipStakes[k];
                else newStakes[ki] = this.betSlipStakes[k];
            });
            this.betSlipStakes = newStakes;
            if (this.betSlipSelections.length < 2 && this.betSlipMode === 'multi') {
                this.betSlipMode = 'singles';
            }
            if (this.betSlipSelections.length === 0) {
                this.showBetSlip = false;
            }
        },

        clearBetSlip() {
            this.betSlipSelections = [];
            this.betSlipStakes = {};
            this.betSlipMultiStake = '';
            this.betSlipMode = 'singles';
            this.betSlipSuccess = false;
        },

        addQuickStake(index, amount) {
            const current = Number(this.betSlipStakes[index]) || 0;
            this.betSlipStakes[index] = String(current + amount);
        },

        addQuickStakeMulti(amount) {
            const current = Number(this.betSlipMultiStake) || 0;
            this.betSlipMultiStake = String(current + amount);
        },

        calcToWin(odds, stake) {
            const o = Number(odds) || 0;
            const s = Number(stake) || 0;
            if (s <= 0) return 0;
            if (o > 0) return s * (o / 100);
            if (o < 0) return s * (100 / Math.abs(o));
            return 0;
        },

        sanitizeMoney(val) {
            let s = String(val).replace(/[^0-9.]/g, '');
            const parts = s.split('.');
            if (parts.length > 2) s = parts[0] + '.' + parts.slice(1).join('');
            if (parts.length === 2 && parts[1].length > 2) s = parts[0] + '.' + parts[1].slice(0, 2);
            return s;
        },

        calcStakeFromToWin(odds, toWin) {
            const o = Number(odds) || 0;
            const tw = Number(toWin) || 0;
            if (tw <= 0) return 0;
            if (o > 0) return tw / (o / 100);
            if (o < 0) return tw / (100 / Math.abs(o));
            return 0;
        },

        americanToDecimal(odds) {
            const o = Number(odds) || 0;
            if (o > 0) return 1 + o / 100;
            if (o < 0) return 1 + 100 / Math.abs(o);
            return 1;
        },

        decimalToAmerican(dec) {
            if (dec >= 2) return '+' + Math.round((dec - 1) * 100);
            if (dec > 1) return String(-Math.round(100 / (dec - 1)));
            return '+100';
        },

        /**
         * Routes where a member can pick lines, and therefore where the bet
         * slip must be reachable. Named because it is checked in three places —
         * this getter, the mobile bar and the sidebar — and adding the game
         * detail route to only some of them let a member select lines with no
         * way to see or submit them.
         */
        get isBettingRoute() {
            return this.route === 'player-games'
                || this.route === 'player-sport'
                || this.route === 'player-game';
        },

        get hasBetSlip() {
            return this.isBettingRoute
                && (this.betSlipSelections.length > 0 || this.betSlipSuccess);
        },

        get combinedMultiOdds() {
            if (this.betSlipSelections.length < 2) return 0;
            let combined = 1;
            for (const sel of this.betSlipSelections) {
                combined *= this.americanToDecimal(sel.odds);
            }
            return combined;
        },

        get combinedMultiOddsAmerican() {
            const dec = this.combinedMultiOdds;
            if (dec <= 1) return '+100';
            return this.decimalToAmerican(dec);
        },

        get multiToWin() {
            const stake = Number(this.betSlipMultiStake) || 0;
            if (stake <= 0) return 0;
            return stake * (this.combinedMultiOdds - 1);
        },

        get betSlipTotalStakes() {
            if (this.betSlipMode === 'multi') return Number(this.betSlipMultiStake) || 0;
            let total = 0;
            for (const key in this.betSlipStakes) {
                total += Number(this.betSlipStakes[key]) || 0;
            }
            return total;
        },

        get betSlipValid() {
            if (this.betSlipMode === 'singles') {
                // At least one selection with a positive stake
                let hasStake = false;
                for (let i = 0; i < this.betSlipSelections.length; i++) {
                    const s = Number(this.betSlipStakes[i]) || 0;
                    if (s > 0) hasStake = true;
                }
                if (!hasStake) return false;
            } else {
                if ((Number(this.betSlipMultiStake) || 0) <= 0) return false;
                if (this.betSlipSelections.length < 2) return false;
            }
            // Check credit
            if (this.betSlipTotalStakes > this.playerAvailableCredit && this.playerCreditLimit > 0) return false;
            // Win limit block
            if (this.isPlayerWinLimitReached && this.playerWinLimitAction === 'block') return false;
            return true;
        },

        get betSlipValidationMessage() {
            if (this.betSlipMode === 'singles') {
                let hasStake = false;
                for (let i = 0; i < this.betSlipSelections.length; i++) {
                    if ((Number(this.betSlipStakes[i]) || 0) > 0) hasStake = true;
                }
                if (!hasStake) return 'Enter a stake amount';
            } else {
                if (this.betSlipSelections.length < 2) return 'Need at least 2 selections for Multi-Pick';
                if ((Number(this.betSlipMultiStake) || 0) <= 0) return 'Enter a stake amount';
            }
            if (this.betSlipTotalStakes > this.playerAvailableCredit && this.playerCreditLimit > 0) {
                return 'Exceeds available credit';
            }
            if (this.isPlayerWinLimitReached && this.playerWinLimitAction === 'block') {
                return 'Win limit reached — picks suspended';
            }
            return '';
        },

        get betSlipWinLimitWarning() {
            if (!this.isPlayerWinLimitReached) return '';
            if (this.playerWinLimitAction === 'require_approval') return 'Picks will require organizer approval';
            return '';
        },

        get canSelectMulti() {
            if (this.betSlipSelections.length < 2) return false;
            // Check bookie futures parlay setting
            if (this.playerBookie && !this.playerBookie.allow_futures_parlays) {
                if (this.betSlipSelections.some(s => s.market_type === 'outright')) return false;
            }
            return true;
        },

        get betSlipButtonText() {
            if (this.betSlipMode === 'multi') return 'Place Multi-Pick';
            const count = this.betSlipSelections.filter((_, i) => (Number(this.betSlipStakes[i]) || 0) > 0).length;
            return count > 1 ? 'Place Picks' : 'Place Pick';
        },

        get betSlipStakedCount() {
            if (this.betSlipMode === 'multi') return this.betSlipSelections.length;
            return this.betSlipSelections.filter((_, i) => (Number(this.betSlipStakes[i]) || 0) > 0).length;
        },

        get betSlipTotalReturn() {
            if (this.betSlipMode === 'multi') {
                const stake = Number(this.betSlipMultiStake) || 0;
                if (stake <= 0) return 0;
                return stake + this.multiToWin;
            }
            let total = 0;
            for (let i = 0; i < this.betSlipSelections.length; i++) {
                const s = Number(this.betSlipStakes[i]) || 0;
                if (s > 0) {
                    total += s + this.calcToWin(this.betSlipSelections[i].odds, s);
                }
            }
            return total;
        },

        betSlipConfirmationMessages: [
            'Locked in!', 'Let it ride!', 'Good luck!', 'Sharp move!',
            'Dialed in!', 'Money time!', "Let's go!", 'Registered!',
            'On the board!', 'Ride or die!', 'Smooth operator!',
            'Big brain play!', 'Trust the process!', 'All gas!',
            'Chef kiss!', 'In it to win it!', 'Feeling lucky!',
            'No regrets!', 'LFG!', 'Fire pick!', 'Confident!',
            'Built different!', 'Main character energy!', 'Certified!',
            'Bold move!', 'This is the way!', 'Full send!',
            'Nothing but net!', 'Hammer time!', 'Clutch!',
            'Ice in your veins!', 'Risk it for the biscuit!',
            'Go big or go home!', 'Smooth sailing!',
        ],

        async submitBetSlip() {
            if (!this.betSlipValid || this.isSubmittingBets) return;
            this.isSubmittingBets = true;

            try {
                if (this.betSlipMode === 'singles') {
                    // Build bets array — only selections with stakes
                    const bets = [];
                    for (let i = 0; i < this.betSlipSelections.length; i++) {
                        const stake = Number(this.betSlipStakes[i]) || 0;
                        if (stake <= 0) continue;
                        const sel = this.betSlipSelections[i];
                        bets.push({
                            event_id: sel.event_id,
                            market_id: sel.market_id,
                            side: sel.side_indicator,
                            side_indicator: sel.side_indicator,
                            odds: sel.odds,
                            stake,
                        });
                    }

                    const response = await this.callEdgeFunction('submit_bets', {
                        player_id: this.playerId,
                        bookie_id: this.playerBookieId,
                        bets,
                        idempotency_key: crypto.randomUUID(),
                    });

                    // A moved line is not a failure — it needs the member's
                    // confirmation at the new price. This MUST be checked before
                    // the generic error throw: when every bet in the batch hits a
                    // moved line the server returns 'All bets failed validation'
                    // with the details in `failed`, and throwing first would show
                    // a dead-end error instead of the prompt.
                    const moved = (response.failed || []).filter(f => f.error === 'line_changed');
                    if (moved.length > 0) {
                        this.lineChanges = moved;
                        this.applyLineChangesToSlip(moved);
                        this.isSubmittingBets = false;
                        return;
                    }

                    // When every single in the batch fails, the server wraps the
                    // real reasons in a generic 'All bets failed validation'.
                    // Surface the first actual reason instead, so the member gets
                    // the same specific copy a parlay would give them.
                    if (response.error === 'All bets failed validation' &&
                        (response.failed || []).length > 0) {
                        throw new Error(response.failed[0].error || response.error);
                    }
                    if (response.error) throw new Error(response.error);

                    // Check partial success
                    if (response.results) {
                        const failed = response.results.filter(r => !r.success);
                        if (failed.length > 0 && failed.length < bets.length) {
                            this.toast(`${bets.length - failed.length} of ${bets.length} picks placed`, 'success');
                        }
                    }
                } else {
                    // Multi-pick / parlay
                    const legs = this.betSlipSelections.map(sel => ({
                        event_id: sel.event_id,
                        market_id: sel.market_id,
                        side: sel.side_indicator,
                        side_indicator: sel.side_indicator,
                        odds: sel.odds,
                    }));

                    const response = await this.callEdgeFunction('submit_parlay', {
                        player_id: this.playerId,
                        bookie_id: this.playerBookieId,
                        stake: Number(this.betSlipMultiStake),
                        combined_odds: Number(this.combinedMultiOddsAmerican.replace('+', '')),
                        legs,
                        idempotency_key: crypto.randomUUID(),
                    });

                    if (response.error === 'line_changed') {
                        this.lineChanges = [response];
                        this.applyLineChangesToSlip([response]);
                        this.isSubmittingBets = false;
                        return;
                    }
                    if (response.error) throw new Error(response.error);
                }

                // Save selections for re-use, then clear slip
                this.betSlipLastSelections = JSON.parse(JSON.stringify(this.betSlipSelections));
                this.betSlipLastMode = this.betSlipMode;
                this.betSlipSelections = [];
                this.betSlipStakes = {};
                this.betSlipMultiStake = '';

                // Show success
                const msgs = this.betSlipConfirmationMessages;
                this.betSlipSuccessMessage = msgs[Math.floor(Math.random() * msgs.length)];
                this.betSlipSuccess = true;

                // Refresh player data
                this.loadPlayerHome();
            } catch (err) {
                // Log the error itself. This used to log a bare string, which
                // meant the one place the real server message surfaced threw it
                // away — a 404 looked identical to a network drop.
                console.error('Submit bet slip error:', err);
                const raw = err && err.message;
                this.toast(this.humanizeBetError(raw), 'error');

                // A missing event or market means this page is holding a stale
                // copy of the board: sync_games rewrites events twice daily, and
                // a slip built before a rewrite points at ids that no longer
                // exist. Singles absorb this as a partial failure; a parlay is
                // all-or-nothing and 404s outright. Drop the dead selections and
                // reload rather than leaving unbettable odds on screen.
                if (this.isStaleBoardError(raw)) {
                    this.betSlipSelections = [];
                    this.betSlipStakes = {};
                    this.betSlipMultiStake = '';
                    this.showBetSlip = false;
                    this.loadPlayerGames();
                }
            }

            this.isSubmittingBets = false;
        },

        /**
         * Does this error mean the board on screen no longer matches the server?
         */
        isStaleBoardError(raw) {
            const msg = String(raw || '');
            return /^Events? not found/.test(msg) ||
                /^Market not found/.test(msg) ||
                msg === 'line_no_longer_offered' ||
                msg === 'Market has no price';
        },

        /**
         * Server errors are written for a log, not for a member — 'Events not
         * found: 0000...ff' is accurate and useless. Map the ones a member can
         * actually hit onto copy that says what to do next, and pass anything
         * unrecognised through so a new server error is never swallowed.
         */
        humanizeBetError(raw) {
            const msg = String(raw || '');
            if (this.isStaleBoardError(msg)) {
                return 'One of these games is no longer available. Refreshing the board — please rebuild your pick.';
            }
            if (/^Events locked/.test(msg) || msg === 'Event is locked for betting') {
                return 'Betting has closed on one of these games.';
            }
            if (msg === 'win_limit_reached') {
                return "You've hit your win limit. Ask your organizer to raise it.";
            }
            if (msg === 'open_bet_limit_reached') {
                return 'You have too many open picks. Wait for some to settle.';
            }
            if (msg === 'Player not found' || msg === 'Player does not belong to specified bookie' ||
                msg === 'Cannot submit bet for another player') {
                return 'Your account needs a refresh. Reload the page and try again.';
            }
            if (msg === 'Parlay requires at least 2 legs') {
                return 'A Multi-Pick needs at least 2 selections.';
            }
            if (msg === 'pro_required') return 'That feature needs Booki Pro.';
            if (msg === 'Unauthorized') return 'Your session has expired. Sign in again.';
            if (/^Stake must be/.test(msg)) return 'Enter a stake amount.';
            if (/^Odds must be/.test(msg)) return 'That price is no longer valid. Refresh and try again.';
            return msg || 'Failed to place pick';
        },

        closeBetSlipSuccess() {
            this.betSlipSuccess = false;
            this.showBetSlip = false;
        },

        reuseSelections() {
            this.betSlipSelections = JSON.parse(JSON.stringify(this.betSlipLastSelections));
            this.betSlipMode = this.betSlipLastMode;
            this.betSlipStakes = {};
            this.betSlipMultiStake = '';
            this.betSlipSuccess = false;
        },

        // ── Load Bookie ──
        async loadBookie() {
            const { data, error } = await this.supabase
                .from('bookies')
                .select('*')
                .eq('auth_user_id', this.session.user.id)
                .limit(1);

            if (error || !data?.length) {
                console.error('Failed to load bookie');
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
                console.error('Failed to load players');
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

            if (betsErr) console.error('Recent bets query failed');

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
                _betId: b.id,
                _betStatus: b.status,
            }));

            const merged = [...ledgerItems, ...betItems]
                .sort((a, b) => new Date(b.created_at) - new Date(a.created_at))
                .slice(0, 10);

            this.recentActivity = merged;

            // Exposure: fetch open bets for potential payout calculation
            const { data: openBets } = await this.supabase
                .from('bets')
                .select('stake, odds, player_id, status, event_id, side')
                .eq('bookie_id', this.bookie.id)
                .in('status', ['pending', 'accepted']);

            const openBetsList = openBets || [];
            this.dashboardOpenBets = openBetsList;
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
                    memberExposureMap[b.player_id] = { exposure: 0, openPicks: 0, openStakes: 0 };
                }
                const payout = this.calcPotentialReturn(b) - (Number(b.stake) || 0);
                memberExposureMap[b.player_id].exposure += payout;
                memberExposureMap[b.player_id].openPicks += 1;
                memberExposureMap[b.player_id].openStakes += Number(b.stake) || 0;
            }

            // Build dashboard members list sorted by exposure desc
            this.dashboardMembers = this.players
                .map(p => ({
                    ...p,
                    exposure: memberExposureMap[p.id]?.exposure || 0,
                    openPicks: memberExposureMap[p.id]?.openPicks || 0,
                    openStakes: memberExposureMap[p.id]?.openStakes || 0,
                }))
                .filter(p => p.status !== 'archived')
                .sort((a, b) => b.exposure - a.exposure);

            // Top risk member
            this.topRiskMember = this.dashboardMembers.length > 0 && this.dashboardMembers[0].exposure > 0
                ? this.dashboardMembers[0]
                : null;

            // Tonight's events: games starting between now and end of today (local timezone)
            const todayStart = new Date();
            const todayEnd = new Date();
            todayEnd.setHours(23, 59, 59, 999);
            const { data: tonightEvts } = await this.supabase
                .from('events')
                .select('id, home_team, away_team, start_time, status, sport, league')
                .is('bookie_id', null)
                .gte('start_time', todayStart.toISOString())
                .lte('start_time', todayEnd.toISOString())
                .not('status', 'eq', 'final').not('status', 'eq', 'canceled');
            this.tonightEvents = tonightEvts || [];

            // Sport Performance breakdown + attention tags data
            const { data: allBets } = await this.supabase
                .from('bets')
                .select('event_id, stake, odds, status, market, side, player_id, is_parlay, created_at, grade_result')
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

        // ── Attention Feed Alerts ──
        get attentionAlerts() {
            const alerts = [];
            if (!this.dashboardMembers || this.dashboardMembers.length === 0) return alerts;

            // Overdue alerts: members with positive balance and overdue tag
            for (const m of this.dashboardMembers) {
                const tags = m.attentionTags || [];
                if (tags.some(t => t.key === 'overdue')) {
                    alerts.push({
                        id: 'overdue-' + m.id,
                        severity: 'urgent',
                        category: 'Overdue',
                        icon: 'exclamation',
                        description: (m.display_name || m.name || 'Unknown') + ' — owes ' + this.formatCurrency(m.balance || 0),
                        badge: 'Overdue',
                        badgeClass: 'badge-danger',
                        amount: this.formatCurrency(m.balance || 0),
                        href: '#/members/' + m.id,
                    });
                }
            }

            // Near Credit Limit alerts: utilization >= 75%
            for (const m of this.dashboardMembers) {
                const limit = m.credit_limit || 1000;
                const utilization = (Math.max(0, m.balance || 0) + (m.openStakes || 0)) / limit * 100;
                if (utilization >= 75) {
                    alerts.push({
                        id: 'nearlimit-' + m.id,
                        severity: 'urgent',
                        category: 'Near Limit',
                        icon: 'exclamation',
                        description: (m.display_name || m.name || 'Unknown') + ' — ' + Math.round(utilization) + '% credit used',
                        badge: 'Near Limit',
                        badgeClass: 'badge-danger',
                        amount: Math.round(utilization) + '%',
                        href: '#/members/' + m.id,
                    });
                }
            }

            // High Exposure alerts: events with total bookie exposure >= $500
            // Group open bets by event_id
            const eventExposureMap = {};
            for (const m of this.dashboardMembers) {
                // Use openPicks and exposure from dashboardMembers (already computed)
            }
            // We need open bets — reconstruct from bets or use netExposure as proxy
            // Since we already have per-member exposure in dashboardMembers, group by event from bets data isn't stored
            // Instead, use members with high individual exposure as a signal
            // The allBets data isn't persisted at dashboard level, so we skip event-level grouping
            // and rely on the per-member exposure data

            // Sort: urgent first, then warning
            alerts.sort((a, b) => {
                if (a.severity === 'urgent' && b.severity !== 'urgent') return -1;
                if (a.severity !== 'urgent' && b.severity === 'urgent') return 1;
                return 0;
            });

            return alerts;
        },

        get attentionAlertCount() {
            return this.attentionAlerts.length;
        },

        get displayedAttentionAlerts() {
            if (this.attentionExpanded) return this.attentionAlerts;
            return this.attentionAlerts.slice(0, 5);
        },

        // ── Risk Watchlist ──
        get riskWatchlist() {
            if (!this.dashboardMembers || this.dashboardMembers.length === 0) return [];
            const sevenDaysAgo = Date.now() - 7 * 24 * 60 * 60 * 1000;
            const results = [];
            for (const m of this.dashboardMembers) {
                const signals = [];
                const tags = m.attentionTags || [];
                const limit = m.credit_limit || 1000;
                const utilization = (Math.max(0, m.balance || 0) + (m.openStakes || 0)) / limit * 100;

                // Near Limit: credit utilization >= 75%
                if (utilization >= 75) {
                    signals.push({ key: 'nearlimit', label: 'Near Limit', color: 'danger' });
                }
                // Overdue
                if (tags.some(t => t.key === 'overdue')) {
                    signals.push({ key: 'overdue', label: 'Overdue', color: 'danger' });
                }
                // Hot Streak: 3+ consecutive wins
                if (tags.some(t => t.key === 'heater')) {
                    signals.push({ key: 'hotstreak', label: 'Hot Streak', color: 'warning' });
                }
                // Losing Big: net P/L worse than -$500 in last 7 days
                const recentLedger = this.allLedgerEntries.filter(e =>
                    e.player_id === m.id &&
                    e.type !== 'paymentLogged' &&
                    new Date(e.created_at).getTime() >= sevenDaysAgo
                );
                const recentPnl = recentLedger.reduce((s, e) => s + (Number(e.amount) || 0), 0);
                // Internal positive = player owes bookie (player lost). If > 500, player is losing big
                if (recentPnl > 500) {
                    signals.push({ key: 'losingbig', label: 'Losing Big', color: 'danger' });
                }

                if (signals.length > 0) {
                    results.push({
                        ...m,
                        riskSignals: signals,
                        creditUtilization: Math.min(100, Math.max(0, utilization)),
                    });
                }
            }
            // Sort by signal count descending, return top 5
            results.sort((a, b) => b.riskSignals.length - a.riskSignals.length);
            return results.slice(0, 5);
        },

        get tonightsExposure() {
            const tonightIds = new Set(this.tonightEvents.map(e => e.id));
            if (tonightIds.size === 0) {
                return { gameCount: 0, totalPotentialLoss: 0, highestRiskGame: null, highExposure: false };
            }

            // Group open bets by tonight's event
            const eventExposure = {};
            for (const b of this.dashboardOpenBets) {
                if (!tonightIds.has(b.event_id)) continue;
                if (!eventExposure[b.event_id]) eventExposure[b.event_id] = 0;
                const payout = this.calcPotentialReturn(b) - (Number(b.stake) || 0);
                eventExposure[b.event_id] += payout;
            }

            const totalPotentialLoss = Object.values(eventExposure).reduce((s, v) => s + v, 0);

            // Find highest risk game
            let highestRiskGame = null;
            let maxExposure = 0;
            for (const [eventId, exposure] of Object.entries(eventExposure)) {
                if (exposure > maxExposure) {
                    maxExposure = exposure;
                    const evt = this.tonightEvents.find(e => e.id === eventId);
                    if (evt) {
                        highestRiskGame = {
                            id: eventId,
                            name: (evt.away_team || '?') + ' @ ' + (evt.home_team || '?'),
                            startTime: evt.start_time,
                            exposure: exposure,
                        };
                    }
                }
            }

            return {
                gameCount: this.tonightEvents.length,
                totalPotentialLoss,
                highestRiskGame,
                highExposure: maxExposure >= 1000,
            };
        },

        // ── Events Data ──
        async loadEvents() {
            this.isLoadingEvents = true;

            const fourteenDaysAgo = new Date(Date.now() - 14 * 24 * 60 * 60 * 1000).toISOString();
            // Upper bound deliberately 6 days, one inside sync_games' 7-day odds
            // storage window. Beyond it a game has no odds stored, so listing it
            // shows an organizer a priceless row. iOS has had this horizon since
            // 6788a6c; the web query never got it and was fetching every future
            // event on each load — 853 rows where 281 are renderable.
            // Outrights are exempt: they are long-dated by nature and would all
            // disappear under a plain upper bound.
            const organizerHorizon = new Date(Date.now() + 6 * 24 * 60 * 60 * 1000).toISOString();

            const { data, error } = await this.supabase
                .from('events')
                .select('*')
                .is('bookie_id', null)
                .gte('start_time', fourteenDaysAgo)
                .or(`start_time.lte.${organizerHorizon},away_team.eq.Outright`)
                .order('start_time', { ascending: true });

            if (error) {
                console.error('Failed to load events');
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

        formatLeagueName(sport, league) {
            // Prefer the event's league column if provided
            if (league) return league;
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
                const league = this.formatLeagueName(ev.sport, ev.league);
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

        // ── Settlement ──
        mostRecentSunday() {
            const d = new Date();
            d.setHours(0, 0, 0, 0);
            const day = d.getDay(); // 0=Sun
            if (day !== 0) d.setDate(d.getDate() - day);
            return d;
        },

        getWeekStart(sunday) {
            const d = new Date(sunday);
            d.setDate(d.getDate() - 6); // Monday
            return d;
        },

        formatWeekRange(sunday) {
            if (!sunday) return '';
            const mon = this.getWeekStart(sunday);
            const monStr = mon.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' });
            const sunStr = sunday.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric', year: 'numeric' });
            return monStr + ' – ' + sunStr;
        },

        navigateWeek(direction) {
            const current = this.settlementWeek || this.mostRecentSunday();
            const next = new Date(current);
            next.setDate(next.getDate() + (direction * 7));

            const mostRecent = this.mostRecentSunday();
            if (next > mostRecent) return;

            const fiveWeeksAgo = new Date(mostRecent);
            fiveWeeksAgo.setDate(fiveWeeksAgo.getDate() - 28);
            if (next < fiveWeeksAgo) return;

            this.settlementWeek = next;
            this.loadSettlement();
        },

        async loadSettlement() {
            if (!this.bookie) return;
            this.isLoadingSettlement = true;

            if (!this.settlementWeek) {
                this.settlementWeek = this.mostRecentSunday();
            }

            const weekEnd = new Date(this.settlementWeek);
            weekEnd.setHours(23, 59, 59, 999);
            const weekStart = this.getWeekStart(this.settlementWeek);

            const { data: allEntries, error } = await this.supabase
                .from('ledger_entries')
                .select('player_id, amount, type, created_at')
                .eq('bookie_id', this.bookie.id)
                .lte('created_at', weekEnd.toISOString());

            if (error) {
                console.error('Failed to load settlement');
                this.isLoadingSettlement = false;
                return;
            }

            const entries = allEntries || [];
            const activePlayers = this.players.filter(p => p.status !== 'archived');
            const reports = [];

            for (const player of activePlayers) {
                const playerEntries = entries.filter(e => e.player_id === player.id);
                let startingBalance = 0;
                let betsWon = 0;
                let betsLost = 0;
                let adjustments = 0;

                for (const e of playerEntries) {
                    const entryDate = new Date(e.created_at);
                    if (entryDate < weekStart) {
                        startingBalance += e.amount || 0;
                    } else if (entryDate <= weekEnd) {
                        if (e.type === 'settlement') {
                            if ((e.amount || 0) >= 0) {
                                betsLost += e.amount || 0;
                            } else {
                                betsWon += e.amount || 0;
                            }
                        } else if (e.type === 'adjustment') {
                            adjustments += e.amount || 0;
                        } else if (e.type === 'paymentLogged') {
                            adjustments += e.amount || 0;
                        }
                    }
                }

                const endingBalance = startingBalance + betsWon + betsLost + adjustments;
                const hasActivity = betsWon !== 0 || betsLost !== 0 || adjustments !== 0 || endingBalance !== 0;

                if (hasActivity || endingBalance !== 0) {
                    reports.push({
                        player_id: player.id,
                        name: player.display_name || player.name || 'Unknown',
                        startingBalance,
                        betsWon,
                        betsLost,
                        adjustments,
                        endingBalance,
                        collection_status: player.collection_status || null,
                        isPaid: endingBalance === 0,
                    });
                }
            }

            reports.sort((a, b) => Math.abs(b.endingBalance) - Math.abs(a.endingBalance));
            this.settlementReports = reports;
            this.isLoadingSettlement = false;
        },

        get filteredSettlementReports() {
            if (this.settlementFilter === 'all') return this.settlementReports;
            if (this.settlementFilter === 'unsettled') {
                return this.settlementReports.filter(r => r.endingBalance !== 0 && !r.isPaid);
            }
            if (this.settlementFilter === 'settled') {
                return this.settlementReports.filter(r => r.endingBalance === 0 || r.isPaid);
            }
            if (this.settlementFilter === 'attention') {
                return this.settlementReports.filter(r => r.collection_status === 'overdue');
            }
            return this.settlementReports;
        },

        get settlementOwedToYou() {
            return this.settlementReports
                .filter(r => r.endingBalance > 0)
                .reduce((sum, r) => sum + r.endingBalance, 0);
        },

        get settlementYouOwe() {
            return this.settlementReports
                .filter(r => r.endingBalance < 0)
                .reduce((sum, r) => sum + Math.abs(r.endingBalance), 0);
        },

        // ── Settlement Snapshot (Dashboard) ──
        get snapshotWeekRange() {
            const sunday = this.mostRecentSunday();
            return this.formatWeekRange(sunday);
        },

        get snapshotOwedToYou() {
            const activePlayers = this.players.filter(p => p.status !== 'archived');
            return activePlayers
                .filter(p => (p.balance || 0) > 0)
                .reduce((sum, p) => sum + (p.balance || 0), 0);
        },

        get snapshotYouOwe() {
            const activePlayers = this.players.filter(p => p.status !== 'archived');
            return activePlayers
                .filter(p => (p.balance || 0) < 0)
                .reduce((sum, p) => sum + Math.abs(p.balance || 0), 0);
        },

        get snapshotUnpaidCount() {
            return this.players.filter(p => p.status !== 'archived' && (p.balance || 0) !== 0).length;
        },

        get snapshotOverdueCount() {
            return this.players.filter(p => p.status !== 'archived' && p.collection_status === 'overdue').length;
        },

        get snapshotTopUnpaid() {
            return this.players
                .filter(p => p.status !== 'archived' && (p.balance || 0) !== 0)
                .sort((a, b) => Math.abs(b.balance || 0) - Math.abs(a.balance || 0))
                .slice(0, 3);
        },

        openSnapshotPay(player) {
            this.snapshotPayPlayer = player;
            this.showSnapshotPayModal = true;
        },

        async snapshotMarkPaid() {
            if (!this.snapshotPayPlayer || !this.bookie) return;
            this.isSnapshotPaying = true;

            try {
                await this.callEdgeFunction('adjust_balance', {
                    idempotency_key: crypto.randomUUID(),
                    player_id: this.snapshotPayPlayer.id,
                    amount: -(this.snapshotPayPlayer.balance || 0),
                    type: 'paymentLogged',
                    reason: 'Weekly settlement',
                });

                this.toast(`Marked ${this.snapshotPayPlayer.display_name || this.snapshotPayPlayer.name || 'member'} as paid`, 'success');
                this.showSnapshotPayModal = false;
                this.snapshotPayPlayer = null;
                await this.loadPlayerBalances();
                await this.loadDashboard();
            } catch (e) {
                this.toast(e.message || 'Failed to mark as paid', 'error');
            }

            this.isSnapshotPaying = false;
        },

        openSettlementPay(report) {
            this.settlementPayPlayer = report;
            this.showSettlementPayModal = true;
        },

        async settlementMarkPaid() {
            if (!this.settlementPayPlayer || !this.bookie) return;
            this.isSettlementPaying = true;

            try {
                const response = await this.callEdgeFunction('adjust_balance', {
                    idempotency_key: crypto.randomUUID(),
                    player_id: this.settlementPayPlayer.player_id,
                    amount: -this.settlementPayPlayer.endingBalance,
                    type: 'paymentLogged',
                    reason: 'Weekly settlement',
                });

                if (response.error) throw new Error(response.error);

                this.toast(`Marked ${this.settlementPayPlayer.name} as paid`, 'success');
                this.showSettlementPayModal = false;
                await this.loadPlayers();
                await this.loadSettlement();
            } catch (e) {
                this.toast(e.message || 'Failed to mark as paid', 'error');
            }

            this.isSettlementPaying = false;
        },

        exportSettlementCSV() {
            if (!this.settlementReports.length) return;

            const headers = ['Member Name', 'Starting Balance', 'Bets Won', 'Bets Lost', 'Adjustments', 'Ending Balance', 'Status'];
            const rows = this.settlementReports.map(r => [
                r.name,
                r.startingBalance.toFixed(2),
                r.betsWon.toFixed(2),
                r.betsLost.toFixed(2),
                r.adjustments.toFixed(2),
                r.endingBalance.toFixed(2),
                r.isPaid || r.endingBalance === 0 ? 'Settled' : 'Unpaid'
            ]);

            // Summary row
            const totals = this.settlementReports.reduce((acc, r) => ({
                startingBalance: acc.startingBalance + r.startingBalance,
                betsWon: acc.betsWon + r.betsWon,
                betsLost: acc.betsLost + r.betsLost,
                adjustments: acc.adjustments + r.adjustments,
                endingBalance: acc.endingBalance + r.endingBalance,
            }), { startingBalance: 0, betsWon: 0, betsLost: 0, adjustments: 0, endingBalance: 0 });

            rows.push([
                'TOTAL',
                totals.startingBalance.toFixed(2),
                totals.betsWon.toFixed(2),
                totals.betsLost.toFixed(2),
                totals.adjustments.toFixed(2),
                totals.endingBalance.toFixed(2),
                ''
            ]);

            const escapeCsvField = (field) => {
                const str = String(field);
                if (str.includes(',') || str.includes('"') || str.includes('\n')) {
                    return '"' + str.replace(/"/g, '""') + '"';
                }
                return str;
            };

            const csvString = [headers, ...rows].map(row => row.map(escapeCsvField).join(',')).join('\n');

            // Format filename date from the week-ending Sunday
            const d = this.settlementWeek || this.mostRecentSunday();
            const yyyy = d.getFullYear();
            const mm = String(d.getMonth() + 1).padStart(2, '0');
            const dd = String(d.getDate()).padStart(2, '0');
            const filename = `booki-settlement-${yyyy}-${mm}-${dd}.csv`;

            const blob = new Blob([csvString], { type: 'text/csv' });
            const url = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = filename;
            a.click();
            URL.revokeObjectURL(url);

            this.toast('Settlement report exported', 'success');
        },

        // ── Accept/Decline Picks ──
        async acceptBet(betId) {
            if (this.acceptingBetId) return;
            this.acceptingBetId = betId;

            try {
                const response = await this.callEdgeFunction('accept_bet', {
                    bet_id: betId,
                    idempotency_key: crypto.randomUUID(),
                });

                if (response.error) {
                    this.toast(response.error || 'Failed to accept pick', 'error');
                } else {
                    this.toast('Pick accepted', 'success');
                    await this.loadDashboard();
                    await this.loadPicks();
                }
            } catch (e) {
                this.toast(e.message || 'Failed to accept pick', 'error');
            }

            this.acceptingBetId = null;
        },

        openDeclineModal(betId) {
            this.declineBetId = betId;
            this.showDeclineModal = true;
        },

        async confirmDeclineBet() {
            if (!this.declineBetId || this.decliningBetId) return;
            this.decliningBetId = this.declineBetId;

            try {
                const response = await this.callEdgeFunction('decline_bet', {
                    bet_id: this.declineBetId,
                    idempotency_key: crypto.randomUUID(),
                });

                if (response.error) {
                    this.toast(response.error || 'Failed to decline pick', 'error');
                } else {
                    this.toast('Pick declined', 'success');
                    await this.loadDashboard();
                    await this.loadPicks();
                }
            } catch (e) {
                this.toast(e.message || 'Failed to decline pick', 'error');
            }

            this.decliningBetId = null;
            this.showDeclineModal = false;
            this.declineBetId = null;
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
                console.error('Failed to load event detail');
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

        get eventGradableBets() {
            return this.eventDetailBets.filter(b => ['accepted', 'readyToGrade'].includes(b.status));
        },

        get eventVoidableBets() {
            return this.eventDetailBets.filter(b => ['pending', 'accepted', 'readyToGrade'].includes(b.status));
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
                query = query.eq('is_parlay', false);
            } else if (this.pickTypeFilter === 'parlay') {
                query = query.eq('is_parlay', true);
            } else if (this.pickTypeFilter === 'futures') {
                query = query.eq('market', 'outright');
            }

            const { data, error } = await query;

            if (error) {
                console.error('Failed to load picks');
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
                .eq('bookie_id', this.bookie.id)
                .limit(1);

            if (error || !data?.length) {
                console.error('Failed to load pick detail');
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
            if (this.pickDetail.is_parlay && this.pickDetail.ticket_id) {
                const { data: legs } = await this.supabase
                    .from('bets')
                    .select('*')
                    .eq('ticket_id', this.pickDetail.ticket_id)
                    .eq('bookie_id', this.bookie.id)
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
            this.isEditingWinLimit = false;
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
                    console.error('Failed to load member detail');
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
                const parlayCount = playerBets.filter(b => b.is_parlay).length;
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

        // ── Batch Event Actions ──
        confirmBatchGrade(outcome) {
            this.batchGradeOutcome = outcome;
            this.batchGradeProgress = '';
            this.showBatchGradeModal = true;
        },

        async executeBatchGrade() {
            const bets = this.eventGradableBets;
            if (bets.length === 0) return;
            this.isBatchGrading = true;
            let successCount = 0;
            let errorCount = 0;

            for (let i = 0; i < bets.length; i++) {
                this.batchGradeProgress = `Grading pick ${i + 1} of ${bets.length}...`;
                try {
                    const response = await this.callEdgeFunction('grade_bet', {
                        bet_id: bets[i].id,
                        outcome: this.batchGradeOutcome,
                        idempotency_key: crypto.randomUUID(),
                    });
                    if (response.error) {
                        errorCount++;
                    } else {
                        successCount++;
                    }
                } catch (e) {
                    errorCount++;
                }
            }

            this.isBatchGrading = false;
            this.batchGradeProgress = '';
            this.showBatchGradeModal = false;

            if (errorCount === 0) {
                this.toast(`${successCount} pick${successCount !== 1 ? 's' : ''} graded as ${this.batchGradeOutcome}`, 'success');
            } else {
                this.toast(`${successCount} graded, ${errorCount} failed`, errorCount > 0 && successCount === 0 ? 'error' : 'success');
            }

            await this.loadEventDetail();
        },

        async executeBatchVoid() {
            const bets = this.eventVoidableBets;
            if (bets.length === 0) return;
            this.isBatchVoiding = true;
            let successCount = 0;
            let errorCount = 0;

            for (let i = 0; i < bets.length; i++) {
                this.batchVoidProgress = `Voiding pick ${i + 1} of ${bets.length}...`;
                try {
                    const response = await this.callEdgeFunction('grade_bet', {
                        bet_id: bets[i].id,
                        outcome: 'void',
                        idempotency_key: crypto.randomUUID(),
                    });
                    if (response.error) {
                        errorCount++;
                    } else {
                        successCount++;
                    }
                } catch (e) {
                    errorCount++;
                }
            }

            this.isBatchVoiding = false;
            this.batchVoidProgress = '';
            this.showBatchVoidModal = false;

            if (errorCount === 0) {
                this.toast(`${successCount} pick${successCount !== 1 ? 's' : ''} voided`, 'success');
            } else {
                this.toast(`${successCount} voided, ${errorCount} failed`, errorCount > 0 && successCount === 0 ? 'error' : 'success');
            }

            await this.loadEventDetail();
        },

        openFinalScoreModal() {
            if (this.eventDetail && this.eventDetail.final_score) {
                const parts = this.eventDetail.final_score.split('-');
                this.finalScoreAway = parts[0] || '';
                this.finalScoreHome = parts[1] || '';
            } else {
                this.finalScoreAway = '';
                this.finalScoreHome = '';
            }
            this.showFinalScoreModal = true;
        },

        async saveFinalScore() {
            if (!this.eventDetail) return;
            this.isSavingFinalScore = true;

            const finalScore = `${this.finalScoreAway}-${this.finalScoreHome}`;
            const { error } = await this.supabase
                .from('events')
                .update({ final_score: finalScore, status: 'final' })
                .eq('id', this.eventDetail.id);

            if (error) {
                this.toast('Failed to save final score', 'error');
            } else {
                this.toast('Final score saved', 'success');
                this.showFinalScoreModal = false;
                await this.loadEventDetail();
            }

            this.isSavingFinalScore = false;
        },

        async saveEventStatus() {
            if (!this.eventDetail || this.eventNewStatus === this.eventDetail.status) return;
            this.isSavingStatus = true;

            const { error } = await this.supabase
                .from('events')
                .update({ status: this.eventNewStatus })
                .eq('id', this.eventDetail.id);

            if (error) {
                this.toast('Failed to update status', 'error');
            } else {
                this.toast(`Status changed to ${this.eventNewStatus}`, 'success');
                this.showChangeStatusModal = false;
                await this.loadEventDetail();
            }

            this.isSavingStatus = false;
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
        resetInviteModal() {
            this.inviteMethod = '';
            this.inviteEmail = '';
            this.inviteCode = '';
            this.inviteUrl = '';
            this.inviteSentTo = '';
            this.inviteExpiresAt = '';
            this.inviteError = '';
        },

        async createInvite() {
            this.inviteError = '';

            if (this.inviteMethod === 'email') {
                const email = (this.inviteEmail || '').trim();
                if (!email || !email.includes('@')) {
                    this.inviteError = 'Enter the email address to send it to.';
                    return;
                }
            }

            this.isCreatingInvite = true;
            this.inviteCode = '';

            try {
                const response = await this.callEdgeFunction('create_invite', {
                    idempotency_key: crypto.randomUUID(),
                    // Only an email invite carries an address. A link invite must
                    // not, or the server would bind it to one person and the
                    // code would stop working for anyone else in the group chat.
                    email: this.inviteMethod === 'email'
                        ? this.inviteEmail.trim()
                        : undefined,
                });

                if (response.error) {
                    this.inviteError = response.error;
                } else if (this.inviteMethod === 'email') {
                    this.inviteSentTo = this.inviteEmail.trim();
                    this.toast('Invite sent', 'success');
                    this.loadInvites();
                } else {
                    this.inviteCode = response.invite_code;
                    this.inviteUrl = response.invite_url
                        || `https://bookisports.com/invite/${response.invite_code}`;
                    this.inviteExpiresAt = response.expires_at || '';
                    this.toast('Invite link created', 'success');
                    this.loadInvites();
                }
            } catch (e) {
                this.inviteError = e.message || 'Failed to create invite';
            }

            this.isCreatingInvite = false;
        },

        /** "in 23 hours" / "in 45 minutes" — a bearer code is short-lived. */
        inviteExpiryLabel() {
            if (!this.inviteExpiresAt) return '';
            const ms = new Date(this.inviteExpiresAt).getTime() - Date.now();
            if (ms <= 0) return 'expired';
            const hours = Math.floor(ms / 3600000);
            if (hours >= 1) return `in ${hours} hour${hours === 1 ? '' : 's'}`;
            const mins = Math.max(1, Math.round(ms / 60000));
            return `in ${mins} minute${mins === 1 ? '' : 's'}`;
        },


        /**
         * Update the slip in place with the prices the server is actually
         * offering, so confirming resubmits the new numbers rather than the
         * stale ones. The member sees what changed before deciding.
         */
        applyLineChangesToSlip(changes) {
            for (const change of changes) {
                const idx = this.betSlipSelections.findIndex(
                    sel => String(sel.market_id).toLowerCase() === String(change.market_id).toLowerCase()
                );
                if (idx === -1) continue;
                const sel = this.betSlipSelections[idx];
                sel.previous_odds = change.submitted_odds;
                sel.odds = change.current_odds;
                if (change.current_side) sel.side = change.current_side;
            }
        },

        /**
         * Confirm at the new price. This is an ordinary resubmission — it runs
         * through exactly the same server-side validation, so if the line moved
         * again in the meantime the member is prompted again rather than being
         * held to a price that is already gone.
         */
        async confirmLineChanges() {
            this.lineChanges = [];
            this.isConfirmingLineChange = true;
            try {
                await this.submitBetSlip();
            } finally {
                this.isConfirmingLineChange = false;
            }
        },

        dismissLineChanges() {
            this.lineChanges = [];
        },

        formatOddsChange(odds) {
            const n = Number(odds);
            return n > 0 ? `+${n}` : String(n);
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
            navigator.clipboard.writeText(`https://bookisports.com/invite/${code}`);
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
                console.error('Failed to load invites');
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
                console.error('Delete invite error');
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
                if (this.memberDetail?.id === this.settlePlayer.id) {
                    await this.loadMemberDetail();
                }
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
                if (this.memberDetail?.id === this.adjustPlayer.id) {
                    await this.loadMemberDetail();
                }
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
                    success_url: 'https://bookisports.com/dashboard/#/subscription?success=true',
                    cancel_url: 'https://bookisports.com/dashboard/#/subscription?canceled=true',
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
            this.loadNotifPrefs();
            this.loadAcceptancePolicy();
        },

        async loadNotifPrefs() {
            if (!this.session?.user?.id) return;
            this.isLoadingNotifPrefs = true;
            const { data, error } = await this.supabase
                .from('notification_preferences')
                .select('new_members, pick_submissions, risk_alerts, game_results')
                .eq('user_id', this.session.user.id)
                .maybeSingle();
            if (data) {
                this.notifPrefs = {
                    new_members: data.new_members ?? true,
                    pick_submissions: data.pick_submissions ?? false,
                    risk_alerts: data.risk_alerts ?? true,
                    game_results: data.game_results ?? true,
                };
            }
            this.isLoadingNotifPrefs = false;
        },

        async toggleNotifPref(field) {
            if (!this.session?.user?.id) return;
            this.notifPrefs[field] = !this.notifPrefs[field];
            const { error } = await this.supabase
                .from('notification_preferences')
                .upsert({ user_id: this.session.user.id, [field]: this.notifPrefs[field] }, { onConflict: 'user_id' });
            if (error) {
                this.notifPrefs[field] = !this.notifPrefs[field];
                this.toast('Failed to update notification preference', 'error');
            } else {
                this.toast('Notification preference updated', 'success');
            }
        },

        async loadAcceptancePolicy() {
            if (!this.bookie) return;
            this.isLoadingAcceptancePolicy = true;
            const { data, error } = await this.supabase
                .from('acceptance_policies')
                .select('*')
                .eq('bookie_id', this.bookie.id)
                .maybeSingle();
            if (data) {
                this.acceptancePolicy = { ...data };
            } else {
                this.acceptancePolicy = {
                    bookie_id: this.bookie.id,
                    max_stake: null,
                    require_approval_above: null,
                    auto_accept_enabled: true,
                    auto_accept_new_players: true,
                    auto_accept_parlays: true,
                    parlay_max_legs: null,
                    event_lock_offset_minutes: 0,
                };
            }
            this.isLoadingAcceptancePolicy = false;
        },

        async saveAcceptancePolicy() {
            if (!this.bookie || !this.acceptancePolicy) return;
            this.isSavingAcceptancePolicy = true;
            const payload = {
                bookie_id: this.bookie.id,
                max_stake: this.acceptancePolicy.max_stake || null,
                require_approval_above: this.acceptancePolicy.require_approval_above || null,
                auto_accept_enabled: this.acceptancePolicy.auto_accept_enabled ?? true,
                auto_accept_new_players: this.acceptancePolicy.auto_accept_new_players ?? true,
                auto_accept_parlays: this.acceptancePolicy.auto_accept_parlays ?? true,
                parlay_max_legs: this.acceptancePolicy.parlay_max_legs || null,
                event_lock_offset_minutes: parseInt(this.acceptancePolicy.event_lock_offset_minutes, 10) || 0,
            };
            const { error } = await this.supabase
                .from('acceptance_policies')
                .upsert(payload, { onConflict: 'bookie_id' });
            if (error) {
                this.toast('Failed to save acceptance rules', 'error');
            } else {
                this.toast('Acceptance rules saved', 'success');
            }
            this.isSavingAcceptancePolicy = false;
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
                    window.location.href = 'login.html';
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
                    window.location.href = 'login.html';
                }
            } catch (e) {
                this.toast(e.message || 'Failed to delete account', 'error');
            }

            this.isDeleting = false;
        },

        // ── Helpers ──
        async callEdgeFunction(name, body) {
            const controller = new AbortController();
            const timeoutId = setTimeout(() => controller.abort(), 10000);

            let res;
            try {
                res = await fetch(`${SUPABASE_URL}/functions/v1/${name}`, {
                    method: 'POST',
                    headers: {
                        'Authorization': `Bearer ${this.session.access_token}`,
                        'apikey': SUPABASE_ANON_KEY,
                        'Content-Type': 'application/json',
                    },
                    body: JSON.stringify(body),
                    signal: controller.signal,
                });
            } catch (err) {
                clearTimeout(timeoutId);
                if (err.name === 'AbortError') {
                    throw new Error('Request timed out. Please try again.');
                }
                throw new Error('Network error. Check your connection and try again.');
            }
            clearTimeout(timeoutId);

            const data = await res.json();
            if (!res.ok && !data.error) {
                throw new Error(`Failed to call ${name}. Please try again.`);
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

        formatDateTime(iso) {
            if (!iso) return '—';
            const d = new Date(iso);
            return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' }) + ' at ' +
                   d.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' });
        },

        formatMarketType(market) {
            if (!market) return '';
            const map = { h2h: 'Moneyline', moneyline: 'Moneyline', spreads: 'Spread', spread: 'Spread', totals: 'Total', total: 'Total', outright: 'Futures' };
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
            // `visible` is not optional: the template binds x-show="toast.visible",
            // so a toast pushed without it is undefined -> falsy -> rendered but
            // permanently hidden. Every toast in the dashboard, success and error
            // alike, was silently invisible because of that missing property.
            const id = Date.now() + Math.random();
            this.toasts.push({ id, message, type, visible: true });
            // Flip to hidden first so x-transition can play the leave animation,
            // then drop the row once it has finished.
            setTimeout(() => {
                const t = this.toasts.find(x => x.id === id);
                if (t) t.visible = false;
            }, 3000);
            setTimeout(() => {
                this.toasts = this.toasts.filter(x => x.id !== id);
            }, 3300);
        },
    };
}
