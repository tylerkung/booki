import SwiftUI
import SwiftData

struct AnalyticsDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncService.self) private var syncService
    @Query private var bets: [Bet]
    @Query private var players: [Player]
    @Query private var ledgerEntries: [LedgerEntry]
    @Query private var bookies: [Bookie]

    @State private var lastUpdated = Date()
    @State private var scrollToPlayers = false
    @State private var showSkeleton = true
    @State private var showProUpgrade = false
    @State private var timeframe: Timeframe = .day
    @State private var summaries: [PlayerAnalyticsSummary] = []
    @State private var summariesReady = false
    @State private var showDeferredSections = false
    @State private var balanceLookup: [UUID: Decimal] = [:]
    @State private var utilizationLookup: [UUID: Double] = [:]
    @State private var recomputeTask: Task<Void, Never>?

    enum Timeframe: String, CaseIterable {
        case day = "1D"
        case week = "1W"
        case month = "1M"
        case all = "All"

        var startDate: Date? {
            switch self {
            case .day: return Calendar.current.date(byAdding: .day, value: -1, to: .now)
            case .week: return Calendar.current.date(byAdding: .day, value: -7, to: .now)
            case .month: return Calendar.current.date(byAdding: .month, value: -1, to: .now)
            case .all: return nil
            }
        }

        var label: String {
            switch self {
            case .day: return "today"
            case .week: return "this week"
            case .month: return "this month"
            case .all: return "all time"
            }
        }
    }

    private var bookieTier: BookieTier {
        bookies.first?.tier ?? .free
    }

    private var bookieIsPro: Bool {
        bookies.first?.isPro ?? false
    }

    private var lifetimePL: Decimal {
        ledgerEntries
            .filter { $0.type != .paymentLogged }
            .reduce(Decimal.zero) { $0 + $1.amount }
    }

    private var filteredPL: Decimal {
        guard let start = timeframe.startDate else { return lifetimePL }
        return ledgerEntries
            .filter { $0.type != .paymentLogged && $0.createdAt >= start }
            .reduce(Decimal.zero) { $0 + $1.amount }
    }

    // MARK: - Aggregated Metrics

    private var totalExposure: Decimal {
        summaries.reduce(.zero) { $0 + $1.exposure.grossExposure }
    }

    private var totalPendingBets: Int {
        summaries.reduce(0) { $0 + $1.exposure.pendingBetCount }
    }

    private var totalPendingStake: Decimal {
        bets.filter { $0.status == .pending || $0.status == .accepted }
            .reduce(.zero) { $0 + $1.stake }
    }

    private var topRiskSummary: PlayerAnalyticsSummary? {
        summaries.first(where: { $0.pas.score > 0 })
    }

    private var overduePlayers: [PlayerAnalyticsSummary] {
        summaries.filter(\.isOverdue)
    }

    private var totalOverdueAmount: Decimal {
        overduePlayers.reduce(.zero) { $0 + $1.overdueAmount }
    }

    var body: some View {
        NavigationStack {
            mainBody
                .skeletonObservers(
                    showSkeleton: $showSkeleton,
                    betsCount: bets.count,
                    onDataChanged: { lastUpdated = Date() }
                )
        }
    }

    private var mainBody: some View {
        Group {
            if showSkeleton {
                ScrollView {
                    skeletonContent
                }
            } else {
                dashboardContent
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .refreshable {
            await withCheckedContinuation { continuation in
                Task.detached {
                    await syncService.sync()
                    continuation.resume()
                }
            }
        }
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Image("BookiWordmark")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 20)
            }
            ToolbarItem(placement: .topBarTrailing) {
                SyncStatusIndicator(syncService: syncService, bookieEmail: bookies.first?.email ?? "")
            }
        }
        .navigationDestination(for: PlayerAnalyticsSummary.self) { summary in
            PlayerAnalyticsDetailView(
                summary: summary,
                playerBets: bets.filter { $0.player?.id == summary.player.id },
                playerLedgerEntries: ledgerEntries.filter { $0.player?.id == summary.player.id }
            )
        }
    }

    // MARK: - Dashboard Content

    private var dashboardContent: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(spacing: 16) {
                    earningsHeader
                        .padding(.horizontal, 16)

                    if players.filter({ $0.status == .active }).isEmpty {
                        emptyState
                    } else {
                        if summariesReady {
                            summaryCardsGrid
                                .padding(.horizontal, 16)

                            playerListSection
                                .padding(.horizontal, 16)
                                .id("playerList")
                        } else {
                            skeletonSummaryCardsGrid
                                .padding(.horizontal, 16)

                            skeletonMembersSection
                                .padding(.horizontal, 16)
                                .id("playerList")
                        }

                        if showDeferredSections {
                            if bookieIsPro {
                                FuturesTrackingCard(bets: bets)
                                    .padding(.horizontal, 16)
                            }

                            sportPerformanceGated
                                .padding(.horizontal, 16)

                            if bookieIsPro {
                                RecentActivitySection(bets: bets, ledgerEntries: ledgerEntries)
                                    .padding(.horizontal, 16)
                            }
                        }

                        Text("Last updated \(lastUpdated.formatted(date: .omitted, time: .shortened))")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textMuted)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 16)
            }
            .onChange(of: scrollToPlayers) {
                if scrollToPlayers {
                    withAnimation {
                        scrollProxy.scrollTo("playerList", anchor: .top)
                    }
                    scrollToPlayers = false
                }
            }
        }
        .onAppear { lastUpdated = Date() }
        .task { await recomputeSummaries() }
        .onChange(of: players.count) { scheduleRecompute() }
        .onChange(of: bets.count) { scheduleRecompute() }
        .onChange(of: ledgerEntries.count) { scheduleRecompute() }
    }

    private func recomputeSummaries() async {
        let activePlayers = players.filter { $0.status == .active }

        var newSummaries: [PlayerAnalyticsSummary] = []
        newSummaries.reserveCapacity(activePlayers.count)
        var balances: [UUID: Decimal] = [:]
        var utilizations: [UUID: Double] = [:]

        for player in activePlayers {
            if Task.isCancelled { return }

            let pas = PlayerAttentionService.calculatePAS(player: player, bets: bets, ledgerEntries: ledgerEntries)
            let exposure = PlayerAttentionService.calculateExposure(player: player, bets: bets)
            let playerLedger = ledgerEntries.filter { $0.player?.id == player.id }
            let balance = BalanceService.balanceOwed(from: playerLedger)
            let sevenDayPL = PlayerAttentionService.realizedPL(player: player, bets: bets, days: 7)
            let thirtyDayPL = PlayerAttentionService.realizedPL(player: player, bets: bets, days: 30)
            let allTimePL = PlayerAttentionService.realizedPL(player: player, bets: bets, days: 0)
            let avgBet = PlayerAttentionService.avgBetSize(player: player, bets: bets, days: 30)
            let (overdue, overdueAmt) = PlayerAttentionService.isOverdue(player: player, ledgerEntries: ledgerEntries)
            let wr = PlayerAttentionService.winRate(player: player, bets: bets)

            newSummaries.append(PlayerAnalyticsSummary(
                player: player,
                pas: pas,
                exposure: exposure,
                balanceOwed: balance,
                sevenDayPL: sevenDayPL,
                thirtyDayPL: thirtyDayPL,
                allTimePL: allTimePL,
                avgBetSize30d: avgBet,
                isOverdue: overdue,
                overdueAmount: overdueAmt,
                winRate: wr
            ))

            balances[player.id] = balance
            if player.creditLimit > 0 {
                let playerBets = bets.filter { $0.player?.id == player.id }
                let pSummary = BalanceService.playerSummary(for: player, bets: playerBets, ledgerEntries: playerLedger)
                let used = player.creditLimit - pSummary.availableCredit
                let util = (used as NSDecimalNumber).doubleValue / (player.creditLimit as NSDecimalNumber).doubleValue
                utilizations[player.id] = max(0, min(1, util)) * 100
            } else {
                utilizations[player.id] = 0
            }

            await Task.yield()
        }

        if Task.isCancelled { return }

        newSummaries.sort { $0.pas.score > $1.pas.score }

        summaries = newSummaries
        balanceLookup = balances
        utilizationLookup = utilizations
        summariesReady = true
        showDeferredSections = true
    }

    private func scheduleRecompute() {
        recomputeTask?.cancel()
        recomputeTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await recomputeSummaries()
        }
    }

    // MARK: - Sport Performance (Tier-Gated)

    private var sportPerformanceGated: some View {
        Group {
            if bookieIsPro {
                SportPerformanceSection(bets: bets)
            } else {
                ZStack {
                    sportPerformancePlaceholder
                        .blur(radius: 8)
                        .allowsHitTesting(false)

                    VStack(spacing: 8) {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Theme.accent)

                        Text("Sport Breakdown")
                            .font(Theme.font(size: 17, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)

                        Text("See which sports are winning for you")
                            .font(Theme.bodyFont(size: 13))
                            .foregroundStyle(Theme.textSecondary)

                        Button {
                            showProUpgrade = true
                        } label: {
                            Text("Unlock with Pro")
                                .font(Theme.bodyFont(size: 14, weight: .bold))
                                .foregroundStyle(Theme.accent)
                        }
                        .padding(.top, 4)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
                }
            }
        }
        .sheet(isPresented: $showProUpgrade) {
            ProUpgradeSheet(contextMessage: "Unlock analytics")
        }
    }

    private var sportPerformancePlaceholder: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PERFORMANCE BY SPORT")
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
                .tracking(1.0)
                .padding(.leading, 4)

            ForEach(["Football", "Basketball", "Baseball"], id: \.self) { sport in
                HStack(spacing: 12) {
                    Image(systemName: "sportscourt.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(sport)
                                .font(Theme.font(size: 15, weight: .bold))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text("+$0.00")
                                .font(Theme.font(size: 15, weight: .bold))
                                .foregroundStyle(Theme.accent)
                        }
                        HStack(spacing: 12) {
                            Text("0 picks")
                                .font(Theme.caption)
                                .foregroundStyle(Theme.textSecondary)
                            Spacer()
                        }
                    }
                }
                .padding(14)
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
            }
        }
    }

    // MARK: - Skeleton Content

    private var skeletonContent: some View {
        VStack(spacing: 16) {
            // PNL area
            VStack(alignment: .leading, spacing: 8) {
                SkeletonBlock(width: 180, height: 34)
                SkeletonBlock(width: 120, height: 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)

            // Summary cards 2x2
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(["NET EXPOSURE", "PENDING PICKS", "TOP RISK", "OUTSTANDING"], id: \.self) { label in
                    skeletonSummaryCard(label: label)
                }
            }
            .padding(.horizontal, 16)

            // Members section
            VStack(alignment: .leading, spacing: 12) {
                Text("MEMBERS")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .tracking(1.0)
                    .padding(.leading, 4)

                ForEach(0..<3, id: \.self) { _ in
                    skeletonPlayerRow
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 16)
    }

    private func skeletonSummaryCard(label: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
                .tracking(0.5)

            SkeletonBlock(width: 80, height: 22)

            SkeletonBlock(width: 60, height: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .cardStyle()
    }

    private var skeletonPlayerRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SkeletonBlock(width: 120, height: 18)
                Spacer()
                SkeletonBlock(width: 56, height: 22, cornerRadius: 11)
            }
            SkeletonBlock(width: 160, height: 14)
            HStack(spacing: 16) {
                SkeletonBlock(width: 90, height: 12)
                SkeletonBlock(width: 80, height: 12)
            }
        }
        .padding(14)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
    }

    // MARK: - Earnings Header

    private var earningsHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(formatSignedCurrency(filteredPL))
                .font(Theme.font(size: 34, weight: .bold))
                .foregroundStyle(filteredPL > 0 ? Theme.accent : filteredPL < 0 ? Theme.danger : Theme.textPrimary)

            Text("\(formatSignedCurrency(filteredPL)) \(timeframe.label)")
                .font(Theme.caption)
                .foregroundStyle(filteredPL != 0 ? (filteredPL > 0 ? Theme.accent : Theme.danger) : Theme.textSecondary)

            HStack(spacing: 0) {
                ForEach(Timeframe.allCases, id: \.self) { tf in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            timeframe = tf
                        }
                    } label: {
                        Text(tf.rawValue)
                            .font(Theme.bodyFont(size: 13, weight: .semibold))
                            .foregroundStyle(timeframe == tf ? Theme.textPrimary : Theme.textMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                timeframe == tf
                                    ? Theme.elevatedBackground
                                    : Color.clear
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            .padding(2)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formatSignedCurrency(_ value: Decimal) -> String {
        let formatted = Theme.formatCurrency(value < 0 ? -value : value)
        if value > 0 { return "+\(formatted)" }
        if value < 0 { return "-\(formatted)" }
        return formatted
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.textMuted)

            Text("No Members Yet")
                .font(Theme.title3)
                .foregroundStyle(Theme.textPrimary)

            Text("Add members to start tracking analytics and risk.")
                .font(Theme.bodyFont(size: 15))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Summary Cards Grid

    private var summaryCardsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ], spacing: 12) {
            // Card 1 — Net Exposure → scroll to player list
            Button { scrollToPlayers = true } label: {
                SummaryCard(
                    label: "Net Exposure",
                    value: Theme.formatCurrency(totalExposure),
                    valueColor: totalExposure > 0 ? Theme.danger : Theme.textPrimary
                )
            }
            .buttonStyle(.plain)

            // Card 2 — Pending Bets
            SummaryCard(
                label: "Pending Picks",
                value: "\(totalPendingBets)",
                subtitle: Theme.formatCurrency(totalPendingStake) + " at stake",
                valueColor: totalPendingBets > 0 ? Theme.warning : Theme.textPrimary
            )

            // Card 3 — Top Risk Player → navigate to that player
            topRiskCard

            // Card 4 — Outstanding Balances → filter to Overdue
            Button { scrollToPlayers = true } label: {
                SummaryCard(
                    label: "Outstanding",
                    value: overduePlayers.isEmpty ? "All clear" : Theme.formatCurrency(totalOverdueAmount),
                    subtitle: overduePlayers.isEmpty ? nil : "\(overduePlayers.count) member\(overduePlayers.count == 1 ? "" : "s")",
                    valueColor: overduePlayers.isEmpty ? Theme.accent : Theme.danger
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var topRiskCard: some View {
        Group {
            if let top = topRiskSummary {
                NavigationLink(value: top) {
                    SummaryCard(
                        label: "Top Risk",
                        value: top.player.bookieDisplayName,
                        subtitle: Theme.formatCurrency(top.exposure.grossExposure) + " exposure",
                        valueColor: top.pas.label == "High" ? Theme.danger : Theme.warning
                    )
                }
                .buttonStyle(.plain)
            } else {
                SummaryCard(
                    label: "Top Risk",
                    value: "All clear",
                    valueColor: Theme.accent
                )
            }
        }
    }

    // MARK: - Player List Section

    private var playerListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MEMBERS")
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
                .tracking(1.0)
                .padding(.leading, 4)

            ForEach(summaries, id: \.player.id) { summary in
                NavigationLink(value: summary) {
                    PlayerRowView(
                        player: summary.player,
                        balance: balanceForPlayer(summary.player),
                        utilization: utilizationForPlayer(summary.player)
                    )
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func balanceForPlayer(_ player: Player) -> Decimal {
        balanceLookup[player.id] ?? .zero
    }

    private func utilizationForPlayer(_ player: Player) -> Double {
        utilizationLookup[player.id] ?? 0
    }

    // MARK: - Skeleton Sub-Views (inline)

    private var skeletonSummaryCardsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ], spacing: 12) {
            ForEach(["NET EXPOSURE", "PENDING PICKS", "TOP RISK", "OUTSTANDING"], id: \.self) { label in
                skeletonSummaryCard(label: label)
            }
        }
    }

    private var skeletonMembersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MEMBERS")
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
                .tracking(1.0)
                .padding(.leading, 4)

            ForEach(0..<3, id: \.self) { _ in
                skeletonPlayerRow
            }
        }
    }

}


// MARK: - Summary Card

private struct SummaryCard: View {
    let label: String
    let value: String
    var subtitle: String? = nil
    var valueColor: Color = Theme.textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
                .tracking(0.5)

            Text(value)
                .font(Theme.font(size: 20, weight: .bold))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if let subtitle {
                Text(subtitle)
                    .font(Theme.bodyFont(size: 12))
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .cardStyle()
    }
}

// MARK: - Futures Tracking Card

private struct FuturesTrackingCard: View {
    let bets: [Bet]

    private static let openStatuses: Set<String> = [
        BetStatus.pending.rawValue,
        BetStatus.accepted.rawValue,
        BetStatus.readyToGrade.rawValue,
        BetStatus.graded.rawValue
    ]

    private var openFuturesBets: [Bet] {
        bets.filter { $0.market == MarketType.outright.rawValue && Self.openStatuses.contains($0.status.rawValue) }
    }

    private var totalStaked: Decimal {
        openFuturesBets.reduce(.zero) { $0 + $1.stake }
    }

    private struct PopularSelection: Identifiable {
        let id: String // side name
        let count: Int
    }

    private var topSelections: [PopularSelection] {
        var counts: [String: Int] = [:]
        for bet in openFuturesBets {
            counts[bet.side, default: 0] += 1
        }
        return counts
            .map { PopularSelection(id: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
            .prefix(3)
            .map { $0 }
    }

    var body: some View {
        let futures = openFuturesBets
        VStack(alignment: .leading, spacing: 12) {
            Text("FUTURES ACTIVITY")
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
                .tracking(1.0)
                .padding(.leading, 4)

            if futures.isEmpty {
                Text("No futures picks yet")
                    .font(Theme.bodyFont(size: 14))
                    .foregroundStyle(Theme.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 16) {
                        statColumn(label: "Open Picks", value: "\(futures.count)")
                        statColumn(label: "Open Activity", value: Theme.formatCurrency(totalStaked))
                    }

                    let selections = topSelections
                    if !selections.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("POPULAR SELECTIONS")
                                .font(Theme.bodyFont(size: 10, weight: .medium))
                                .foregroundStyle(Theme.textMuted)
                                .tracking(0.5)

                            ForEach(selections) { selection in
                                HStack {
                                    Text(selection.id)
                                        .font(Theme.bodyFont(size: 13))
                                        .foregroundStyle(Theme.textPrimary)
                                        .lineLimit(1)

                                    Spacer()

                                    Text("\(selection.count)")
                                        .font(Theme.bodyFont(size: 13, weight: .bold))
                                        .foregroundStyle(.black)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(Theme.accent)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }
                .padding(14)
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
            }
        }
    }

    private func statColumn(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(Theme.bodyFont(size: 10, weight: .medium))
                .foregroundStyle(Theme.textMuted)
                .tracking(0.5)

            Text(value)
                .font(Theme.font(size: 20, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
        }
    }

}

// MARK: - Sport Performance Section

private struct SportPerformanceSection: View {
    let bets: [Bet]

    private struct SportStat: Identifiable {
        let id: String // sport name
        let iconName: String
        let pickCount: Int
        let totalStaked: Decimal
        let netPL: Decimal
        let winRate: Double
    }

    private var sportStats: [SportStat] {
        let settledBets = bets.filter { $0.status == .settled && $0.gradeResult != nil }
        guard !settledBets.isEmpty else { return [] }

        // Group by sport derived from sportLeague
        var grouped: [String: [Bet]] = [:]
        for bet in settledBets {
            let sportName: String
            if let league = bet.sportLeague,
               let category = SportCategory.fromLeague(league) {
                sportName = category.displayName
            } else {
                sportName = bet.sportLeague ?? "Other"
            }
            grouped[sportName, default: []].append(bet)
        }

        return grouped.map { sport, sportBets in
            let staked = sportBets.reduce(Decimal.zero) { $0 + $1.stake }
            let pl = PlayerAttentionService.totalBookiePL(bets: sportBets)
            let totalSettled = sportBets.filter { $0.gradeResult != .push }.count
            // Win rate from bookie perspective: player losses are bookie wins
            let bookieWins = sportBets.filter { $0.gradeResult == .loss }.count
            let winRate = totalSettled > 0 ? Double(bookieWins) / Double(totalSettled) * 100 : 0

            return SportStat(
                id: sport,
                iconName: SportCategory.iconName(for: sport),
                pickCount: sportBets.count,
                totalStaked: staked,
                netPL: pl,
                winRate: winRate
            )
        }
        .sorted { $0.totalStaked > $1.totalStaked }
    }

    var body: some View {
        let stats = sportStats
        if !stats.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("PERFORMANCE BY SPORT")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .tracking(1.0)
                    .padding(.leading, 4)

                ForEach(stats) { stat in
                    sportRow(stat)
                }
            }
        }
    }

    private func sportRow(_ stat: SportStat) -> some View {
        HStack(spacing: 12) {
            Image(systemName: stat.iconName)
                .font(.system(size: 20))
                .foregroundStyle(Theme.accent)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(stat.id)
                        .font(Theme.font(size: 15, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)

                    Spacer()

                    Text(formatSignedCurrency(stat.netPL))
                        .font(Theme.font(size: 15, weight: .bold))
                        .foregroundStyle(stat.netPL > 0 ? Theme.accent : stat.netPL < 0 ? Theme.danger : Theme.textSecondary)
                }

                HStack(spacing: 12) {
                    Text("\(stat.pickCount) picks")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)

                    Text(Theme.formatCurrency(stat.totalStaked) + " staked")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)

                    Spacer()

                    Text(String(format: "%.0f%% win", stat.winRate))
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textMuted)
                }
            }
        }
        .padding(14)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
    }

    private func formatSignedCurrency(_ value: Decimal) -> String {
        let formatted = Theme.formatCurrency(value < 0 ? -value : value)
        if value > 0 { return "+\(formatted)" }
        if value < 0 { return "-\(formatted)" }
        return formatted
    }
}

// MARK: - Recent Activity Section

private struct RecentActivitySection: View {
    let bets: [Bet]
    let ledgerEntries: [LedgerEntry]

    private enum ActivityItem: Identifiable {
        case pickPlaced(Bet)
        case pickGraded(Bet)
        case reconciliation(LedgerEntry)

        var id: String {
            switch self {
            case .pickPlaced(let bet): return "placed-\(bet.id)"
            case .pickGraded(let bet): return "graded-\(bet.id)"
            case .reconciliation(let entry): return "recon-\(entry.id)"
            }
        }

        var date: Date {
            switch self {
            case .pickPlaced(let bet): return bet.createdAt
            case .pickGraded(let bet): return bet.createdAt
            case .reconciliation(let entry): return entry.createdAt
            }
        }

        var iconName: String {
            switch self {
            case .pickPlaced: return "ticket.fill"
            case .pickGraded: return "checkmark.circle"
            case .reconciliation: return "banknote"
            }
        }
    }

    private var activities: [ActivityItem] {
        var items: [ActivityItem] = []

        for bet in bets {
            items.append(.pickPlaced(bet))
            if bet.status == .settled, bet.gradeResult != nil {
                items.append(.pickGraded(bet))
            }
        }

        for entry in ledgerEntries {
            items.append(.reconciliation(entry))
        }

        return Array(items.sorted { $0.date > $1.date }.prefix(10))
    }

    var body: some View {
        let items = activities
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("RECENT ACTIVITY")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .tracking(1.0)
                    .padding(.leading, 4)

                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        activityRow(item)
                        if index < items.count - 1 {
                            Divider()
                                .background(Theme.elevatedBackground)
                        }
                    }
                }
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
            }
        }
    }

    private func activityRow(_ item: ActivityItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.iconName)
                .font(.system(size: 14))
                .foregroundStyle(Theme.accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(activityDescription(item))
                    .font(Theme.bodyFont(size: 13))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)

                Text(relativeTime(item.date))
                    .font(Theme.bodyFont(size: 11))
                    .foregroundStyle(Theme.textMuted)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func activityDescription(_ item: ActivityItem) -> String {
        switch item {
        case .pickPlaced(let bet):
            let playerName = bet.player?.name ?? "Unknown"
            let eventDesc = bet.eventDescription ?? "an event"
            return "\(playerName) placed a pick on \(eventDesc)"
        case .pickGraded(let bet):
            let playerName = bet.player?.name ?? "Unknown"
            let eventDesc = bet.eventDescription ?? "an event"
            let resultText: String
            switch bet.gradeResult {
            case .win: resultText = "Win"
            case .loss: resultText = "Loss"
            case .push: resultText = "Push"
            case .none: resultText = ""
            }
            return "\(playerName)'s pick on \(eventDesc) — \(resultText)"
        case .reconciliation(let entry):
            let playerName = entry.player?.name ?? "Unknown"
            let absAmount = Theme.formatCurrency(entry.amount < 0 ? -entry.amount : entry.amount)
            switch entry.type {
            case .adjustment:
                if entry.amount > 0 {
                    return "\(playerName) owes \(absAmount) more"
                } else {
                    return "\(playerName) credited \(absAmount)"
                }
            case .paymentLogged:
                return "Payment received from \(playerName) — \(absAmount)"
            case .reversal:
                return "Reversal for \(playerName) — \(absAmount)"
            case .settlement:
                if entry.amount > 0 {
                    return "\(playerName) owes \(absAmount) — pick settled"
                } else if entry.amount < 0 {
                    return "\(playerName) won \(absAmount) — pick settled"
                } else {
                    return "\(playerName)'s pick pushed"
                }
            }
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

}

// MARK: - Skeleton Observers Modifier

private struct SkeletonObserversModifier: ViewModifier {
    @Binding var showSkeleton: Bool
    let betsCount: Int
    let onDataChanged: () -> Void

    func body(content: Content) -> some View {
        content
            .task {
                // SwiftData already has cached data — skip skeleton
                if betsCount > 0 {
                    showSkeleton = false
                    return
                }
                // Max skeleton duration: 8 seconds then give up
                try? await Task.sleep(for: .seconds(8))
                if showSkeleton {
                    withAnimation(.easeOut(duration: 0.3)) {
                        showSkeleton = false
                    }
                }
            }
            .onChange(of: betsCount) {
                onDataChanged()
                guard showSkeleton, betsCount > 0 else { return }
                withAnimation(.easeOut(duration: 0.3)) {
                    showSkeleton = false
                }
            }
    }
}

extension View {
    func skeletonObservers(
        showSkeleton: Binding<Bool>,
        betsCount: Int,
        onDataChanged: @escaping () -> Void
    ) -> some View {
        modifier(SkeletonObserversModifier(
            showSkeleton: showSkeleton,
            betsCount: betsCount,
            onDataChanged: onDataChanged
        ))
    }
}

#Preview {
    AnalyticsDashboardView()
        .modelContainer(for: [Bet.self, Event.self, Player.self, LedgerEntry.self, Bookie.self], inMemory: true)
        .environment(SyncService())
}
