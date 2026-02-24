import SwiftUI
import SwiftData
import Charts

struct AnalyticsDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncService.self) private var syncService
    @Query private var bets: [Bet]
    @Query private var players: [Player]
    @Query private var ledgerEntries: [LedgerEntry]
    @Query private var bookies: [Bookie]

    @State private var lastUpdated = Date()
    @State private var searchText = ""
    @State private var activeFilter = "All"
    @State private var scrollToPlayers = false
    @State private var selectedRange: String = "ALL"
    @State private var showSkeleton = true

    private static let timeRanges = ["1W", "1M", "3M", "1Y", "ALL"]

    private var selectedDays: Int {
        switch selectedRange {
        case "1W": return 7
        case "1M": return 30
        case "3M": return 90
        case "1Y": return 365
        default: return 0
        }
    }

    private var bookieTier: BookieTier {
        bookies.first?.tier ?? .default
    }

    private var periodPL: Decimal {
        if selectedRange == "ALL" { return lifetimePL }
        let cutoff = Calendar.current.date(byAdding: .day, value: -selectedDays, to: Date())!
        let rangeBets = bets.filter { $0.createdAt >= cutoff }
        return PlayerAttentionService.totalBookiePL(bets: rangeBets)
    }

    private var periodLabel: String {
        switch selectedRange {
        case "1W": return "past 7 days"
        case "1M": return "past 30 days"
        case "3M": return "past 90 days"
        case "1Y": return "past year"
        default: return "all time"
        }
    }

    private static let filterOptions = ["All", "Attention needed", "Overdue", "High exposure", "Big winners", "Big losers"]

    private var lifetimePL: Decimal {
        PlayerAttentionService.totalBookiePL(bets: bets)
    }

    private var summaries: [PlayerAnalyticsSummary] {
        let activePlayers = players.filter { $0.status == .active }
        return PlayerAttentionService.generateSummaries(
            players: activePlayers,
            bets: bets,
            ledgerEntries: ledgerEntries
        )
    }

    private var filteredSummaries: [PlayerAnalyticsSummary] {
        var result = summaries

        // Apply search
        if !searchText.isEmpty {
            result = result.filter { $0.player.name.localizedCaseInsensitiveContains(searchText) }
        }

        // Apply filter
        switch activeFilter {
        case "Attention needed":
            result = result.filter { $0.pas.score >= 34 }
        case "Overdue":
            result = result.filter { $0.isOverdue }
        case "High exposure":
            result = result.filter { $0.exposure.grossExposure > 0 }
        case "Big winners":
            result = result.filter { $0.sevenDayPL < 0 }  // Bookie P/L negative = player winning
        case "Big losers":
            result = result.filter { $0.sevenDayPL > 0 }  // Bookie P/L positive = player losing
        default:
            break
        }

        // Sort: open activity (highest first), then 7d performance (highest absolute value first)
        result.sort { a, b in
            let aExposure = a.exposure.grossExposure
            let bExposure = b.exposure.grossExposure
            // Players with open activity come first
            if (aExposure > 0) != (bExposure > 0) {
                return aExposure > 0
            }
            // Among players with open activity, sort by exposure descending
            if aExposure > 0 && bExposure > 0 {
                return aExposure > bExposure
            }
            // Among players without open activity, sort by 7d performance absolute value descending
            return abs(a.sevenDayPL) > abs(b.sevenDayPL)
        }

        return result
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
                SyncStatusIndicator(syncService: syncService)
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
                    if bookieTier == .chart {
                        earningsHeader
                            .padding(.horizontal, 16)

                        EarningsChart(
                            bets: bets,
                            days: selectedDays,
                            lineColor: lifetimePL >= 0 ? Theme.accent : Theme.danger
                        )
                            .padding(.horizontal, 16)
                            .animation(.easeInOut(duration: 0.3), value: selectedRange)

                        timeRangeTabs
                            .padding(.horizontal, 16)
                    } else {
                        totalPNLCard
                            .padding(.horizontal, 16)
                    }

                    if players.filter({ $0.status == .active }).isEmpty {
                        emptyState
                    } else {
                        summaryCardsGrid
                            .padding(.horizontal, 16)

                        SportPerformanceSection(bets: bets)
                            .padding(.horizontal, 16)

                        RecentActivitySection(bets: bets, ledgerEntries: ledgerEntries)
                            .padding(.horizontal, 16)

                        Text("Last updated \(lastUpdated.formatted(date: .omitted, time: .shortened))")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textMuted)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.horizontal, 16)

                        playerListSection
                            .padding(.horizontal, 16)
                            .id("playerList")
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
        VStack(alignment: .leading, spacing: 4) {
            Text(formatSignedCurrency(lifetimePL))
                .font(Theme.font(size: 34, weight: .bold))
                .foregroundStyle(lifetimePL > 0 ? Theme.accent : lifetimePL < 0 ? Theme.danger : Theme.textPrimary)

            periodChangeLabel
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var periodChangeLabel: some View {
        Group {
            if periodPL != 0 {
                Text("\(periodPL > 0 ? "▲" : "▼") \(formatSignedCurrency(periodPL)) \(periodLabel)")
                    .font(Theme.caption)
                    .foregroundStyle(periodPL > 0 ? Theme.accent : Theme.danger)
            } else {
                Text("\(formatSignedCurrency(periodPL)) \(periodLabel)")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func formatSignedCurrency(_ value: Decimal) -> String {
        let formatted = formatCurrency(value < 0 ? -value : value)
        if value > 0 { return "+\(formatted)" }
        if value < 0 { return "-\(formatted)" }
        return formatted
    }

    // MARK: - Total PNL Card (Default Tier)

    private var totalPNLCard: some View {
        SummaryCard(
            label: "TOTAL PNL",
            value: formatSignedCurrency(lifetimePL),
            valueColor: lifetimePL > 0 ? Theme.accent : lifetimePL < 0 ? Theme.danger : Theme.textPrimary
        )
    }

    // MARK: - Time Range Tabs

    private var timeRangeTabs: some View {
        HStack(spacing: 0) {
            ForEach(Self.timeRanges, id: \.self) { range in
                Button {
                    selectedRange = range
                } label: {
                    Text(range)
                        .font(Theme.bodyFont(size: 13, weight: selectedRange == range ? .bold : .medium))
                        .foregroundStyle(selectedRange == range ? Theme.accent : Theme.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .overlay(alignment: .bottom) {
                            if selectedRange == range {
                                Rectangle()
                                    .fill(Theme.accent)
                                    .frame(height: 2)
                            }
                        }
                }
            }
        }
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
                    value: formatCurrency(totalExposure),
                    valueColor: totalExposure > 0 ? Theme.danger : Theme.textPrimary
                )
            }
            .buttonStyle(.plain)

            // Card 2 — Pending Bets
            SummaryCard(
                label: "Pending Picks",
                value: "\(totalPendingBets)",
                subtitle: formatCurrency(totalPendingStake) + " at stake",
                valueColor: totalPendingBets > 0 ? Theme.warning : Theme.textPrimary
            )

            // Card 3 — Top Risk Player → navigate to that player
            topRiskCard

            // Card 4 — Outstanding Balances → filter to Overdue
            Button { activeFilter = "Overdue"; scrollToPlayers = true } label: {
                SummaryCard(
                    label: "Outstanding",
                    value: overduePlayers.isEmpty ? "All clear" : formatCurrency(totalOverdueAmount),
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
                        value: top.player.name,
                        subtitle: formatCurrency(top.exposure.grossExposure) + " exposure",
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

            // Search bar
            searchBar

            // Filter chips
            filterChips

            // Result count
            if activeFilter != "All" || !searchText.isEmpty {
                Text("\(filteredSummaries.count) of \(summaries.count) members")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.leading, 4)
            }

            // Player rows
            if filteredSummaries.isEmpty {
                Text("No members match filters")
                    .font(Theme.bodyFont(size: 15))
                    .foregroundStyle(Theme.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ForEach(filteredSummaries, id: \.player.id) { summary in
                    NavigationLink(value: summary) {
                        PlayerAnalyticsRow(summary: summary, formatCurrency: formatCurrency)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.textMuted)
                .font(.system(size: 14))

            TextField("Search members", text: $searchText)
                .font(Theme.bodyFont(size: 15))
                .foregroundStyle(Theme.textPrimary)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.textMuted)
                        .font(.system(size: 14))
                }
            }
        }
        .padding(10)
        .background(Theme.elevatedBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
    }

    // MARK: - Filter Chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Self.filterOptions, id: \.self) { filter in
                    Button {
                        activeFilter = filter
                    } label: {
                        Text(filter)
                            .font(Theme.bodyFont(size: 13, weight: .medium))
                            .foregroundStyle(activeFilter == filter ? .black : Theme.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(activeFilter == filter ? Theme.accent : Theme.elevatedBackground)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }
}

// MARK: - Earnings Chart

/// A normalized chart point with a fixed index for smooth animation between time ranges
private struct NormalizedChartPoint: Identifiable {
    let id: Int       // 0..<sampleCount — fixed index for animation interpolation
    let value: Double // cumulative P/L value
}

private struct EarningsChart: View {
    let bets: [Bet]
    var days: Int = 0
    let lineColor: Color

    /// Fixed number of data points so Swift Charts can animate between time ranges
    private static let sampleCount = 30

    private var rawDataPoints: [DailyPLPoint] {
        PlayerAttentionService.dailyCumulativePL(bets: bets, days: days)
    }

    /// Resample raw data to a fixed number of points using linear interpolation
    private var normalizedPoints: [NormalizedChartPoint] {
        let raw = rawDataPoints
        guard raw.count >= 2 else {
            if let single = raw.first {
                let val = NSDecimalNumber(decimal: single.cumulativePL).doubleValue
                return (0..<Self.sampleCount).map { NormalizedChartPoint(id: $0, value: val) }
            }
            return []
        }

        let values = raw.map { NSDecimalNumber(decimal: $0.cumulativePL).doubleValue }
        let count = Self.sampleCount
        var result: [NormalizedChartPoint] = []

        for i in 0..<count {
            let t = Double(i) / Double(count - 1) // 0.0 ... 1.0
            let srcIndex = t * Double(values.count - 1)
            let lo = Int(srcIndex)
            let hi = min(lo + 1, values.count - 1)
            let frac = srcIndex - Double(lo)
            let interpolated = values[lo] + frac * (values[hi] - values[lo])
            result.append(NormalizedChartPoint(id: i, value: interpolated))
        }
        return result
    }

    var body: some View {
        if rawDataPoints.isEmpty {
            Text("No pick history yet")
                .font(Theme.bodyFont(size: 14))
                .foregroundStyle(Theme.textMuted)
                .frame(maxWidth: .infinity)
                .frame(height: 160)
        } else {
            Chart {
                ForEach(normalizedPoints) { point in
                    LineMark(
                        x: .value("Index", point.id),
                        y: .value("Performance", point.value)
                    )
                    .foregroundStyle(lineColor)
                    .interpolationMethod(.catmullRom)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 160)
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

                    Text(formatCurrency(stat.totalStaked) + " staked")
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
        let formatted = formatCurrency(value < 0 ? -value : value)
        if value > 0 { return "+\(formatted)" }
        if value < 0 { return "-\(formatted)" }
        return formatted
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
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
            let amount = formatSignedCurrency(entry.amount)
            return "Reconciliation for \(playerName) — \(amount)"
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func formatSignedCurrency(_ value: Decimal) -> String {
        let formatted = formatCurrency(value < 0 ? -value : value)
        if value > 0 { return "+\(formatted)" }
        if value < 0 { return "-\(formatted)" }
        return formatted
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }
}

// MARK: - Player Analytics Row

private struct PlayerAnalyticsRow: View {
    let summary: PlayerAnalyticsSummary
    let formatCurrency: (Decimal) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Top: name + PAS badge
            HStack {
                Text(summary.player.name)
                    .font(Theme.font(size: 17, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)

                Spacer()

                Text(summary.pas.label)
                    .font(Theme.bodyFont(size: 11, weight: .semibold))
                    .foregroundStyle(pasLabelColor == Theme.textMuted ? Theme.textPrimary : .black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(pasLabelColor)
                    .clipShape(Capsule())
            }

            // Primary metric
            primaryMetric

            // Secondary metrics
            HStack(spacing: 16) {
                secondaryLabel("Lifetime", value: formatSignedCurrency(summary.allTimePL))
                secondaryLabel("Avg pick", value: formatCurrency(summary.avgBetSize30d))
            }

            // Reason chips
            if !summary.pas.reasonChips.isEmpty {
                reasonChipsView
            }
        }
        .padding(14)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
    }

    // MARK: - PAS Badge Color

    private var pasLabelColor: Color {
        switch summary.pas.label {
        case "High": return Theme.danger
        case "Medium": return Theme.warning
        default: return Theme.textMuted
        }
    }

    // MARK: - Primary Metric

    private var primaryMetric: some View {
        Group {
            if summary.isOverdue {
                Text("Overdue: \(formatCurrency(summary.overdueAmount))")
                    .font(Theme.bodyFont(size: 15))
                    .foregroundStyle(Theme.danger)
            } else if summary.exposure.grossExposure > 0 {
                Text("Open activity: \(formatCurrency(summary.exposure.grossExposure))")
                    .font(Theme.bodyFont(size: 15))
                    .foregroundStyle(Theme.textPrimary)
            } else {
                Text("7d Performance: \(formatSignedCurrency(summary.sevenDayPL))")
                    .font(Theme.bodyFont(size: 15))
                    .foregroundStyle(summary.sevenDayPL > 0 ? Theme.accent : summary.sevenDayPL < 0 ? Theme.danger : Theme.textSecondary)
            }
        }
    }

    // MARK: - Secondary Label

    private func secondaryLabel(_ label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label + ":")
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: - Reason Chips

    private var reasonChipsView: some View {
        HStack(spacing: 6) {
            ForEach(Array(summary.pas.reasonChips.prefix(3)), id: \.self) { chip in
                Text(chip)
                    .font(Theme.bodyFont(size: 10, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(chipColor(for: chip).opacity(0.25))
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Chip Colors

    private func chipColor(for chip: String) -> Color {
        switch chip {
        case "Overdue": return Theme.danger
        case "On heater": return Theme.gold
        case "Cold streak": return Theme.accentTertiary
        case "High roller": return Theme.accentSecondary
        case "Multi-Pick heavy": return Theme.scheduled
        case "High volatility": return Theme.warning
        case "Large pending": return Theme.accent
        default: return Theme.textMuted
        }
    }

    // MARK: - Signed Currency

    private func formatSignedCurrency(_ value: Decimal) -> String {
        let formatted = formatCurrency(abs(value))
        if value > 0 { return "+\(formatted)" }
        if value < 0 { return "-\(formatted)" }
        return formatted
    }

    private func abs(_ value: Decimal) -> Decimal {
        value < 0 ? -value : value
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
