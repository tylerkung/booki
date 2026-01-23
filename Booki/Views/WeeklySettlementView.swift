import SwiftUI
import SwiftData

struct WeeklySettlementView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var bets: [Bet]
    @Query private var players: [Player]
    @Query private var ledgerEntries: [LedgerEntry]

    /// Currently selected week start date (Monday)
    @State private var selectedWeekStart: Date = WeeklySettlementView.currentWeekStart()

    /// Whether export sheet is showing
    @State private var showingExportSheet = false

    /// Export content for sharing
    @State private var exportContent = ""

    // MARK: - Computed Properties

    /// End of the selected week (Sunday 23:59:59)
    private var selectedWeekEnd: Date {
        Calendar.current.date(byAdding: .day, value: 7, to: selectedWeekStart)!
            .addingTimeInterval(-1)
    }

    /// Bets that were graded during the selected week
    private var weeklyGradedBets: [Bet] {
        bets.filter { bet in
            // Filter for settled bets with a grade result
            guard bet.status == .settled || bet.status == .graded,
                  bet.gradeResult != nil else { return false }

            // Check if the bet was created/settled during the week
            // For now, we use createdAt as a proxy since we don't track settledAt
            // Ideally we'd use ledger entries to determine when bets were settled
            return bet.createdAt >= selectedWeekStart && bet.createdAt <= selectedWeekEnd
        }
    }

    /// Ledger entries (settlements) during the selected week
    private var weeklySettlements: [LedgerEntry] {
        ledgerEntries.filter { entry in
            entry.type == .settlement &&
            entry.createdAt >= selectedWeekStart &&
            entry.createdAt <= selectedWeekEnd
        }
    }

    /// Summary statistics for the week
    private var weeklySummary: WeeklySummary {
        calculateWeeklySummary()
    }

    /// Per-player breakdown
    private var playerBreakdowns: [PlayerBreakdown] {
        calculatePlayerBreakdowns()
    }

    // MARK: - Static Methods

    /// Get the start of the current week (Monday)
    static func currentWeekStart() -> Date {
        let calendar = Calendar.current
        let today = Date()

        // Get the weekday (1 = Sunday, 2 = Monday, ..., 7 = Saturday)
        let weekday = calendar.component(.weekday, from: today)

        // Calculate days to subtract to get to Monday
        // If Sunday (1), go back 6 days; Monday (2) is 0 days back
        let daysToSubtract = weekday == 1 ? 6 : weekday - 2

        let mondayDate = calendar.date(byAdding: .day, value: -daysToSubtract, to: today)!
        return calendar.startOfDay(for: mondayDate)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // MARK: - Week Picker
                weekPickerSection

                // MARK: - Summary Stats
                summarySection

                // MARK: - Per-Player Breakdown
                playerBreakdownSection
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle("Weekly Settlement")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    prepareExport()
                    showingExportSheet = true
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: $showingExportSheet) {
            ExportSettlementSheet(content: exportContent)
        }
    }

    // MARK: - Week Picker Section

    private var weekPickerSection: some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    moveWeek(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                        .foregroundStyle(Theme.accent)
                }

                Spacer()

                VStack(spacing: 4) {
                    Text(weekRangeString)
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)

                    Text(isCurrentWeek ? "This Week" : relativeDateString)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer()

                Button {
                    moveWeek(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.title2)
                        .foregroundStyle(canMoveForward ? Theme.accent : Theme.textMuted)
                }
                .disabled(!canMoveForward)
            }
            .padding(.horizontal, 8)

            // Jump to current week button
            if !isCurrentWeek {
                Button {
                    selectedWeekStart = WeeklySettlementView.currentWeekStart()
                } label: {
                    Text("Go to Current Week")
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .padding()
        .background(Theme.cardBackground)
        .cornerRadius(12)
    }

    // MARK: - Summary Section

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SUMMARY")
                .font(.caption)
                .fontWeight(.semibold)
                .tracking(1)
                .foregroundStyle(Theme.textMuted)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                // Total Bets Graded
                SummaryStatCard(
                    title: "Bets Graded",
                    value: "\(weeklySummary.totalBetsGraded)",
                    icon: "checkmark.circle.fill",
                    color: Theme.accent
                )

                // Total Won by Players
                SummaryStatCard(
                    title: "Won by Players",
                    value: formatCurrency(weeklySummary.totalWonByPlayers),
                    icon: "arrow.down.circle.fill",
                    color: Theme.danger
                )

                // Total Lost by Players
                SummaryStatCard(
                    title: "Lost by Players",
                    value: formatCurrency(weeklySummary.totalLostByPlayers),
                    icon: "arrow.up.circle.fill",
                    color: Theme.accent
                )

                // Net Movement
                SummaryStatCard(
                    title: "Net Movement",
                    value: formatCurrency(weeklySummary.netMovement),
                    icon: "arrow.left.arrow.right.circle.fill",
                    color: weeklySummary.netMovement >= 0 ? Theme.accent : Theme.danger
                )
            }
        }
        .padding()
        .background(Theme.cardBackground)
        .cornerRadius(12)
    }

    // MARK: - Player Breakdown Section

    private var playerBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("PER-PLAYER BREAKDOWN")
                .font(.caption)
                .fontWeight(.semibold)
                .tracking(1)
                .foregroundStyle(Theme.textMuted)

            if playerBreakdowns.isEmpty {
                Text("No settlement activity this week")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                VStack(spacing: 12) {
                    ForEach(playerBreakdowns) { breakdown in
                        PlayerBreakdownRow(breakdown: breakdown)
                    }
                }
            }
        }
        .padding()
        .background(Theme.cardBackground)
        .cornerRadius(12)
    }

    // MARK: - Helper Methods

    private var weekRangeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"

        let start = formatter.string(from: selectedWeekStart)
        let end = formatter.string(from: selectedWeekEnd)

        return "\(start) - \(end)"
    }

    private var isCurrentWeek: Bool {
        let currentStart = WeeklySettlementView.currentWeekStart()
        return Calendar.current.isDate(selectedWeekStart, inSameDayAs: currentStart)
    }

    private var canMoveForward: Bool {
        let currentStart = WeeklySettlementView.currentWeekStart()
        return selectedWeekStart < currentStart
    }

    private var relativeDateString: String {
        let currentStart = WeeklySettlementView.currentWeekStart()
        let weeksAgo = Calendar.current.dateComponents([.weekOfYear], from: selectedWeekStart, to: currentStart).weekOfYear ?? 0

        if weeksAgo == 1 {
            return "Last Week"
        } else if weeksAgo > 1 {
            return "\(weeksAgo) weeks ago"
        }
        return ""
    }

    private func moveWeek(by weeks: Int) {
        if let newDate = Calendar.current.date(byAdding: .weekOfYear, value: weeks, to: selectedWeekStart) {
            let currentStart = WeeklySettlementView.currentWeekStart()
            // Don't allow going into the future
            if newDate <= currentStart {
                selectedWeekStart = newDate
            }
        }
    }

    private func calculateWeeklySummary() -> WeeklySummary {
        var totalBetsGraded = 0
        var totalWonByPlayers: Decimal = 0
        var totalLostByPlayers: Decimal = 0

        // Calculate from weekly settlements (ledger entries)
        for entry in weeklySettlements {
            totalBetsGraded += 1

            // Positive ledger amount = player lost (bookie wins)
            // Negative ledger amount = player won (bookie pays)
            if entry.amount > 0 {
                totalLostByPlayers += entry.amount
            } else {
                totalWonByPlayers += abs(entry.amount)
            }
        }

        // Net movement: positive = bookie profit, negative = bookie loss
        let netMovement = totalLostByPlayers - totalWonByPlayers

        return WeeklySummary(
            totalBetsGraded: totalBetsGraded,
            totalWonByPlayers: totalWonByPlayers,
            totalLostByPlayers: totalLostByPlayers,
            netMovement: netMovement
        )
    }

    private func calculatePlayerBreakdowns() -> [PlayerBreakdown] {
        var breakdowns: [UUID: PlayerBreakdown] = [:]

        for entry in weeklySettlements {
            guard let player = entry.player else { continue }

            if breakdowns[player.id] == nil {
                // Get current balance for the player
                let playerLedger = ledgerEntries.filter { $0.player?.id == player.id }
                let currentBalance = BalanceService.balanceOwed(from: playerLedger)

                breakdowns[player.id] = PlayerBreakdown(
                    id: player.id,
                    playerName: player.name,
                    betsSettled: 0,
                    netResult: 0,
                    currentBalance: currentBalance
                )
            }

            breakdowns[player.id]?.betsSettled += 1
            breakdowns[player.id]?.netResult += entry.amount
        }

        // Sort by net result (biggest losses first - good for bookie)
        return breakdowns.values.sorted { $0.netResult > $1.netResult }
    }

    private func formatCurrency(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: amount as NSDecimalNumber) ?? "$\(amount)"
    }

    private func prepareExport() {
        var lines: [String] = []

        // Header
        lines.append("Weekly Settlement Summary")
        lines.append(weekRangeString)
        lines.append("")

        // Summary
        lines.append("--- SUMMARY ---")
        lines.append("Total Bets Graded: \(weeklySummary.totalBetsGraded)")
        lines.append("Total Won by Players: \(formatCurrency(weeklySummary.totalWonByPlayers))")
        lines.append("Total Lost by Players: \(formatCurrency(weeklySummary.totalLostByPlayers))")
        lines.append("Net Movement: \(formatCurrency(weeklySummary.netMovement))")
        lines.append("")

        // Player Breakdown
        lines.append("--- PER-PLAYER BREAKDOWN ---")
        lines.append("Player, Bets Settled, Net Result, Current Balance")

        for breakdown in playerBreakdowns {
            let netStr = formatCurrency(breakdown.netResult)
            let balStr = formatCurrency(breakdown.currentBalance)
            lines.append("\(breakdown.playerName), \(breakdown.betsSettled), \(netStr), \(balStr)")
        }

        exportContent = lines.joined(separator: "\n")
    }
}

// MARK: - Summary Models

struct WeeklySummary {
    let totalBetsGraded: Int
    let totalWonByPlayers: Decimal
    let totalLostByPlayers: Decimal
    let netMovement: Decimal
}

struct PlayerBreakdown: Identifiable {
    let id: UUID
    let playerName: String
    var betsSettled: Int
    var netResult: Decimal
    var currentBalance: Decimal
}

// MARK: - Summary Stat Card

struct SummaryStatCard: View {
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
        .background(Theme.elevatedBackground)
        .cornerRadius(10)
    }
}

// MARK: - Player Breakdown Row

struct PlayerBreakdownRow: View {
    let breakdown: PlayerBreakdown

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(breakdown.playerName)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)

                Text("\(breakdown.betsSettled) bet\(breakdown.betsSettled == 1 ? "" : "s") settled")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                // Net result for this week
                Text(formatNetResult(breakdown.netResult))
                    .font(.subheadline.bold())
                    .foregroundStyle(breakdown.netResult >= 0 ? Theme.accent : Theme.danger)

                // Current balance
                Text("Balance: \(formatCurrency(breakdown.currentBalance))")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding()
        .background(Theme.elevatedBackground)
        .cornerRadius(10)
    }

    private func formatNetResult(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        let formatted = formatter.string(from: amount as NSDecimalNumber) ?? "$\(amount)"

        if amount > 0 {
            return "+\(formatted)"
        }
        return formatted
    }

    private func formatCurrency(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: amount as NSDecimalNumber) ?? "$\(amount)"
    }
}

// MARK: - Export Sheet

struct ExportSettlementSheet: View {
    let content: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Settlement Summary")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)

                ScrollView {
                    Text(content)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .background(Theme.elevatedBackground)
                .cornerRadius(12)

                // Share Button
                ShareLink(item: content) {
                    Label("Share Summary", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .foregroundStyle(Theme.background)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Theme.accent)
                        .cornerRadius(12)
                }

                // Copy to Clipboard Button
                Button {
                    UIPasteboard.general.string = content
                } label: {
                    Label("Copy to Clipboard", systemImage: "doc.on.doc")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Theme.elevatedBackground)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Theme.border, lineWidth: 1)
                        )
                }
            }
            .padding()
            .background(Theme.cardBackground)
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .toolbarBackground(Theme.cardBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        WeeklySettlementView()
    }
    .modelContainer(for: [Bet.self, Player.self, LedgerEntry.self], inMemory: true)
}
