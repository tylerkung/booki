import SwiftUI
import SwiftData

/// Filter options for the player settlement list
enum SettlementFilterOption: String, CaseIterable, Identifiable {
    case all = "All"
    case unsettled = "Unsettled"
    case settled = "Settled"
    case needsAttention = "Needs Attention"

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

    /// Temporary file URL for CSV export
    @State private var csvFileURL: URL?

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

    /// Check if viewing the current (most recent) week
    private var isViewingCurrentWeek: Bool {
        let mostRecent = WeeklySettlementView.mostRecentSunday()
        return Calendar.current.isDate(selectedWeekEndingDate, inSameDayAs: mostRecent)
    }

    /// Check if there is earlier period data (ledger entries or bets before the selected week start)
    private var hasEarlierPeriodData: Bool {
        let earlierDate = Calendar.current.date(byAdding: .day, value: -7, to: selectedWeekStartDate) ?? selectedWeekStartDate
        let hasEarlierLedger = ledgerEntries.contains { $0.date < earlierDate }
        let hasEarlierBets = bets.contains { $0.createdAt < earlierDate }
        return hasEarlierLedger || hasEarlierBets
    }

    /// Previous week's ending date (Sunday)
    private var previousWeekEndingDate: Date {
        Calendar.current.date(byAdding: .weekOfYear, value: -1, to: selectedWeekEndingDate) ?? selectedWeekEndingDate
    }

    /// Previous week's start date (Monday)
    private var previousWeekStartDate: Date {
        Calendar.current.date(byAdding: .day, value: -6, to: previousWeekEndingDate) ?? previousWeekEndingDate
    }

    /// Player reports for the previous period (for balance verification)
    private var previousPeriodReports: [PlayerSettlementReport] {
        activePlayers.map { player in
            SettlementService.calculatePlayerReport(
                player: player,
                periodStart: previousWeekStartDate,
                periodEnd: previousWeekEndingDate,
                bets: bets,
                ledgerEntries: ledgerEntries
            )
        }
    }

    /// Count of unsettled players from the previous period
    private var unsettledFromPriorPeriodCount: Int {
        activePlayers.filter { player in
            !playerSettlements.contains { settlement in
                settlement.player?.id == player.id &&
                Calendar.current.isDate(settlement.periodWeekEndingDate, inSameDayAs: previousWeekEndingDate) &&
                settlement.isSettled
            }
        }.count
    }

    /// Check if starting balances match previous period ending balances
    private var balanceMismatchPlayers: [String] {
        var mismatches: [String] = []
        for report in playerReports {
            let previousReport = previousPeriodReports.first { $0.player.id == report.player.id }
            if let prevReport = previousReport {
                // Check if starting balance matches previous ending balance
                if report.startingBalance != prevReport.endingBalance {
                    mismatches.append(report.player.name)
                }
            }
        }
        return mismatches
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

    /// CSV filename based on weekEndingDate
    private var csvFilename: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "settlement_\(formatter.string(from: selectedWeekEndingDate)).csv"
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
        case .needsAttention:
            return sorted.filter { hasCollectionStatus($0.player) }
        }
    }

    /// Check if a player has a collection status set (not nil and not .noStatus)
    private func hasCollectionStatus(_ player: Player) -> Bool {
        guard let status = player.collectionStatus else { return false }
        return status != .noStatus
    }

    /// Generate CSV content for the settlement report
    private func generateCSVContent() -> String {
        var csvContent = "Player Name,Starting Balance,Net Results,Payments,Adjustments,Ending Balance,Settled\n"

        for report in playerReports.sorted(by: { $0.player.name < $1.player.name }) {
            let settled = isPlayerSettled(report.player) ? "Yes" : "No"
            // Format currency values without $ symbol for CSV compatibility
            let startingBalance = formatDecimalForCSV(report.startingBalance)
            let netResults = formatDecimalForCSV(report.netBetResults)
            let payments = formatDecimalForCSV(report.paymentsReceived)
            let adjustments = formatDecimalForCSV(report.adjustments)
            let endingBalance = formatDecimalForCSV(report.endingBalance)

            // Escape player name if it contains commas
            let playerName = report.player.name.contains(",") ? "\"\(report.player.name)\"" : report.player.name

            csvContent += "\(playerName),\(startingBalance),\(netResults),\(payments),\(adjustments),\(endingBalance),\(settled)\n"
        }

        return csvContent
    }

    /// Format a Decimal value for CSV (no currency symbol, 2 decimal places)
    private func formatDecimalForCSV(_ value: Decimal) -> String {
        let nsDecimal = value as NSDecimalNumber
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: nsDecimal) ?? "\(value)"
    }

    /// Create a temporary file URL for the CSV export
    private func createCSVFile() -> URL? {
        let csvContent = generateCSVContent()
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileURL = tempDirectory.appendingPathComponent(csvFilename)

        do {
            try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            print("Failed to write CSV file: \(error)")
            return nil
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
                    // Date range header with navigation buttons
                    HStack {
                        // Previous week button
                        Button {
                            navigateToPreviousWeek()
                        } label: {
                            Image(systemName: "chevron.left.circle.fill")
                                .font(.title2)
                                .foregroundStyle(hasEarlierPeriodData ? Theme.accent : Theme.textMuted)
                        }
                        .disabled(!hasEarlierPeriodData)

                        Spacer()

                        // Date range
                        Text(dateRangeDescription)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)

                        Spacer()

                        // Next week button
                        Button {
                            navigateToNextWeek()
                        } label: {
                            Image(systemName: "chevron.right.circle.fill")
                                .font(.title2)
                                .foregroundStyle(isViewingCurrentWeek ? Theme.textMuted : Theme.accent)
                        }
                        .disabled(isViewingCurrentWeek)
                    }

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

            // MARK: - Prior Period Alerts Section
            if unsettledFromPriorPeriodCount > 0 || !balanceMismatchPlayers.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        // Unsettled from prior period warning
                        if unsettledFromPriorPeriodCount > 0 {
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Theme.warning)
                                    .font(.title3)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(unsettledFromPriorPeriodCount) player\(unsettledFromPriorPeriodCount == 1 ? "" : "s") unsettled from prior period")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(Theme.warning)

                                    Text("Balances carried forward")
                                        .font(.caption)
                                        .foregroundStyle(Theme.textSecondary)
                                }

                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }

                        // Balance mismatch warning (if any)
                        if !balanceMismatchPlayers.isEmpty {
                            HStack(spacing: 10) {
                                Image(systemName: "arrow.left.arrow.right.circle.fill")
                                    .foregroundStyle(Theme.danger)
                                    .font(.title3)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Balance verification issue")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(Theme.danger)

                                    Text("Starting balances carried from previous period")
                                        .font(.caption)
                                        .foregroundStyle(Theme.textSecondary)
                                }

                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    HStack {
                        Text("Period Alerts")
                        Spacer()
                        if unsettledFromPriorPeriodCount > 0 {
                            Text("\(unsettledFromPriorPeriodCount)")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Theme.warning)
                                .clipShape(Capsule())
                        }
                    }
                }
                .listRowBackground(Theme.cardBackground)
            }

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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let fileURL = csvFileURL {
                    ShareLink(item: fileURL) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Button {
                        csvFileURL = createCSVFile()
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .onAppear {
            // Pre-generate CSV file URL
            csvFileURL = createCSVFile()
        }
        .onChange(of: selectedWeekEndingDate) { _, _ in
            // Regenerate CSV when week changes
            csvFileURL = createCSVFile()
        }
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

    /// Navigate to the previous week
    private func navigateToPreviousWeek() {
        if let previousWeek = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: selectedWeekEndingDate) {
            selectedWeekEndingDate = previousWeek
        }
    }

    /// Navigate to the next week
    private func navigateToNextWeek() {
        if let nextWeek = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: selectedWeekEndingDate) {
            let mostRecent = WeeklySettlementView.mostRecentSunday()
            // Don't go past the current week
            if nextWeek <= mostRecent {
                selectedWeekEndingDate = nextWeek
            }
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

                    // Collection status badge
                    if let badge = collectionStatusBadge {
                        badge
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

    /// Collection status badge view if player has a collection status set
    @ViewBuilder
    private var collectionStatusBadge: some View? {
        if let status = report.player.collectionStatus, status != .noStatus {
            Text(status.displayName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(collectionStatusColor(for: status))
                .clipShape(Capsule())
        }
    }

    /// Get the color for a collection status
    private func collectionStatusColor(for status: CollectionStatus) -> Color {
        switch status {
        case .noStatus: return Theme.textMuted
        case .reminded: return Theme.warning // Yellow/orange
        case .promised: return Theme.scheduled // Blue
        case .overdue: return Theme.danger // Red
        }
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

    /// Show payment recording sheet
    @State private var showPaymentSheet: Bool = false

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

            // MARK: - Collection Status Section (only show if player has collection status)
            if let status = player.collectionStatus, status != .noStatus {
                Section {
                    NavigationLink {
                        PlayerDetailView(player: player)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: collectionStatusIcon(for: status))
                                .font(.title2)
                                .foregroundStyle(collectionStatusColor(for: status))

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Collection Status")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.textSecondary)

                                HStack(spacing: 8) {
                                    Text(status.displayName)
                                        .font(.headline)
                                        .foregroundStyle(Theme.textPrimary)

                                    // Show promised date if applicable
                                    if status == .promised, let promisedDate = player.promisedPaymentDate {
                                        Text("by \(promisedDate, style: .date)")
                                            .font(.caption)
                                            .foregroundStyle(Theme.textSecondary)
                                    }
                                }
                            }

                            Spacer()

                            Text("Edit")
                                .font(.subheadline)
                                .foregroundStyle(Theme.accent)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Collection Status")
                }
                .listRowBackground(Theme.cardBackground)
            }

            // MARK: - Quick Payment Section (only show if player owes money)
            if report.endingBalance > 0 {
                Section {
                    Button {
                        showPaymentSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "dollarsign.circle.fill")
                                .font(.title2)
                                .foregroundStyle(Theme.accent)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Record Payment")
                                    .font(.headline)
                                    .foregroundStyle(Theme.textPrimary)

                                Text("Player owes \(formatCurrency(report.endingBalance))")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("Quick Actions")
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
        .sheet(isPresented: $showPaymentSheet) {
            QuickPaymentSheet(
                player: player,
                amountOwed: report.endingBalance
            )
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

    // MARK: - Collection Status Helpers

    /// Get the color for a collection status
    private func collectionStatusColor(for status: CollectionStatus) -> Color {
        switch status {
        case .noStatus: return Theme.textMuted
        case .reminded: return Theme.warning // Yellow/orange
        case .promised: return Theme.scheduled // Blue
        case .overdue: return Theme.danger // Red
        }
    }

    /// Get the icon for a collection status
    private func collectionStatusIcon(for status: CollectionStatus) -> String {
        switch status {
        case .noStatus: return "questionmark.circle"
        case .reminded: return "bell.badge.fill"
        case .promised: return "calendar.badge.clock"
        case .overdue: return "exclamationmark.triangle.fill"
        }
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

// MARK: - Quick Payment Sheet

struct QuickPaymentSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let player: Player
    let amountOwed: Decimal

    @State private var paymentAmount: String = ""
    @State private var selectedMethod: PaymentMethod = .cash
    @State private var note: String = ""
    @State private var showSuccessMessage: Bool = false

    private var amountDecimal: Decimal? {
        guard let doubleValue = Double(paymentAmount), doubleValue > 0 else { return nil }
        return Decimal(doubleValue)
    }

    private var isValidInput: Bool {
        amountDecimal != nil
    }

    private var paymentDescription: String {
        let methodText = selectedMethod.rawValue
        var description = "Payment received from \(player.name) via \(methodText)"
        if !note.trimmingCharacters(in: .whitespaces).isEmpty {
            description += " - \(note.trimmingCharacters(in: .whitespaces))"
        }
        return description
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Amount Section
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        // Amount input
                        HStack {
                            Text("$")
                                .font(.title2)
                                .foregroundStyle(Theme.textMuted)
                            TextField("0.00", text: $paymentAmount)
                                .keyboardType(.decimalPad)
                                .font(.title2.bold())
                        }

                        // Quick buttons
                        HStack(spacing: 12) {
                            Button {
                                paymentAmount = "\(amountOwed)"
                            } label: {
                                Text("Full Payment")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.accent)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(Theme.accent.opacity(0.15))
                                    .cornerRadius(Theme.cornerRadiusSmall)
                            }
                            .buttonStyle(.plain)

                            if amountOwed > 50 {
                                Button {
                                    paymentAmount = "\(amountOwed / 2)"
                                } label: {
                                    Text("Partial (50%)")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Theme.warning)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .background(Theme.warning.opacity(0.15))
                                        .cornerRadius(Theme.cornerRadiusSmall)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                } header: {
                    Text("Payment Amount")
                } footer: {
                    Text("Player owes \(formatCurrency(amountOwed))")
                }

                // MARK: - Payment Method Section
                Section {
                    Picker("Method", selection: $selectedMethod) {
                        ForEach(PaymentMethod.allCases) { method in
                            Label(method.rawValue, systemImage: method.icon)
                                .tag(method)
                        }
                    }
                } header: {
                    Text("Payment Method")
                }

                // MARK: - Note Section
                Section {
                    TextField("Add a note (optional)", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Note")
                }

                // MARK: - Preview Section
                if let displayAmount = amountDecimal {
                    Section {
                        LabeledContent("Amount") {
                            Text(formatCurrency(displayAmount))
                                .fontWeight(.semibold)
                        }

                        LabeledContent("Method") {
                            Label(selectedMethod.rawValue, systemImage: selectedMethod.icon)
                        }

                        LabeledContent("Balance Impact") {
                            Text("-\(formatCurrency(displayAmount))")
                                .foregroundStyle(Theme.accent)
                                .fontWeight(.semibold)
                        }

                        if !note.trimmingCharacters(in: .whitespaces).isEmpty {
                            LabeledContent("Note") {
                                Text(note.trimmingCharacters(in: .whitespaces))
                                    .foregroundStyle(Theme.textMuted)
                            }
                        }
                    } header: {
                        Text("Preview")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Record Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        savePayment()
                    }
                    .disabled(!isValidInput)
                }
            }
            .overlay {
                if showSuccessMessage {
                    successOverlay
                }
            }
        }
        .onAppear {
            // Pre-fill with full amount owed
            paymentAmount = "\(amountOwed)"
        }
    }

    // MARK: - Success Overlay

    private var successOverlay: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(Theme.accent)

            Text("Payment Recorded")
                .font(.title2.bold())
                .foregroundStyle(Theme.textPrimary)

            if let amount = amountDecimal {
                Text(formatCurrency(amount))
                    .font(.title3)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(40)
        .background(Theme.cardBackground)
        .cornerRadius(Theme.cornerRadius)
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
    }

    // MARK: - Actions

    private func savePayment() {
        guard let amount = amountDecimal else { return }

        // Create ledger entry (negative amount reduces player's debt)
        let ledgerEntry = LedgerEntry(
            amount: -amount,
            type: .paymentLogged,
            entryDescription: paymentDescription,
            player: player
        )

        modelContext.insert(ledgerEntry)

        // Show success message briefly then dismiss
        withAnimation {
            showSuccessMessage = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            dismiss()
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
