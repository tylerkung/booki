import SwiftUI
import SwiftData

/// Enhanced account summary view for players showing balance, credit utilization, and quick stats
struct AccountView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allBets: [Bet]
    @Query private var allLedgerEntries: [LedgerEntry]

    let player: Player

    // MARK: - Computed Properties

    /// All bets for this player
    private var playerBets: [Bet] {
        allBets.filter { $0.player?.id == player.id }
    }

    /// Ledger entries for this player
    private var playerLedgerEntries: [LedgerEntry] {
        allLedgerEntries.filter { $0.player?.id == player.id }
    }

    /// Player balance summary
    private var balanceSummary: PlayerBalanceSummary {
        BalanceService.playerSummary(
            for: player,
            bets: playerBets,
            ledgerEntries: playerLedgerEntries
        )
    }

    /// Open bets count (pending + accepted)
    private var openBetsCount: Int {
        playerBets.filter { $0.status == .pending || $0.status == .accepted || $0.status == .readyToGrade }.count
    }

    /// Pending bets count (awaiting acceptance)
    private var pendingBetsCount: Int {
        playerBets.filter { $0.status == .pending }.count
    }

    /// Settled bets for win rate calculation
    private var settledBets: [Bet] {
        playerBets.filter { $0.status == .settled && $0.gradeResult != nil }
    }

    /// Win count
    private var winCount: Int {
        settledBets.filter { $0.gradeResult == .win }.count
    }

    /// Loss count
    private var lossCount: Int {
        settledBets.filter { $0.gradeResult == .loss }.count
    }

    /// Win rate percentage
    private var winRate: Double {
        let winsAndLosses = winCount + lossCount
        guard winsAndLosses > 0 else { return 0 }
        return Double(winCount) / Double(winsAndLosses) * 100
    }

    /// Credit utilization percentage (0.0 to 1.0+)
    private var creditUtilization: Double {
        guard player.creditLimit > 0 else { return 0 }
        let used = player.creditLimit - balanceSummary.availableCredit
        return Double(truncating: (used / player.creditLimit) as NSDecimalNumber)
    }

    /// Color for balance display
    private var balanceColor: Color {
        // Positive balance = player owes bookie (red)
        // Negative balance = bookie owes player (green - player is winning)
        balanceSummary.balanceOwed > 0 ? .red : (balanceSummary.balanceOwed < 0 ? .green : .primary)
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Hero Balance Section
                heroBalanceSection

                // Credit Utilization Section
                creditUtilizationSection

                // Quick Stats Section
                quickStatsSection
            }
            .padding()
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Hero Balance Section

    private var heroBalanceSection: some View {
        VStack(spacing: 8) {
            Text("Current Balance")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(formatCurrency(balanceSummary.balanceOwed))
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(balanceColor)

            if balanceSummary.balanceOwed > 0 {
                Text("Amount you owe")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if balanceSummary.balanceOwed < 0 {
                Text("Amount owed to you")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
    }

    // MARK: - Credit Utilization Section

    private var creditUtilizationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Available Credit")
                    .font(.headline)

                Spacer()

                Text(formatCurrency(balanceSummary.availableCredit))
                    .font(.headline)
                    .foregroundColor(balanceSummary.availableCredit >= 0 ? Color.primary : Color.red)
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray5))
                        .frame(height: 12)

                    // Filled portion
                    RoundedRectangle(cornerRadius: 8)
                        .fill(creditUtilizationColor)
                        .frame(width: min(CGFloat(creditUtilization) * geometry.size.width, geometry.size.width), height: 12)
                }
            }
            .frame(height: 12)

            HStack {
                Text("Used: \(formatCurrency(player.creditLimit - balanceSummary.availableCredit))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("Limit: \(formatCurrency(player.creditLimit))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
    }

    /// Color for credit utilization bar
    private var creditUtilizationColor: Color {
        if creditUtilization >= 1.0 {
            return .red
        } else if creditUtilization >= 0.8 {
            return .orange
        } else if creditUtilization >= 0.5 {
            return .yellow
        } else {
            return .green
        }
    }

    // MARK: - Quick Stats Section

    private var quickStatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Stats")
                .font(.headline)

            HStack(spacing: 16) {
                // Open Bets
                statCard(
                    title: "Open Bets",
                    value: "\(openBetsCount)",
                    color: .blue
                )

                // Pending Bets
                statCard(
                    title: "Pending",
                    value: "\(pendingBetsCount)",
                    color: .orange
                )

                // Win Rate
                statCard(
                    title: "Win Rate",
                    value: settledBets.isEmpty ? "—" : String(format: "%.0f%%", winRate),
                    color: .green
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
    }

    private func statCard(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(color)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.1))
        )
    }

    // MARK: - Helpers

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }
}

#Preview {
    NavigationStack {
        AccountView(player: Player(
            name: "Test Player",
            email: "test@example.com",
            creditLimit: 1000
        ))
    }
    .modelContainer(for: [Player.self, Bet.self, LedgerEntry.self], inMemory: true)
}
