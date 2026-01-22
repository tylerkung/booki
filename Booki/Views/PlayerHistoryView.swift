import SwiftUI
import SwiftData

/// View for players to see their submitted bets and their status
struct PlayerHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allBets: [Bet]
    @Query private var allLedgerEntries: [LedgerEntry]
    @Query private var events: [Event]

    let player: Player

    // MARK: - Computed Properties

    /// All bets for this player, sorted by creation date (newest first)
    private var playerBets: [Bet] {
        allBets.filter { $0.player?.id == player.id }
            .sorted { $0.createdAt > $1.createdAt }
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

    /// Color for balance display
    private var balanceColor: Color {
        // Positive balance = player owes bookie (secondary)
        // Negative balance = bookie owes player (green - player is winning)
        balanceSummary.balanceOwed >= 0 ? Color.secondary : Color.green
    }

    /// Color for available credit
    private var availableCreditColor: Color {
        balanceSummary.availableCredit >= 0 ? Color.primary : Color.red
    }

    // MARK: - Body

    var body: some View {
        List {
            // Balance Section
            balanceSection

            // Bet History Section
            betHistorySection
        }
        .navigationTitle("My Bets")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Section Views

    @ViewBuilder
    private var balanceSection: some View {
        Section {
            // Current Balance (prominent)
            VStack(alignment: .leading, spacing: 4) {
                Text("Current Balance")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(formatCurrency(balanceSummary.balanceOwed))
                    .font(.largeTitle.bold())
                    .foregroundStyle(balanceColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)

            // Balance Details
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Available Credit")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formatCurrency(balanceSummary.availableCredit))
                        .font(.headline)
                        .foregroundStyle(availableCreditColor)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Credit Limit")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formatCurrency(player.creditLimit))
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }

            // Open Liability
            if balanceSummary.openLiability > 0 {
                HStack {
                    Text("Open Liability")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatCurrency(balanceSummary.openLiability))
                        .fontWeight(.medium)
                        .foregroundStyle(.orange)
                }
            }
        } header: {
            Text("Account Summary")
        }
    }

    @ViewBuilder
    private var betHistorySection: some View {
        Section {
            if playerBets.isEmpty {
                ContentUnavailableView(
                    "No Bets Yet",
                    systemImage: "list.bullet.clipboard",
                    description: Text("Your bet requests will appear here.")
                )
            } else {
                ForEach(playerBets) { bet in
                    HistoryBetRowView(
                        bet: bet,
                        eventName: eventName(for: bet)
                    )
                }
            }
        } header: {
            Text("Bet History (\(playerBets.count))")
        }
    }

    // MARK: - Helpers

    private func eventName(for bet: Bet) -> String {
        if let event = events.first(where: { $0.id.uuidString == bet.eventId }) {
            return "\(event.awayTeam) @ \(event.homeTeam)"
        }
        return "Event \(bet.eventId.prefix(8))"
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }
}

// MARK: - History Bet Row View

/// Row view for displaying a single bet in player history
struct HistoryBetRowView: View {
    let bet: Bet
    let eventName: String

    // MARK: - Computed Properties

    private var formattedOdds: String {
        bet.odds > 0 ? "+\(bet.odds)" : "\(bet.odds)"
    }

    private var formattedStake: String {
        formatCurrency(bet.stake)
    }

    private var statusColor: Color {
        switch bet.status {
        case .pending: return .orange
        case .accepted: return .blue
        case .declined: return .red
        case .readyToGrade: return .purple
        case .graded: return .indigo
        case .settled: return .green
        case .void: return .gray
        }
    }

    private var statusText: String {
        bet.status.rawValue.capitalized
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: bet.createdAt)
    }

    /// Calculate payout amount for settled bets
    private var payoutAmount: Decimal? {
        guard bet.status == .settled, let result = bet.gradeResult else {
            return nil
        }

        switch result {
        case .win:
            // Win: player receives payout (profit)
            return LiabilityService.calculatePayout(stake: bet.stake, odds: bet.odds)
        case .loss:
            // Loss: player loses stake (negative)
            return -bet.stake
        case .push:
            // Push: no gain or loss
            return Decimal.zero
        }
    }

    /// Format payout for display
    private var formattedPayout: String? {
        guard let payout = payoutAmount else { return nil }
        return formatCurrency(payout)
    }

    /// Color for payout display
    private var payoutColor: Color {
        guard let payout = payoutAmount else { return .secondary }
        if payout > 0 {
            return .green
        } else if payout < 0 {
            return .red
        } else {
            return .secondary
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Row 1: Event name and status badge
            HStack {
                Text(eventName)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                Text(statusText)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor)
                    .clipShape(Capsule())
            }

            // Row 2: Market, side, odds
            HStack {
                Text(bet.market.capitalized)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("•")
                    .foregroundStyle(.secondary)

                Text(bet.side)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("•")
                    .foregroundStyle(.secondary)

                Text(formattedOdds)
                    .font(.subheadline)
                    .foregroundStyle(.blue)
            }

            // Row 3: Stake
            HStack {
                Text("Stake:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(formattedStake)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }

            // Row 4: Outcome and Payout (for settled bets)
            if bet.status == .settled, let result = bet.gradeResult {
                HStack {
                    // Outcome
                    HStack(spacing: 4) {
                        Text("Result:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(result.rawValue.capitalized)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(gradeResultColor(result))
                    }

                    Spacer()

                    // Payout
                    if let payout = formattedPayout {
                        HStack(spacing: 4) {
                            Text("Payout:")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Text(payout)
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundStyle(payoutColor)
                        }
                    }
                }
            }

            // Row 5: Date
            Text(formattedDate)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private func gradeResultColor(_ result: GradeResult) -> Color {
        switch result {
        case .win: return .green
        case .loss: return .red
        case .push: return .orange
        }
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }
}

#Preview {
    NavigationStack {
        PlayerHistoryView(player: Player(
            name: "Test Player",
            email: "test@example.com",
            creditLimit: 1000
        ))
    }
    .modelContainer(for: [Player.self, Bet.self, LedgerEntry.self, Event.self], inMemory: true)
}
