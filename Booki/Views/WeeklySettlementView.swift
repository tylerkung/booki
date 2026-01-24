import SwiftUI
import SwiftData

/// Filter options for the player settlement list
enum SettlementFilterOption: String, CaseIterable, Identifiable {
    case all = "All"
    case unsettled = "Unsettled"
    case settled = "Settled"

    var id: String { rawValue }
}

struct WeeklySettlementView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settlementPeriods: [SettlementPeriod]
    @Query private var players: [Player]
    @Query private var bets: [Bet]
    @Query private var ledgerEntries: [LedgerEntry]
    @Query private var playerSettlements: [PlayerSettlement]

    /// Currently selected week ending date (Sunday)
    @State private var selectedWeekEndingDate: Date = WeeklySettlementView.mostRecentSunday()

    /// Filter for player list
    @State private var selectedFilter: SettlementFilterOption = .all

    // MARK: - Computed Properties

    /// Active players for settlement
    private var activePlayers: [Player] {
        players.filter { $0.status == .active }
    }

    /// Recent 5 weeks for picker (Sundays)
    private var recentWeeks: [Date] {
        var weeks: [Date] = []
        let mostRecent = WeeklySettlementView.mostRecentSunday()
        for i in 0..<5 {
            if let weekDate = Calendar.current.date(byAdding: .weekOfYear, value: -i, to: mostRecent) {
                weeks.append(weekDate)
            }
        }
        return weeks
    }

    /// Start of the selected week (Monday)
    private var selectedWeekStartDate: Date {
        Calendar.current.date(byAdding: .day, value: -6, to: selectedWeekEndingDate) ?? selectedWeekEndingDate
    }

    /// Date range description for display
    private var dateRangeDescription: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"

        let yearFormatter = DateFormatter()
        yearFormatter.dateFormat = "MMM d, yyyy"

        let startStr = formatter.string(from: selectedWeekStartDate)
        let endStr = yearFormatter.string(from: selectedWeekEndingDate)

        return "\(startStr) - \(endStr)"
    }

    /// Player settlement reports for selected period
    private var playerReports: [PlayerSettlementReport] {
        activePlayers.map { player in
            SettlementService.calculatePlayerReport(
                player: player,
                periodStart: selectedWeekStartDate,
                periodEnd: selectedWeekEndingDate,
                bets: bets,
                ledgerEntries: ledgerEntries
            )
        }
    }

    /// Count of players marked as settled for this period
    private var settledCount: Int {
        playerSettlements.filter {
            Calendar.current.isDate($0.periodWeekEndingDate, inSameDayAs: selectedWeekEndingDate) && $0.isSettled
        }.count
    }

    /// Total owed to bookie (positive ending balances)
    private var totalOwedToBookie: Decimal {
        playerReports.filter { $0.endingBalance > 0 }
            .reduce(Decimal.zero) { $0 + $1.endingBalance }
    }

    /// Total owed to players (negative ending balances)
    private var totalOwedToPlayers: Decimal {
        abs(playerReports.filter { $0.endingBalance < 0 }
            .reduce(Decimal.zero) { $0 + $1.endingBalance })
    }

    /// Filtered and sorted player reports for display
    /// - Sorted by absolute ending balance descending (biggest amounts first)
    /// - Filtered by settlement status
    private var filteredSortedReports: [PlayerSettlementReport] {
        let sorted = playerReports.sorted { abs($0.endingBalance) > abs($1.endingBalance) }

        switch selectedFilter {
        case .all:
            return sorted
        case .unsettled:
            return sorted.filter { !isPlayerSettled($0.player) }
        case .settled:
            return sorted.filter { isPlayerSettled($0.player) }
        }
    }

    // MARK: - Static Methods

    /// Get the most recent Sunday (week ending date)
    static func mostRecentSunday() -> Date {
        let calendar = Calendar.current
        let today = Date()

        // Get the weekday (1 = Sunday, 2 = Monday, ..., 7 = Saturday)
        let weekday = calendar.component(.weekday, from: today)

        // Calculate days to add/subtract to get to Sunday
        // If today is Sunday (1), use today; otherwise go back to previous Sunday
        let daysToSubtract = weekday == 1 ? 0 : weekday - 1

        let sundayDate = calendar.date(byAdding: .day, value: -daysToSubtract, to: today)!
        // Return end of day (23:59:59) for the Sunday
        return calendar.startOfDay(for: sundayDate).addingTimeInterval(86399)
    }

    var body: some View {
        List {
            // MARK: - Week Picker Section
            Section {
                VStack(spacing: 16) {
                    // Date range header
                    Text(dateRangeDescription)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)

                    // Week picker
                    Picker("Week", selection: $selectedWeekEndingDate) {
                        ForEach(recentWeeks, id: \.self) { date in
                            Text(weekPickerLabel(for: date))
                                .tag(date)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.vertical, 8)
            }
            .listRowBackground(Theme.cardBackground)

            // MARK: - Summary Section
            Section {
                VStack(spacing: 16) {
                    // First row: Total Players and Settled Count
                    HStack(spacing: 16) {
                        SummaryStatView(
                            title: "Total Players",
                            value: "\(activePlayers.count)",
                            icon: "person.2.fill",
                            color: Theme.accent
                        )

                        SummaryStatView(
                            title: "Settled",
                            value: "\(settledCount) / \(activePlayers.count)",
                            icon: "checkmark.circle.fill",
                            color: settledCount == activePlayers.count ? Theme.accent : Theme.warning
                        )
                    }

                    // Second row: Owed to Bookie and Owed to Players
                    HStack(spacing: 16) {
                        SummaryStatView(
                            title: "Owed to You",
                            value: formatCurrency(totalOwedToBookie),
                            icon: "arrow.down.circle.fill",
                            color: Theme.accent
                        )

                        SummaryStatView(
                            title: "You Owe",
                            value: formatCurrency(totalOwedToPlayers),
                            icon: "arrow.up.circle.fill",
                            color: Theme.danger
                        )
                    }
                }
                .padding(.vertical, 8)
            } header: {
                Text("Summary")
            }
            .listRowBackground(Theme.cardBackground)

            // MARK: - Players Section
            Section {
                // Filter picker
                Picker("Filter", selection: $selectedFilter) {
                    ForEach(SettlementFilterOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Theme.cardBackground)

                // Player list
                ForEach(filteredSortedReports, id: \.player.id) { report in
                    NavigationLink {
                        PlayerSettlementDetailView(
                            player: report.player,
                            weekEndingDate: selectedWeekEndingDate
                        )
                    } label: {
                        PlayerSettlementRowView(
                            report: report,
                            isSettled: isPlayerSettled(report.player)
                        )
                    }
                    .listRowBackground(Theme.cardBackground)
                }
            } header: {
                Text("Players")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Weekly Settlement")
    }

    // MARK: - Helper Methods

    private func weekPickerLabel(for date: Date) -> String {
        let calendar = Calendar.current
        let mostRecent = WeeklySettlementView.mostRecentSunday()

        if calendar.isDate(date, inSameDayAs: mostRecent) {
            return "This Week"
        }

        let weeksAgo = calendar.dateComponents([.weekOfYear], from: date, to: mostRecent).weekOfYear ?? 0

        if weeksAgo == 1 {
            return "Last Week"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private func formatCurrency(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: amount as NSDecimalNumber) ?? "$\(amount)"
    }

    /// Check if a player is marked as settled for the selected period
    private func isPlayerSettled(_ player: Player) -> Bool {
        playerSettlements.contains { settlement in
            settlement.player?.id == player.id &&
            Calendar.current.isDate(settlement.periodWeekEndingDate, inSameDayAs: selectedWeekEndingDate) &&
            settlement.isSettled
        }
    }
}

// MARK: - Summary Stat View

struct SummaryStatView: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)

                Spacer()
            }

            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)

            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.elevatedBackground)
        .cornerRadius(Theme.cornerRadiusSmall)
    }
}

// MARK: - Player Settlement Row View

struct PlayerSettlementRowView: View {
    let report: PlayerSettlementReport
    let isSettled: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Player name and settled indicator
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(report.player.name)
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)

                    if isSettled {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(Theme.accent)
                    }
                }

                // Bet activity summary
                Text("\(report.betsSettledCount) bets")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            // Ending balance with color coding
            // Positive = player owes bookie (red/danger)
            // Negative = bookie owes player (green/accent)
            VStack(alignment: .trailing, spacing: 4) {
                Text(formatCurrency(report.endingBalance))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(balanceColor)

                Text(balanceDescription)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var balanceColor: Color {
        if report.endingBalance > 0 {
            return Theme.danger // Player owes bookie
        } else if report.endingBalance < 0 {
            return Theme.accent // Bookie owes player
        } else {
            return Theme.textSecondary // Even
        }
    }

    private var balanceDescription: String {
        if report.endingBalance > 0 {
            return "owes you"
        } else if report.endingBalance < 0 {
            return "you owe"
        } else {
            return "even"
        }
    }

    private func formatCurrency(_ amount: Decimal) -> String {
        let displayAmount = abs(amount)
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: displayAmount as NSDecimalNumber) ?? "$\(displayAmount)"
    }
}

// MARK: - Player Settlement Detail View (Placeholder)
// Full implementation in US-006

struct PlayerSettlementDetailView: View {
    let player: Player
    let weekEndingDate: Date

    var body: some View {
        Text("Settlement details for \(player.name)")
            .navigationTitle(player.name)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        WeeklySettlementView()
    }
    .modelContainer(for: [
        SettlementPeriod.self,
        Player.self,
        Bet.self,
        LedgerEntry.self,
        PlayerSettlement.self
    ], inMemory: true)
}
