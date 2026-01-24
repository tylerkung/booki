import SwiftUI
import SwiftData

struct WeeklySettlementView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settlementPeriods: [SettlementPeriod]
    @Query private var players: [Player]
    @Query private var bets: [Bet]
    @Query private var ledgerEntries: [LedgerEntry]
    @Query private var playerSettlements: [PlayerSettlement]

    /// Currently selected week ending date (Sunday)
    @State private var selectedWeekEndingDate: Date = WeeklySettlementView.mostRecentSunday()

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
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Weekly Settlement")
    }

    // MARK: - Helper Methods

    private func weekPickerLabel(for date: Date) -> String {
        let calendar = Calendar.current
        let today = Date()
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
