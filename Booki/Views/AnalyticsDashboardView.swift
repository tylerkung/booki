import SwiftUI
import SwiftData
import Charts

struct AnalyticsDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var syncService: SyncService
    @Query private var bets: [Bet]
    @Query private var players: [Player]
    @Query private var ledgerEntries: [LedgerEntry]

    @State private var lastUpdated = Date()
    @State private var searchText = ""
    @State private var activeFilter = "All"
    @State private var scrollToPlayers = false
    @State private var selectedRange: String = "ALL"

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

    private var periodPL: Decimal {
        if useMockData {
            // For mock data, scale lifetime P/L based on selected range
            if selectedRange == "ALL" { return lifetimePL }
            let fraction: Decimal = selectedDays == 7 ? 0.08 : selectedDays == 30 ? 0.22 : selectedDays == 90 ? 0.45 : 0.78
            return lifetimePL * fraction
        }
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

    private var useMockData: Bool { bets.filter({ $0.gradeResult != nil }).isEmpty }

    private var lifetimePL: Decimal {
        useMockData ? Self.mockLifetimePL : PlayerAttentionService.totalBookiePL(bets: bets)
    }

    // MARK: - Mock Data for Visualization

    private static let mockLifetimePL: Decimal = 2847.50

    static func generateMockDataPoints(days: Int) -> [DailyPLPoint] {
        let calendar = Calendar.current
        let totalDays = days == 0 ? 180 : days
        let now = Date()
        var points: [DailyPLPoint] = []
        var cumulative: Double = 0

        for i in (0..<totalDays).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -i, to: now) else { continue }
            // Simulate realistic P/L: slight upward trend with volatility
            let daily = Double.random(in: -80...95)
            cumulative += daily
            points.append(DailyPLPoint(date: date, cumulativePL: Decimal(cumulative)))
        }
        // Normalize so final value matches mockLifetimePL
        if let last = points.last, last.cumulativePL != 0 {
            let scale = mockLifetimePL / last.cumulativePL
            points = points.map { DailyPLPoint(date: $0.date, cumulativePL: $0.cumulativePL * scale) }
        }
        return points
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
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(spacing: 16) {
                        // Earnings Hero Number
                        earningsHeader
                            .padding(.horizontal, 16)

                        // Earnings Chart
                        EarningsChart(
                            bets: bets,
                            days: selectedDays,
                            lineColor: lifetimePL >= 0 ? Theme.accent : Theme.danger,
                            mockDataPoints: useMockData ? Self.generateMockDataPoints(days: selectedDays) : nil
                        )
                            .padding(.horizontal, 16)
                            .animation(.easeInOut(duration: 0.3), value: selectedRange)

                        // Time Range Tabs
                        timeRangeTabs
                            .padding(.horizontal, 16)

                        if players.filter({ $0.status == .active }).isEmpty {
                            emptyState
                        } else {
                            // Summary Cards 2x2
                            summaryCardsGrid
                                .padding(.horizontal, 16)

                            // Last updated
                            Text("Last updated \(lastUpdated.formatted(date: .omitted, time: .shortened))")
                                .font(Theme.caption)
                                .foregroundStyle(Theme.textMuted)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .padding(.horizontal, 16)

                            // MARK: - Player List
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
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: PlayerAnalyticsSummary.self) { summary in
                PlayerAnalyticsDetailView(
                    summary: summary,
                    playerBets: bets.filter { $0.player?.id == summary.player.id },
                    playerLedgerEntries: ledgerEntries.filter { $0.player?.id == summary.player.id }
                )
            }
            .onAppear { lastUpdated = Date() }
            .onChange(of: bets.count) { lastUpdated = Date() }
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
        }
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
    var mockDataPoints: [DailyPLPoint]? = nil

    /// Fixed number of data points so Swift Charts can animate between time ranges
    private static let sampleCount = 30

    private var rawDataPoints: [DailyPLPoint] {
        if let mock = mockDataPoints, !mock.isEmpty {
            return mock
        }
        return PlayerAttentionService.dailyCumulativePL(bets: bets, days: days)
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

#Preview {
    AnalyticsDashboardView()
        .modelContainer(for: [Bet.self, Event.self, Player.self, LedgerEntry.self], inMemory: true)
        .environmentObject(SyncService())
}
