import Foundation
import SwiftData

// MARK: - Data Structures

struct PlayerExposure {
    let grossExposure: Decimal
    let pendingBetCount: Int
    let largestPendingBet: Decimal
}

// MARK: - PlayerAttentionService

enum PlayerAttentionService {

    // MARK: - Exposure

    static func calculateExposure(player: Player, bets: [Bet]) -> PlayerExposure {
        let openBets = bets.filter { bet in
            bet.player?.id == player.id &&
            (bet.status == .pending || bet.status == .accepted)
        }

        let grossExposure = openBets.reduce(Decimal.zero) { total, bet in
            total + LiabilityService.calculatePayout(stake: bet.stake, odds: bet.odds)
        }

        let largestPendingBet = openBets.map(\.stake).max() ?? .zero

        return PlayerExposure(
            grossExposure: grossExposure,
            pendingBetCount: openBets.count,
            largestPendingBet: largestPendingBet
        )
    }

    // MARK: - Realized P/L

    /// Returns bookie-perspective P/L: positive = bookie profited, negative = bookie lost money.
    /// For a player win, bookie pays out (negative P/L for bookie).
    /// For a player loss, bookie keeps stake (positive P/L for bookie).
    /// Pass days=0 for all-time.
    static func realizedPL(player: Player, bets: [Bet], days: Int = 0) -> Decimal {
        let cutoff: Date? = days > 0
            ? Calendar.current.date(byAdding: .day, value: -days, to: Date())
            : nil

        let gradedBets = bets.filter { bet in
            bet.player?.id == player.id &&
            bet.gradeResult != nil &&
            bet.gradeResult != .push &&
            (cutoff == nil || bet.createdAt >= cutoff!)
        }

        return gradedBets.reduce(Decimal.zero) { total, bet in
            switch bet.gradeResult {
            case .win:
                // Player won: bookie pays out payout amount
                let payout = LiabilityService.calculatePayout(stake: bet.stake, odds: bet.odds)
                return total - payout
            case .loss:
                // Player lost: bookie keeps the stake
                return total + bet.stake
            default:
                return total
            }
        }
    }

    // MARK: - Volatility

    /// Max absolute daily P/L swing over last 14 days.
    static func volatility(player: Player, bets: [Bet]) -> Decimal {
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: Date())!

        let recentBets = bets.filter { bet in
            bet.player?.id == player.id &&
            bet.gradeResult != nil &&
            bet.gradeResult != .push &&
            bet.createdAt >= cutoff
        }

        guard !recentBets.isEmpty else { return .zero }

        // Group by calendar day
        var dailyPL: [String: Decimal] = [:]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        for bet in recentBets {
            let dayKey = formatter.string(from: bet.createdAt)
            switch bet.gradeResult {
            case .win:
                let payout = LiabilityService.calculatePayout(stake: bet.stake, odds: bet.odds)
                dailyPL[dayKey, default: .zero] -= payout
            case .loss:
                dailyPL[dayKey, default: .zero] += bet.stake
            default:
                break
            }
        }

        return dailyPL.values.map { abs($0) }.max() ?? .zero
    }

    // MARK: - Overdue

    /// Returns (isOverdue, overdueAmount). Overdue if balanceOwed > 0 AND no ledger entry in last thresholdDays.
    static func isOverdue(player: Player, ledgerEntries: [LedgerEntry], thresholdDays: Int = 7) -> (Bool, Decimal) {
        let playerEntries = ledgerEntries.filter { $0.player?.id == player.id }
        let balanceOwed = BalanceService.balanceOwed(from: playerEntries)

        guard balanceOwed > 0 else { return (false, .zero) }

        let cutoff = Calendar.current.date(byAdding: .day, value: -thresholdDays, to: Date())!
        let hasRecentEntry = playerEntries.contains { $0.createdAt >= cutoff }

        if hasRecentEntry {
            return (false, .zero)
        }

        return (true, balanceOwed)
    }

    // MARK: - Win Rate

    /// Wins / (wins + losses), excluding pushes and voids. Returns 0 if no graded bets.
    static func winRate(player: Player, bets: [Bet]) -> Double {
        let gradedBets = bets.filter { bet in
            bet.player?.id == player.id &&
            (bet.gradeResult == .win || bet.gradeResult == .loss)
        }

        guard !gradedBets.isEmpty else { return 0 }

        let wins = gradedBets.filter { $0.gradeResult == .win }.count
        return Double(wins) / Double(gradedBets.count)
    }

    // MARK: - Average Bet Size

    /// Average stake of bets placed in last N days.
    static func avgBetSize(player: Player, bets: [Bet], days: Int) -> Decimal {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())!

        let recentBets = bets.filter { bet in
            bet.player?.id == player.id &&
            bet.createdAt >= cutoff
        }

        guard !recentBets.isEmpty else { return .zero }

        let totalStake = recentBets.reduce(Decimal.zero) { $0 + $1.stake }
        return totalStake / Decimal(recentBets.count)
    }
}
