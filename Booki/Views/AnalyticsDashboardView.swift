import SwiftUI
import SwiftData

struct AnalyticsDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(OnboardingManager.self) private var onboardingManager: OnboardingManager?
    @EnvironmentObject private var syncService: SyncService
    @Query private var bets: [Bet]
    @Query private var players: [Player]
    @Query private var ledgerEntries: [LedgerEntry]

    @State private var showOnboardingFromCard = false
    @State private var lastUpdated = Date()
    @State private var searchText = ""
    @State private var activeFilter = "All"

    private static let filterOptions = ["All", "Attention needed", "Overdue", "High exposure", "Big winners", "Big losers"]

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
            result = result.filter { $0.sevenDayPL > 0 }
        case "Big losers":
            result = result.filter { $0.sevenDayPL < 0 }
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
        ScrollView {
            VStack(spacing: 16) {
                // Finish Setup Card
                if let manager = onboardingManager, !manager.isOnboardingComplete {
                    FinishSetupCard(
                        onboardingManager: manager,
                        onResume: { showOnboardingFromCard = true }
                    )
                    .padding(.horizontal, 16)
                }

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
                }
            }
            .padding(.vertical, 16)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Analytics")
        .onAppear { lastUpdated = Date() }
        .onChange(of: bets.count) { lastUpdated = Date() }
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

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.textMuted)

            Text("No Players Yet")
                .font(Theme.title3)
                .foregroundStyle(Theme.textPrimary)

            Text("Add players to start tracking analytics and risk.")
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
            // Card 1 — Net Exposure
            SummaryCard(
                icon: "chart.line.uptrend.xyaxis",
                label: "Net Exposure",
                value: formatCurrency(totalExposure),
                valueColor: totalExposure > 0 ? Theme.danger : Theme.textPrimary
            )

            // Card 2 — Pending Bets
            SummaryCard(
                icon: "clock.badge.exclamationmark",
                label: "Pending Bets",
                value: "\(totalPendingBets)",
                subtitle: formatCurrency(totalPendingStake) + " at stake",
                valueColor: totalPendingBets > 0 ? Theme.warning : Theme.textPrimary
            )

            // Card 3 — Top Risk Player
            topRiskCard

            // Card 4 — Outstanding Balances
            SummaryCard(
                icon: "exclamationmark.triangle.fill",
                label: "Outstanding",
                value: overduePlayers.isEmpty ? "All clear" : formatCurrency(totalOverdueAmount),
                subtitle: overduePlayers.isEmpty ? nil : "\(overduePlayers.count) player\(overduePlayers.count == 1 ? "" : "s")",
                valueColor: overduePlayers.isEmpty ? Theme.accent : Theme.danger
            )
        }
    }

    private var topRiskCard: some View {
        Group {
            if let top = topRiskSummary {
                SummaryCard(
                    icon: "person.fill.exclamationmark",
                    label: "Top Risk",
                    value: top.player.name,
                    subtitle: top.pas.reasonChips.first,
                    valueColor: top.pas.label == "High" ? Theme.danger : Theme.warning
                )
            } else {
                SummaryCard(
                    icon: "checkmark.shield.fill",
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
            Text("PLAYERS")
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
                Text("\(filteredSummaries.count) of \(summaries.count) players")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.leading, 4)
            }

            // Player rows
            if filteredSummaries.isEmpty {
                Text("No players match filters")
                    .font(Theme.bodyFont(size: 15))
                    .foregroundStyle(Theme.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ForEach(filteredSummaries, id: \.player.id) { summary in
                    PlayerAnalyticsRow(summary: summary, formatCurrency: formatCurrency)
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

            TextField("Search players", text: $searchText)
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

// MARK: - Summary Card

private struct SummaryCard: View {
    let icon: String
    let label: String
    let value: String
    var subtitle: String? = nil
    var valueColor: Color = Theme.textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textMuted)

                Text(label.uppercased())
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .tracking(0.5)
            }

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
        .frame(maxWidth: .infinity, alignment: .leading)
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
                secondaryLabel("Avg bet", value: formatCurrency(summary.avgBetSize30d))
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
                Text("Open exposure: \(formatCurrency(summary.exposure.grossExposure))")
                    .font(Theme.bodyFont(size: 15))
                    .foregroundStyle(Theme.textPrimary)
            } else {
                Text("7d P/L: \(formatSignedCurrency(summary.sevenDayPL))")
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
        case "Parlay heavy": return Theme.scheduled
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
    NavigationStack {
        AnalyticsDashboardView()
    }
    .modelContainer(for: [Bet.self, Event.self, Player.self, LedgerEntry.self], inMemory: true)
    .environmentObject(SyncService())
}
