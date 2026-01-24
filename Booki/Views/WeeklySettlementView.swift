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

// MARK: - Player Settlement Detail View

struct PlayerSettlementDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var bets: [Bet]
    @Query private var ledgerEntries: [LedgerEntry]
    @Query private var playerSettlements: [PlayerSettlement]

    let player: Player
    let weekEndingDate: Date

    /// Notes text for marking as settled
    @State private var settlementNotes: String = ""

    // MARK: - Computed Properties

    /// Start of the selected week (Monday)
    private var weekStartDate: Date {
        Calendar.current.date(byAdding: .day, value: -6, to: weekEndingDate) ?? weekEndingDate
    }

    /// Settlement report for this player and period
    private var report: PlayerSettlementReport {
        SettlementService.calculatePlayerReport(
            player: player,
            periodStart: weekStartDate,
            periodEnd: weekEndingDate,
            bets: bets,
            ledgerEntries: ledgerEntries
        )
    }

    /// Existing settlement record for this player/period (if any)
    private var existingSettlement: PlayerSettlement? {
        playerSettlements.first { settlement in
            settlement.player?.id == player.id &&
            Calendar.current.isDate(settlement.periodWeekEndingDate, inSameDayAs: weekEndingDate)
        }
    }

    /// Whether the player is marked as settled
    private var isSettled: Bool {
        existingSettlement?.isSettled ?? false
    }

    /// Date range description for display
    private var dateRangeDescription: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"

        let yearFormatter = DateFormatter()
        yearFormatter.dateFormat = "MMM d, yyyy"

        let startStr = formatter.string(from: weekStartDate)
        let endStr = yearFormatter.string(from: weekEndingDate)

        return "\(startStr) - \(endStr)"
    }

    var body: some View {
        List {
            // MARK: - Balance Summary Section
            Section {
                BalanceSummaryCard(report: report)
            } header: {
                Text("Balance Summary")
            }
            .listRowBackground(Theme.cardBackground)

            // MARK: - Betting Activity Section
            Section {
                BettingActivityCard(report: report)
            } header: {
                Text("Betting Activity")
            }
            .listRowBackground(Theme.cardBackground)

            // MARK: - Payments Section
            if report.paymentsReceived != 0 {
                Section {
                    HStack {
                        Text("Payments Received")
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text(formatCurrency(report.paymentsReceived))
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.accent)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Payments")
                }
                .listRowBackground(Theme.cardBackground)
            }

            // MARK: - Adjustments Section
            if report.adjustments != 0 {
                Section {
                    HStack {
                        Text("Adjustments")
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text(formatCurrencySigned(report.adjustments))
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(report.adjustments >= 0 ? Theme.danger : Theme.accent)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Adjustments")
                }
                .listRowBackground(Theme.cardBackground)
            }

            // MARK: - Settlement Status Section
            Section {
                if isSettled, let settlement = existingSettlement {
                    // Already settled - show status
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(Theme.accent)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Settled")
                                    .font(.headline)
                                    .foregroundStyle(Theme.textPrimary)

                                if let settledAt = settlement.settledAt {
                                    Text(formatSettledDate(settledAt))
                                        .font(.caption)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }

                            Spacer()
                        }

                        if let notes = settlement.notes, !notes.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Notes")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)

                                Text(notes)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.textPrimary)
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(.vertical, 8)
                } else {
                    // Not settled - show mark as settled UI
                    VStack(alignment: .leading, spacing: 16) {
                        TextField("Settlement notes (optional)", text: $settlementNotes, axis: .vertical)
                            .textFieldStyle(.plain)
                            .foregroundStyle(Theme.textPrimary)
                            .padding(12)
                            .background(Theme.elevatedBackground)
                            .cornerRadius(Theme.cornerRadiusSmall)
                            .lineLimit(3...6)

                        Button {
                            markAsSettled()
                        } label: {
                            HStack {
                                Image(systemName: "checkmark.circle")
                                Text("Mark as Settled")
                            }
                            .font(.headline)
                            .foregroundStyle(Theme.background)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.accent)
                            .cornerRadius(Theme.cornerRadiusSmall)
                        }
                    }
                    .padding(.vertical, 8)
                }
            } header: {
                Text("Settlement Status")
            }
            .listRowBackground(Theme.cardBackground)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(player.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack {
                    Text(player.name)
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Text(dateRangeDescription)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    // MARK: - Actions

    private func markAsSettled() {
        if let existing = existingSettlement {
            // Update existing settlement
            existing.isSettled = true
            existing.settledAt = Date()
            existing.notes = settlementNotes.isEmpty ? nil : settlementNotes
        } else {
            // Create new settlement record
            let newSettlement = PlayerSettlement(
                isSettled: true,
                settledAt: Date(),
                notes: settlementNotes.isEmpty ? nil : settlementNotes,
                periodWeekEndingDate: weekEndingDate,
                player: player
            )
            modelContext.insert(newSettlement)
        }

        // Clear notes field
        settlementNotes = ""
    }

    // MARK: - Formatting Helpers

    private func formatCurrency(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: abs(amount) as NSDecimalNumber) ?? "$\(abs(amount))"
    }

    private func formatCurrencySigned(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        let formatted = formatter.string(from: abs(amount) as NSDecimalNumber) ?? "$\(abs(amount))"
        return amount >= 0 ? "+\(formatted)" : "-\(formatted)"
    }

    private func formatSettledDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Settled on \(formatter.string(from: date))"
    }
}

// MARK: - Balance Summary Card

struct BalanceSummaryCard: View {
    let report: PlayerSettlementReport

    var body: some View {
        VStack(spacing: 16) {
            // Starting Balance -> Net Results -> Payments -> Ending Balance flow
            BalanceLineItem(
                label: "Starting Balance",
                amount: report.startingBalance,
                isHighlighted: false
            )

            BalanceLineItem(
                label: "Net Bet Results",
                amount: report.netBetResults,
                showSign: true,
                isHighlighted: false
            )

            if report.paymentsReceived != 0 {
                BalanceLineItem(
                    label: "Payments",
                    amount: -report.paymentsReceived,
                    showSign: true,
                    isHighlighted: false
                )
            }

            if report.adjustments != 0 {
                BalanceLineItem(
                    label: "Adjustments",
                    amount: report.adjustments,
                    showSign: true,
                    isHighlighted: false
                )
            }

            Divider()
                .background(Theme.divider)

            // Ending Balance (highlighted)
            HStack {
                Text("Ending Balance")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatCurrency(report.endingBalance))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(endingBalanceColor)

                    Text(balanceDescription)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var endingBalanceColor: Color {
        if report.endingBalance > 0 {
            return Theme.danger // Player owes bookie
        } else if report.endingBalance < 0 {
            return Theme.accent // Bookie owes player
        } else {
            return Theme.textSecondary
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
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: abs(amount) as NSDecimalNumber) ?? "$\(abs(amount))"
    }
}

// MARK: - Balance Line Item

struct BalanceLineItem: View {
    let label: String
    let amount: Decimal
    var showSign: Bool = false
    var isHighlighted: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .font(isHighlighted ? .headline : .subheadline)
                .foregroundStyle(isHighlighted ? Theme.textPrimary : Theme.textSecondary)

            Spacer()

            Text(formattedAmount)
                .font(.system(size: isHighlighted ? 18 : 16, weight: isHighlighted ? .bold : .semibold, design: .rounded))
                .foregroundStyle(amountColor)
        }
    }

    private var formattedAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        let absFormatted = formatter.string(from: abs(amount) as NSDecimalNumber) ?? "$\(abs(amount))"

        if showSign && amount != 0 {
            return amount > 0 ? "+\(absFormatted)" : "-\(absFormatted)"
        }
        return absFormatted
    }

    private var amountColor: Color {
        if showSign {
            if amount > 0 {
                return Theme.danger // Adds to debt
            } else if amount < 0 {
                return Theme.accent // Reduces debt
            }
        }
        return Theme.textPrimary
    }
}

// MARK: - Betting Activity Card

struct BettingActivityCard: View {
    let report: PlayerSettlementReport

    var body: some View {
        VStack(spacing: 12) {
            // Total bets
            HStack {
                Text("Total Bets Settled")
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("\(report.betsSettledCount)")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
            }

            // Won/Lost breakdown
            HStack(spacing: 16) {
                // Won
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(report.betsWonCount)")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.accent)
                        Text("Won")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Lost
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(Theme.danger)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(report.betsLostCount)")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.danger)
                        Text("Lost")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Pushed
                HStack(spacing: 8) {
                    Image(systemName: "equal.circle.fill")
                        .foregroundStyle(Theme.textSecondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(report.betsSettledCount - report.betsWonCount - report.betsLostCount)")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                        Text("Push")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 8)
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
