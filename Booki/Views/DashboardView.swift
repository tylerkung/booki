import SwiftUI
import SwiftData

/// Flag reason enum for player alerts
enum PlayerFlagReason: String, CaseIterable {
    case highBalance = "High Balance"
    case aging = "Aging"
    case both = "High Balance & Aging"
}

/// Model for flagged player display
struct FlaggedPlayer: Identifiable {
    let id: UUID
    let player: Player
    let balance: Decimal
    let daysSinceLastActivity: Int?
    let reason: PlayerFlagReason
}

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(OnboardingManager.self) private var onboardingManager: OnboardingManager?
    @EnvironmentObject private var syncService: SyncService
    @Query private var bets: [Bet]
    @Query private var events: [Event]
    @Query private var players: [Player]
    @Query private var ledgerEntries: [LedgerEntry]

    @State private var viewModel = DashboardViewModel()
    @State private var showingFlaggedPlayers = false
    @State private var showOnboardingFromCard = false

    // Alert Threshold settings
    @AppStorage("balanceThreshold") private var balanceThreshold: Double = 500.0
    @AppStorage("agingThreshold") private var agingThreshold: Int = 7

    /// Model for player balance display
    private struct PlayerBalanceItem: Identifiable {
        let id: UUID
        let player: Player
        let balance: Decimal
        let daysSinceLastActivity: Int?
    }

    /// Computed property for players with balances
    private var playerBalances: [PlayerBalanceItem] {
        players.filter { $0.status == .active }.compactMap { player in
            let playerLedger = ledgerEntries.filter { $0.player?.id == player.id }
            let balance = BalanceService.balanceOwed(from: playerLedger)

            // Skip players with zero balance
            guard balance != 0 else { return nil }

            // Find days since last activity
            let lastEntryDate = playerLedger.map { $0.createdAt }.max()
            let daysSinceLastActivity: Int? = lastEntryDate.map { lastDate in
                Calendar.current.dateComponents([.day], from: lastDate, to: Date()).day ?? 0
            }

            return PlayerBalanceItem(
                id: player.id,
                player: player,
                balance: balance,
                daysSinceLastActivity: daysSinceLastActivity
            )
        }
    }

    /// Players who owe the bookie (positive balance)
    private var playersOweYou: [PlayerBalanceItem] {
        playerBalances.filter { $0.balance > 0 }.sorted { $0.balance > $1.balance }
    }

    /// Players the bookie owes (negative balance)
    private var youOwePlayers: [PlayerBalanceItem] {
        playerBalances.filter { $0.balance < 0 }.sorted { $0.balance < $1.balance }
    }

    /// Total amount players owe
    private var totalPlayersOwe: Decimal {
        playersOweYou.reduce(Decimal.zero) { $0 + $1.balance }
    }

    /// Total amount bookie owes
    private var totalYouOwe: Decimal {
        abs(youOwePlayers.reduce(Decimal.zero) { $0 + $1.balance })
    }

    /// Players who need attention based on alert thresholds
    private var flaggedPlayers: [FlaggedPlayer] {
        let thresholdDecimal = Decimal(balanceThreshold)

        return players.filter { $0.status == .active }.compactMap { player in
            let playerLedger = ledgerEntries.filter { $0.player?.id == player.id }
            let balance = BalanceService.balanceOwed(from: playerLedger)

            // Only flag players who owe money (positive balance)
            guard balance > 0 else { return nil }

            // Find days since last activity
            let lastEntryDate = playerLedger.map { $0.createdAt }.max()
            let daysSinceLastActivity: Int? = lastEntryDate.map { lastDate in
                Calendar.current.dateComponents([.day], from: lastDate, to: Date()).day ?? 0
            }

            // Check thresholds
            let isHighBalance = balance >= thresholdDecimal
            let isAging = (daysSinceLastActivity ?? 0) >= agingThreshold

            // Determine flag reason
            let reason: PlayerFlagReason?
            if isHighBalance && isAging {
                reason = .both
            } else if isHighBalance {
                reason = .highBalance
            } else if isAging {
                reason = .aging
            } else {
                reason = nil
            }

            guard let flagReason = reason else { return nil }

            return FlaggedPlayer(
                id: player.id,
                player: player,
                balance: balance,
                daysSinceLastActivity: daysSinceLastActivity,
                reason: flagReason
            )
        }.sorted { $0.balance > $1.balance }
    }

    /// Count of flagged players
    var flaggedPlayersCount: Int {
        flaggedPlayers.count
    }

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Finish Setup Card (only if onboarding incomplete)
                if let manager = onboardingManager, !manager.isOnboardingComplete {
                    Section {
                        FinishSetupCard(
                            onboardingManager: manager,
                            onResume: { showOnboardingFromCard = true }
                        )
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                // MARK: - Attention Feed Section
                Section {
                    AttentionFeedView()
                } header: {
                    Text("Attention")
                        .foregroundStyle(Theme.textMuted)
                }
                .listRowBackground(Theme.cardBackground)

                // MARK: - Settlement Snapshot Section
                Section {
                    SettlementSnapshotCard()
                } header: {
                    Text("Reconciliation")
                        .foregroundStyle(Theme.textMuted)
                }
                .listRowBackground(Theme.cardBackground)

                // MARK: - Player Risk Watchlist Section
                Section {
                    PlayerRiskWatchlistCard()
                } header: {
                    Text("Member Risk")
                        .foregroundStyle(Theme.textMuted)
                }
                .listRowBackground(Theme.cardBackground)

                // MARK: - Tonight's Exposure Section
                Section {
                    TonightsExposureCard()
                } header: {
                    Text("Tonight's Activity")
                        .foregroundStyle(Theme.textMuted)
                }
                .listRowBackground(Theme.cardBackground)

                // MARK: - Activity Section (existing metrics)

                // Alert Banner
                if !flaggedPlayers.isEmpty {
                    Section {
                        Button {
                            showingFlaggedPlayers = true
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(
                                            RadialGradient(
                                                colors: [Theme.danger.opacity(0.4), Theme.danger.opacity(0)],
                                                center: .center,
                                                startRadius: 0,
                                                endRadius: 24
                                            )
                                        )
                                        .frame(width: 48, height: 48)

                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(Theme.title2)
                                        .foregroundStyle(
                                            LinearGradient(
                                                colors: [Theme.danger, Theme.accentTertiary],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                        .shadow(color: Theme.danger.opacity(0.5), radius: 4, x: 0, y: 0)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(flaggedPlayersCount) member\(flaggedPlayersCount == 1 ? "" : "s") need\(flaggedPlayersCount == 1 ? "s" : "") attention")
                                        .font(Theme.font(size: 15, weight: .bold))
                                        .foregroundStyle(Theme.textPrimary)

                                    Text("Tap to view flagged members")
                                        .font(Theme.caption)
                                        .foregroundStyle(Theme.textSecondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right.circle.fill")
                                    .font(Theme.title3)
                                    .foregroundStyle(Theme.danger.opacity(0.6))
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                                    .fill(
                                        LinearGradient(
                                            colors: [Theme.danger.opacity(0.15), Theme.accentTertiary.opacity(0.08)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Theme.cornerRadius)
                                            .stroke(
                                                LinearGradient(
                                                    colors: [Theme.danger.opacity(0.4), Theme.accentTertiary.opacity(0.2)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 1
                                            )
                                    )
                            )
                            .shadow(color: Theme.danger.opacity(0.2), radius: 8, x: 0, y: 4)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                    } header: {
                        Text("Activity")
                            .foregroundStyle(Theme.textMuted)
                    }
                }

                // Balances
                balancesSection

                // Exposure Overview
                Section {
                    ExposureCard(totalExposure: viewModel.totalExposure)
                } header: {
                    if flaggedPlayers.isEmpty && playersOweYou.isEmpty && youOwePlayers.isEmpty {
                        Text("Activity")
                            .foregroundStyle(Theme.textMuted)
                    }
                }
                .listRowBackground(Theme.cardBackground)

                // Pending Bets Count
                Section {
                    PendingBetsCard(count: viewModel.pendingBetsCount)
                }
                .listRowBackground(Theme.cardBackground)

                // Pending Bets Queue
                Section {
                    if viewModel.pendingBets.isEmpty {
                        Text("No pending picks")
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        ForEach(viewModel.pendingBets) { bet in
                            PendingBetRow(
                                bet: bet,
                                eventName: eventName(for: bet),
                                onAccept: { acceptBet(bet) },
                                onDecline: { declineBet(bet) }
                            )
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    declineBet(bet)
                                } label: {
                                    Label("Decline", systemImage: "xmark.circle")
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    acceptBet(bet)
                                } label: {
                                    Label("Accept", systemImage: "checkmark.circle")
                                }
                                .tint(Theme.accent)
                            }
                        }
                    }
                } header: {
                    Text("Pending Picks Queue")
                }
                .listRowBackground(Theme.cardBackground)

                // Top Risk Events
                Section {
                    if viewModel.topRiskEvents.isEmpty {
                        Text("No open activity")
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        ForEach(viewModel.topRiskEvents) { item in
                            if let event = events.first(where: { $0.id.uuidString.lowercased() == item.eventId.lowercased() }) {
                                NavigationLink(value: event) {
                                    RiskEventRow(item: item)
                                }
                            } else {
                                RiskEventRow(item: item)
                            }
                        }
                    }
                } header: {
                    Text("Top Activity Events")
                }
                .listRowBackground(Theme.cardBackground)

                // MARK: - Settlements Section
                Section {
                    NavigationLink {
                        WeeklySettlementView()
                    } label: {
                        HStack {
                            Image(systemName: "calendar.badge.clock")
                                .font(Theme.title2)
                                .foregroundStyle(Theme.accent)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Weekly Reconciliation")
                                    .font(Theme.subheadline)
                                    .foregroundStyle(Theme.textPrimary)

                                Text("View summary and export")
                                    .font(Theme.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(Theme.caption)
                                .foregroundStyle(Theme.textMuted)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Reconciliation")
                }
                .listRowBackground(Theme.cardBackground)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Dashboard")
            .refreshable {
                viewModel.refresh(bets: bets, events: events)
            }
            .onAppear {
                viewModel.refresh(bets: bets, events: events)
            }
            .onChange(of: bets.count) {
                viewModel.refresh(bets: bets, events: events)
            }
            .onChange(of: bets.map { $0.status }) {
                viewModel.refresh(bets: bets, events: events)
            }
            .navigationDestination(for: Event.self) { event in
                EventDetailView(event: event)
            }
            .navigationDestination(for: Player.self) { player in
                PlayerDetailView(player: player)
            }
            .sheet(isPresented: $showingFlaggedPlayers) {
                FlaggedPlayersView(flaggedPlayers: flaggedPlayers)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SyncStatusIndicator(syncService: syncService)
                }
            }
            .fullScreenCover(isPresented: $showOnboardingFromCard) {
                if let manager = onboardingManager {
                    OnboardingContainerView(
                        onboardingManager: manager,
                        startAt: manager.nextIncompleteStep,
                        onComplete: { showOnboardingFromCard = false },
                        onSkip: { showOnboardingFromCard = false }
                    )
                }
            }
        }
    }

    // MARK: - Helper Methods

    private func eventName(for bet: Bet) -> String {
        if let event = events.first(where: { $0.id.uuidString.lowercased() == bet.eventId.lowercased() }) {
            return "\(event.awayTeam) @ \(event.homeTeam)"
        }
        return "Event \(bet.eventId.prefix(8))"
    }

    private func acceptBet(_ bet: Bet) {
        let result = BetService.acceptBet(bet)
        switch result {
        case .success:
            viewModel.refresh(bets: bets, events: events)
        case .failure:
            break
        }
    }

    private func declineBet(_ bet: Bet) {
        let result = BetService.declineBet(bet)
        switch result {
        case .success:
            viewModel.refresh(bets: bets, events: events)
        case .failure:
            break
        }
    }

    // MARK: - Balances Section

    /// Whether the Activity section header should appear on the balances section
    /// (i.e., flagged players banner is not showing, so balances is the first activity item)
    private var balancesShouldShowActivityHeader: Bool {
        flaggedPlayers.isEmpty
    }

    @ViewBuilder
    private var balancesSection: some View {
        // Show section only if there are any players with non-zero balances
        if !playersOweYou.isEmpty || !youOwePlayers.isEmpty {
            // MARK: - Players Owe You
            if !playersOweYou.isEmpty {
                Section {
                    ForEach(playersOweYou) { item in
                        NavigationLink(value: item.player) {
                            PlayerBalanceRow(
                                name: item.player.name,
                                balance: item.balance,
                                daysSinceLastActivity: item.daysSinceLastActivity,
                                isOwedToYou: true
                            )
                        }
                    }
                } header: {
                    if balancesShouldShowActivityHeader {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Activity")
                                .foregroundStyle(Theme.textMuted)
                            HStack {
                                Text("Members Owe You")
                                Spacer()
                                Text(formatCurrency(totalPlayersOwe))
                                    .font(Theme.font(size: 12, weight: .bold))
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                    } else {
                        HStack {
                            Text("Members Owe You")
                            Spacer()
                            Text(formatCurrency(totalPlayersOwe))
                                .font(Theme.font(size: 12, weight: .bold))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }
                .listRowBackground(Theme.cardBackground)
            }

            // MARK: - You Owe Players
            if !youOwePlayers.isEmpty {
                Section {
                    ForEach(youOwePlayers) { item in
                        NavigationLink(value: item.player) {
                            PlayerBalanceRow(
                                name: item.player.name,
                                balance: item.balance,
                                daysSinceLastActivity: item.daysSinceLastActivity,
                                isOwedToYou: false
                            )
                        }
                    }
                } header: {
                    if playersOweYou.isEmpty && balancesShouldShowActivityHeader {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Activity")
                                .foregroundStyle(Theme.textMuted)
                            HStack {
                                Text("You Owe Members")
                                Spacer()
                                Text(formatCurrency(totalYouOwe))
                                    .font(Theme.font(size: 12, weight: .bold))
                                    .foregroundStyle(Theme.danger)
                            }
                        }
                    } else {
                        HStack {
                            Text("You Owe Members")
                            Spacer()
                            Text(formatCurrency(totalYouOwe))
                                .font(Theme.font(size: 12, weight: .bold))
                                .foregroundStyle(Theme.danger)
                        }
                    }
                }
                .listRowBackground(Theme.cardBackground)
            }
        }
    }

    private func formatCurrency(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: amount as NSDecimalNumber) ?? "$\(amount)"
    }
}

// MARK: - Exposure Card

struct ExposureCard: View {
    let totalExposure: Decimal

    private var formattedExposure: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: totalExposure as NSDecimalNumber) ?? "$\(totalExposure)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.accentSecondary)
                Text("Total Open Activity")
                    .font(Theme.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }

            Text(formattedExposure)
                .font(Theme.font(size: 36, weight: .black))
                .foregroundStyle(
                    totalExposure > 0
                        ? LinearGradient(
                            colors: [Theme.danger, Theme.accentTertiary],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        : LinearGradient(
                            colors: [Theme.textPrimary, Theme.textSecondary],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                )
                .shadow(color: totalExposure > 0 ? Theme.danger.opacity(0.3) : .clear, radius: 8, x: 0, y: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
    }
}

// MARK: - Pending Bets Card

struct PendingBetsCard: View {
    let count: Int
    @State private var isPulsing = false

    var body: some View {
        HStack {
            ZStack {
                if count > 0 {
                    Circle()
                        .fill(Theme.warning.opacity(0.3))
                        .frame(width: 44, height: 44)
                        .scaleEffect(isPulsing ? 1.2 : 1.0)
                        .opacity(isPulsing ? 0 : 0.8)
                }
                Image(systemName: "clock.badge.exclamationmark")
                    .font(Theme.title2)
                    .foregroundStyle(
                        count > 0
                            ? LinearGradient(
                                colors: [Theme.warning, Theme.gold],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(colors: [Theme.textSecondary], startPoint: .top, endPoint: .bottom)
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Pending Picks")
                    .font(Theme.subheadline)
                    .foregroundStyle(Theme.textSecondary)

                Text("\(count)")
                    .font(Theme.font(size: 24, weight: .black))
                    .foregroundStyle(count > 0 ? Theme.warning : Theme.textPrimary)
            }

            Spacer()

            if count > 0 {
                Text("Action Required")
                    .font(Theme.font(size: 11, weight: .bold))
                    .foregroundStyle(Theme.background)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Theme.warning, Theme.gold],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                    .shadow(color: Theme.warning.opacity(0.4), radius: 6, x: 0, y: 2)
            }
        }
        .padding(.vertical, 8)
        .onAppear {
            if count > 0 {
                withAnimation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                    isPulsing = true
                }
            }
        }
    }
}

// MARK: - Pending Bet Row

struct PendingBetRow: View {
    let bet: Bet
    let eventName: String
    let onAccept: () -> Void
    let onDecline: () -> Void

    private var formattedOdds: String {
        if bet.odds > 0 {
            return "+\(bet.odds)"
        } else {
            return "\(bet.odds)"
        }
    }

    private var formattedStake: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: bet.stake as NSDecimalNumber) ?? "$\(bet.stake)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top row: Player name and event
            HStack {
                Text(bet.player?.name ?? "Unknown Member")
                    .font(Theme.headline)

                Spacer()

                Text(eventName)
                    .font(Theme.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }

            // Middle row: Side, odds, stake
            HStack {
                Text(bet.side)
                    .font(Theme.subheadline)
                    .foregroundStyle(Theme.textPrimary)

                Text(formattedOdds)
                    .font(Theme.subheadline)
                    .foregroundStyle(Theme.textSecondary)

                Spacer()

                Text(formattedStake)
                    .font(Theme.font(size: 15, weight: .bold))
            }

            // Bottom row: Action buttons with gamelike styling
            HStack(spacing: 12) {
                Button {
                    onAccept()
                } label: {
                    Label("Accept", systemImage: "checkmark.circle.fill")
                        .font(Theme.font(size: 14, weight: .bold))
                        .foregroundStyle(Theme.background)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(
                                colors: [Theme.accent, Theme.accent.opacity(0.8)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
                        .shadow(color: Theme.accent.opacity(0.4), radius: 6, x: 0, y: 2)
                }
                .buttonStyle(.plain)

                Button {
                    onDecline()
                } label: {
                    Label("Decline", systemImage: "xmark.circle.fill")
                        .font(Theme.font(size: 14, weight: .bold))
                        .foregroundStyle(Theme.background)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(
                                colors: [Theme.danger, Theme.accentTertiary.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
                        .shadow(color: Theme.danger.opacity(0.4), radius: 6, x: 0, y: 2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Risk Event Row

struct RiskEventRow: View {
    let item: EventRiskItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName)
                    .font(Theme.font(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                if let startTime = item.formattedStartTime {
                    Text(startTime)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            Spacer()

            Text(item.formattedExposure)
                .font(Theme.font(size: 14, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Theme.danger, Theme.accentTertiary],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Theme.danger.opacity(0.15))
                )
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Player Balance Row

struct PlayerBalanceRow: View {
    let name: String
    let balance: Decimal
    let daysSinceLastActivity: Int?
    let isOwedToYou: Bool

    private var formattedBalance: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        let amount = abs(balance)
        return formatter.string(from: amount as NSDecimalNumber) ?? "$\(amount)"
    }

    private var daysText: String? {
        guard let days = daysSinceLastActivity else { return nil }
        switch days {
        case 0:
            return "Today"
        case 1:
            return "1 day ago"
        default:
            return "\(days) days ago"
        }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(Theme.headline)
                    .foregroundStyle(Theme.textPrimary)

                if let days = daysText {
                    Text("Last activity: \(days)")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textMuted)
                }
            }

            Spacer()

            Text(formattedBalance)
                .font(Theme.font(size: 15, weight: .bold))
                .foregroundStyle(isOwedToYou ? Theme.accent : Theme.danger)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Flagged Players View

struct FlaggedPlayersView: View {
    @Environment(\.dismiss) private var dismiss
    let flaggedPlayers: [FlaggedPlayer]

    var body: some View {
        NavigationStack {
            List {
                if flaggedPlayers.isEmpty {
                    ContentUnavailableView(
                        "No Flagged Members",
                        systemImage: "checkmark.circle",
                        description: Text("All members are within acceptable thresholds.")
                    )
                } else {
                    ForEach(flaggedPlayers) { flagged in
                        NavigationLink(value: flagged.player) {
                            FlaggedPlayerRow(flaggedPlayer: flagged)
                        }
                        .listRowBackground(Theme.cardBackground)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Members Need Attention")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .navigationDestination(for: Player.self) { player in
                PlayerDetailView(player: player)
            }
        }
    }
}

// MARK: - Flagged Player Row

struct FlaggedPlayerRow: View {
    let flaggedPlayer: FlaggedPlayer

    private var formattedBalance: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: flaggedPlayer.balance as NSDecimalNumber) ?? "$\(flaggedPlayer.balance)"
    }

    private var daysText: String? {
        guard let days = flaggedPlayer.daysSinceLastActivity else { return nil }
        switch days {
        case 0:
            return "Today"
        case 1:
            return "1 day ago"
        default:
            return "\(days) days ago"
        }
    }

    private var reasonColor: Color {
        switch flaggedPlayer.reason {
        case .highBalance:
            return Theme.gold
        case .aging:
            return Theme.warning
        case .both:
            return Theme.danger
        }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(flaggedPlayer.player.name)
                        .font(Theme.headline)
                        .foregroundStyle(Theme.textPrimary)

                    Text(flaggedPlayer.reason.rawValue)
                        .font(Theme.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.background)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(reasonColor)
                        .clipShape(Capsule())
                }

                HStack(spacing: 12) {
                    Text("Owes: \(formattedBalance)")
                        .font(Theme.subheadline)
                        .foregroundStyle(Theme.accent)

                    if let days = daysText {
                        Text("Last activity: \(days)")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textMuted)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(Theme.caption)
                .foregroundStyle(Theme.textMuted)
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    DashboardView()
        .modelContainer(for: [Bet.self, Event.self, Player.self, LedgerEntry.self], inMemory: true)
        .environmentObject(SyncService())
}
