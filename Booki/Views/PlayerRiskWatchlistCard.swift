import SwiftUI
import SwiftData

/// Card showing players with active risk signals on the bookie dashboard.
/// Limited to 5 players with a "View All" link when more exist.
struct PlayerRiskWatchlistCard: View {
    @Query private var players: [Player]
    @Query private var bets: [Bet]
    @Query private var ledgerEntries: [LedgerEntry]

    private let maxDisplay = 5

    private var riskPlayers: [(player: Player, signals: [PlayerRiskSignal])] {
        let signalMap = PlayerRiskService.calculateRiskSignals(
            players: players,
            bets: bets,
            ledgerEntries: ledgerEntries
        )
        // Sort by number of signals descending, then by name
        return signalMap
            .map { (player: $0.key, signals: $0.value) }
            .sorted {
                if $0.signals.count != $1.signals.count {
                    return $0.signals.count > $1.signals.count
                }
                return $0.player.bookieDisplayName < $1.player.bookieDisplayName
            }
    }

    var body: some View {
        if riskPlayers.isEmpty {
            emptyState
        } else {
            ForEach(riskPlayers.prefix(maxDisplay), id: \.player.id) { item in
                NavigationLink(value: item.player) {
                    PlayerRiskRow(
                        player: item.player,
                        signals: item.signals,
                        ledgerEntries: ledgerEntries.filter { $0.player?.id == item.player.id },
                        bets: bets.filter { $0.player?.id == item.player.id }
                    )
                }
            }

            if riskPlayers.count > maxDisplay {
                NavigationLink(value: riskPlayers[0].player) {
                    HStack {
                        Text("View All (\(riskPlayers.count))")
                            .font(.subheadline.bold())
                            .foregroundStyle(Theme.accent)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Theme.textMuted)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var emptyState: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(Theme.accent)

            Text("No members need attention")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)

            Spacer()
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Player Risk Row

private struct PlayerRiskRow: View {
    let player: Player
    let signals: [PlayerRiskSignal]
    let ledgerEntries: [LedgerEntry]
    let bets: [Bet]

    /// Balance / credit limit ratio for the progress bar (0.0–1.0)
    private var usageRatio: Double {
        guard player.creditLimit > 0 else { return 0 }
        let balanceOwed = BalanceService.balanceOwed(from: ledgerEntries)
        let liability = BalanceService.openLiability(from: bets)
        let used = balanceOwed + liability
        let ratio = NSDecimalNumber(decimal: used).doubleValue
            / NSDecimalNumber(decimal: player.creditLimit).doubleValue
        return min(max(ratio, 0), 1)
    }

    private var progressColor: Color {
        if usageRatio >= 0.9 { return Theme.danger }
        if usageRatio >= 0.75 { return Theme.warning }
        return Theme.accent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top: name + badges
            HStack(spacing: 6) {
                Text(player.bookieDisplayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                Spacer()

                ForEach(signals) { signal in
                    RiskBadge(signal: signal)
                }
            }

            // Progress bar: balance / credit ratio
            if player.creditLimit > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Theme.elevatedBackground)
                                .frame(height: 6)

                            RoundedRectangle(cornerRadius: 3)
                                .fill(progressColor)
                                .frame(width: geo.size.width * usageRatio, height: 6)
                        }
                    }
                    .frame(height: 6)

                    Text("\(Int(usageRatio * 100))% of credit used")
                        .font(.caption2)
                        .foregroundStyle(Theme.textMuted)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Risk Badge

private struct RiskBadge: View {
    let signal: PlayerRiskSignal

    private var label: String {
        switch signal {
        case .nearLimit: return "Near Limit"
        case .overdue: return "Overdue"
        case .hotStreak: return "Hot Streak"
        case .losingBig: return "Losing Big"
        }
    }

    private var color: Color {
        switch signal {
        case .nearLimit: return Theme.warning    // orange
        case .overdue: return Theme.danger       // red
        case .hotStreak: return Theme.accent     // green (teal)
        case .losingBig: return Theme.danger     // red
        }
    }

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color)
            .clipShape(Capsule())
    }
}
