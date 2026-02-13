import Foundation

/// Risk signals that identify players needing bookie attention
enum PlayerRiskSignal: String, CaseIterable, Identifiable {
    case nearLimit   // Balance > 75% of credit limit
    case overdue     // Has overdue collection status
    case hotStreak   // Top 3 winners in last 7 days
    case losingBig   // Top 3 losers in last 7 days

    var id: String { rawValue }
}

/// Service for calculating player risk signals
/// Identifies players that need bookie attention based on financial and betting patterns
enum PlayerRiskService {

    /// Calculates risk signals for all active players
    /// - Parameters:
    ///   - players: All players to evaluate
    ///   - bets: All bets (used for hot streak / losing big calculations)
    ///   - ledgerEntries: All ledger entries (used for balance calculations)
    /// - Returns: Dictionary mapping players with risk signals to their signal list.
    ///           Players with no signals are omitted.
    static func calculateRiskSignals(
        players: [Player],
        bets: [Bet],
        ledgerEntries: [LedgerEntry]
    ) -> [Player: [PlayerRiskSignal]] {
        let activePlayers = players.filter { $0.status == .active }

        // Pre-group bets and ledger entries by player ID for efficient lookup
        let betsByPlayer = Dictionary(grouping: bets, by: { $0.player?.id })
        let ledgerByPlayer = Dictionary(grouping: ledgerEntries, by: { $0.player?.id })

        // Calculate 7-day net results for hot streak / losing big
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let netResultsByPlayer = calculateNetResults(
            players: activePlayers,
            bets: bets,
            since: sevenDaysAgo
        )

        // Find top 3 winners and top 3 losers
        let sortedByNet = netResultsByPlayer.sorted { $0.value > $1.value }
        let topWinnerIDs = Set(sortedByNet.prefix(3).filter { $0.value > 0 }.map { $0.key })
        let topLoserIDs = Set(sortedByNet.suffix(3).filter { $0.value < 0 }.map { $0.key })

        var result: [Player: [PlayerRiskSignal]] = [:]

        for player in activePlayers {
            var signals: [PlayerRiskSignal] = []

            // Near limit: balance owed > 75% of credit limit
            if player.creditLimit > 0 {
                let playerLedger = ledgerByPlayer[player.id] ?? []
                let playerBets = betsByPlayer[player.id] ?? []
                let balanceOwed = BalanceService.balanceOwed(from: playerLedger)
                let liability = BalanceService.openLiability(from: playerBets)
                let used = balanceOwed + liability
                let threshold = player.creditLimit * Decimal(string: "0.75")!
                if used >= threshold {
                    signals.append(.nearLimit)
                }
            }

            // Overdue: collection status is .overdue
            if player.collectionStatus == .overdue {
                signals.append(.overdue)
            }

            // Hot streak: top 3 winners in last 7 days
            if topWinnerIDs.contains(player.id) {
                signals.append(.hotStreak)
            }

            // Losing big: top 3 losers in last 7 days
            if topLoserIDs.contains(player.id) {
                signals.append(.losingBig)
            }

            if !signals.isEmpty {
                result[player] = signals
            }
        }

        return result
    }

    /// Calculates net betting results per player over a time period
    /// Positive = player won money (bookie lost), Negative = player lost money (bookie won)
    /// - Parameters:
    ///   - players: Players to evaluate
    ///   - bets: All bets
    ///   - since: Start date for the calculation window
    /// - Returns: Dictionary of player ID to net result amount
    private static func calculateNetResults(
        players: [Player],
        bets: [Bet],
        since: Date
    ) -> [UUID: Decimal] {
        let recentGradedBets = bets.filter { bet in
            bet.createdAt >= since &&
            bet.gradeResult != nil &&
            (bet.status == .graded || bet.status == .settled)
        }

        var netResults: [UUID: Decimal] = [:]

        for bet in recentGradedBets {
            guard let playerId = bet.player?.id else { continue }

            let payout = LiabilityService.calculatePayout(stake: bet.stake, odds: bet.odds)
            switch bet.gradeResult {
            case .win:
                // Player won: they gain payout amount
                netResults[playerId, default: .zero] += payout
            case .loss:
                // Player lost: they lose their stake
                netResults[playerId, default: .zero] -= bet.stake
            case .push, .none:
                break
            }
        }

        return netResults
    }
}
