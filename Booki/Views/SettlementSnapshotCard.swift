import SwiftUI
import SwiftData

/// Dashboard card showing weekly settlement status at a glance
struct SettlementSnapshotCard: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var players: [Player]
    @Query private var bets: [Bet]
    @Query private var ledgerEntries: [LedgerEntry]
    @Query private var playerSettlements: [PlayerSettlement]
    @Query private var settlementPeriods: [SettlementPeriod]

    /// ID of player who was just marked as paid (for confirmation feedback)
    @State private var recentlyPaidPlayerId: UUID?

    /// Current week ending date (Sunday)
    private var currentWeekEndingDate: Date {
        WeeklySettlementView.mostRecentSunday()
    }

    /// Current week start date (Monday)
    private var currentWeekStartDate: Date {
        Calendar.current.date(byAdding: .day, value: -6, to: currentWeekEndingDate) ?? currentWeekEndingDate
    }

    /// Whether a settlement period exists for the current week
    private var hasActiveSettlementPeriod: Bool {
        settlementPeriods.contains { period in
            Calendar.current.isDate(period.weekEndingDate, inSameDayAs: currentWeekEndingDate)
        }
    }

    /// Date range description (e.g., "Feb 3 - Feb 9, 2026")
    private var dateRangeDescription: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"

        let yearFormatter = DateFormatter()
        yearFormatter.dateFormat = "MMM d, yyyy"

        let startStr = formatter.string(from: currentWeekStartDate)
        let endStr = yearFormatter.string(from: currentWeekEndingDate)

        return "\(startStr) - \(endStr)"
    }

    /// Active players
    private var activePlayers: [Player] {
        players.filter { $0.status == .active }
    }

    /// Player settlement reports for current period
    private var playerReports: [PlayerSettlementReport] {
        activePlayers.map { player in
            SettlementService.calculatePlayerReport(
                player: player,
                periodStart: currentWeekStartDate,
                periodEnd: currentWeekEndingDate,
                bets: bets,
                ledgerEntries: ledgerEntries
            )
        }
    }

    /// Total owed to bookie (positive ending balances)
    private var totalOwedToBookie: Decimal {
        playerReports.filter { $0.endingBalance > 0 }
            .reduce(Decimal.zero) { $0 + $1.endingBalance }
    }

    /// Total owed to players (negative ending balances, shown as positive)
    private var totalOwedToPlayers: Decimal {
        abs(playerReports.filter { $0.endingBalance < 0 }
            .reduce(Decimal.zero) { $0 + $1.endingBalance })
    }

    /// Count of players not yet settled for this period
    private var unpaidPlayersCount: Int {
        activePlayers.filter { player in
            // Player owes money AND is not settled
            let report = playerReports.first { $0.player.id == player.id }
            let owes = (report?.endingBalance ?? 0) > 0
            let settled = playerSettlements.contains { settlement in
                settlement.player?.id == player.id &&
                Calendar.current.isDate(settlement.periodWeekEndingDate, inSameDayAs: currentWeekEndingDate) &&
                settlement.isSettled
            }
            return owes && !settled
        }.count
    }

    /// Count of players with overdue collection status
    private var overduePlayersCount: Int {
        activePlayers.filter { $0.collectionStatus == .overdue }.count
    }

    /// Top 3 unpaid players sorted by amount owed (highest first)
    private var topUnpaidPlayers: [(report: PlayerSettlementReport, isSettled: Bool)] {
        playerReports
            .map { report -> (report: PlayerSettlementReport, isSettled: Bool) in
                let settled = playerSettlements.contains { settlement in
                    settlement.player?.id == report.player.id &&
                    Calendar.current.isDate(settlement.periodWeekEndingDate, inSameDayAs: currentWeekEndingDate) &&
                    settlement.isSettled
                }
                return (report: report, isSettled: settled)
            }
            .filter { $0.report.endingBalance != 0 && !$0.isSettled }
            .sorted { abs($0.report.endingBalance) > abs($1.report.endingBalance) }
            .prefix(3)
            .map { $0 }
    }

    /// Days until next Sunday (next settlement period)
    private var daysUntilNextSettlement: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        // weekday: 1=Sun, 2=Mon, ..., 7=Sat
        // If today is Sunday, next settlement is in 7 days
        let daysUntilSunday = weekday == 1 ? 7 : (8 - weekday)
        return daysUntilSunday
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "calendar.badge.clock")
                    .font(.title2)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Theme.accent, Theme.accentSecondary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Reconciliation")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)

                    Text(dateRangeDescription)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer()

                // Overdue badge
                if overduePlayersCount > 0 {
                    Text("\(overduePlayersCount) overdue")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(Theme.danger)
                        )
                }
            }

            // Amounts row
            HStack(spacing: 16) {
                // Owed to bookie
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.accent)
                        Text("Owed to You")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    Text(formatCurrency(totalOwedToBookie))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.accent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Owed to players
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.danger)
                        Text("You Owe")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    Text(formatCurrency(totalOwedToPlayers))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.danger)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Stats row
            HStack(spacing: 16) {
                // Unpaid players
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle.badge.clock")
                        .font(.subheadline)
                        .foregroundStyle(unpaidPlayersCount > 0 ? Theme.warning : Theme.textMuted)

                    Text("\(unpaidPlayersCount) unpaid")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(unpaidPlayersCount > 0 ? Theme.warning : Theme.textSecondary)
                }

                // Overdue players
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(overduePlayersCount > 0 ? Theme.danger : Theme.textMuted)

                    Text("\(overduePlayersCount) overdue")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(overduePlayersCount > 0 ? Theme.danger : Theme.textSecondary)
                }

                Spacer()
            }

            // Top unpaid players with quick Mark Paid actions
            if !topUnpaidPlayers.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(topUnpaidPlayers.enumerated()), id: \.element.report.player.id) { index, item in
                        if index > 0 {
                            Divider()
                                .background(Theme.divider)
                        }

                        HStack(spacing: 10) {
                            // Player name
                            Text(item.report.player.name)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)

                            Spacer()

                            // Amount owed
                            Text(formatCurrency(abs(item.report.endingBalance)))
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(item.report.endingBalance > 0 ? Theme.danger : Theme.accent)

                            // Mark Paid button or confirmation
                            if recentlyPaidPlayerId == item.report.player.id {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption)
                                    Text("Paid")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundStyle(Theme.accent)
                                .transition(.scale.combined(with: .opacity))
                            } else {
                                Button {
                                    markAsPaid(player: item.report.player, amount: item.report.endingBalance)
                                } label: {
                                    Text("Mark Paid")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(Theme.background)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Theme.accent)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                                .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Theme.elevatedBackground.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
            }

            // Next settlement or View Settlements button
            if !hasActiveSettlementPeriod && activePlayers.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textMuted)

                    Text("Next reconciliation in \(daysUntilNextSettlement) day\(daysUntilNextSettlement == 1 ? "" : "s")")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            } else {
                NavigationLink {
                    WeeklySettlementView()
                } label: {
                    HStack {
                        Text("View Reconciliations")
                            .font(.system(size: 14, weight: .bold))

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                    }
                    .foregroundStyle(Theme.accent)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(Theme.accent.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
    }

    // MARK: - Actions

    /// Records a full payment for a player, creating a ledger entry
    private func markAsPaid(player: Player, amount: Decimal) {
        // Create ledger entry: negative amount reduces player's debt
        // For positive balance (player owes), record -amount
        // For negative balance (bookie owes), record +abs(amount) — paying out
        let paymentAmount = amount > 0 ? -amount : abs(amount)

        let ledgerEntry = LedgerEntry(
            amount: paymentAmount,
            type: .paymentLogged,
            entryDescription: "Full payment – \(player.name) (quick action)",
            player: player
        )
        modelContext.insert(ledgerEntry)

        // Show confirmation with animation
        withAnimation(.spring(response: 0.3)) {
            recentlyPaidPlayerId = player.id
        }

        // Clear confirmation after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeOut(duration: 0.3)) {
                if recentlyPaidPlayerId == player.id {
                    recentlyPaidPlayerId = nil
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatCurrency(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: amount as NSDecimalNumber) ?? "$\(amount)"
    }
}
