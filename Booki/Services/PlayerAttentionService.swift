import Foundation
import SwiftData

// MARK: - Data Structures

struct DailyPLPoint: Hashable {
    let date: Date
    let cumulativePL: Decimal
}

struct PlayerExposure: Hashable {
    let grossExposure: Decimal
    let pendingBetCount: Int
    let largestPendingBet: Decimal
}

struct PlayerAttentionScore: Hashable {
    let score: Int        // 0-100
    let label: String     // "Low", "Medium", "High"
    let reasonChips: [String]
}

struct PlayerAnalyticsSummary: Hashable {
    let player: Player
    let pas: PlayerAttentionScore
    let exposure: PlayerExposure
    let balanceOwed: Decimal
    let sevenDayPL: Decimal
    let thirtyDayPL: Decimal
    let allTimePL: Decimal
    let avgBetSize30d: Decimal
    let isOverdue: Bool
    let overdueAmount: Decimal
    let winRate: Double

    static func == (lhs: PlayerAnalyticsSummary, rhs: PlayerAnalyticsSummary) -> Bool {
        lhs.player.id == rhs.player.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(player.id)
    }
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

    // MARK: - Total Bookie P/L

    /// Returns aggregate bookie P/L across ALL players. Positive = bookie profited, negative = bookie lost.
    static func totalBookiePL(bets: [Bet]) -> Decimal {
        let gradedBets = bets.filter { bet in
            bet.gradeResult != nil && bet.gradeResult != .push
        }

        return gradedBets.reduce(Decimal.zero) { total, bet in
            switch bet.gradeResult {
            case .win:
                let payout = LiabilityService.calculatePayout(stake: bet.stake, odds: bet.odds)
                return total - payout
            case .loss:
                return total + bet.stake
            default:
                return total
            }
        }
    }

    // MARK: - Daily Cumulative P/L

    /// Computes daily cumulative bookie P/L data points across all players.
    /// Pass days=0 for all-time, or days>0 for the last N days.
    static func dailyCumulativePL(bets: [Bet], days: Int) -> [DailyPLPoint] {
        let cutoff: Date? = days > 0
            ? Calendar.current.date(byAdding: .day, value: -days, to: Date())
            : nil

        let gradedBets = bets.filter { bet in
            bet.gradeResult != nil &&
            bet.gradeResult != .push &&
            (cutoff == nil || bet.createdAt >= cutoff!)
        }

        guard !gradedBets.isEmpty else { return [] }

        // Group by calendar day
        var dailyPL: [String: Decimal] = [:]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        for bet in gradedBets {
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

        // Sort days ascending, compute running cumulative sum
        let sortedDays = dailyPL.keys.sorted()
        var cumulative: Decimal = .zero
        var points: [DailyPLPoint] = []

        for dayKey in sortedDays {
            cumulative += dailyPL[dayKey]!
            if let date = formatter.date(from: dayKey) {
                points.append(DailyPLPoint(date: date, cumulativePL: cumulative))
            }
        }

        return points
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

        // Payments and credits (negative adjustments) reset the overdue clock
        let creditEntries = playerEntries.filter { $0.type == .paymentLogged || $0.amount < 0 }
        let cutoff = Calendar.current.date(byAdding: .day, value: -thresholdDays, to: Date())!
        let hasRecentPayment = creditEntries.contains { $0.createdAt >= cutoff }

        if hasRecentPayment {
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

    // MARK: - Player Attention Score

    /// Calculates PAS (0-100) using weighted factors: exposure, 7d P/L, largest bet, overdue amount, volatility.
    static func calculatePAS(player: Player, bets: [Bet], ledgerEntries: [LedgerEntry]) -> PlayerAttentionScore {
        let exposure = calculateExposure(player: player, bets: bets)
        let sevenDayPL = realizedPL(player: player, bets: bets, days: 7)
        let vol = volatility(player: player, bets: bets)
        let (overdue, overdueAmt) = isOverdue(player: player, ledgerEntries: ledgerEntries)
        let avgBet = avgBetSize(player: player, bets: bets, days: 30)

        // Normalize each factor 0-1, clamped
        let a = min(NSDecimalNumber(decimal: exposure.grossExposure).doubleValue / 5000.0, 1.0)
        let b = min(abs(NSDecimalNumber(decimal: sevenDayPL).doubleValue) / 2000.0, 1.0)
        let c = min(NSDecimalNumber(decimal: exposure.largestPendingBet).doubleValue / 1000.0, 1.0)
        let d = min(NSDecimalNumber(decimal: overdueAmt).doubleValue / 2000.0, 1.0)
        let e = min(NSDecimalNumber(decimal: vol).doubleValue / 1000.0, 1.0)

        let raw = 100.0 * (0.35 * a + 0.20 * b + 0.15 * c + 0.20 * d + 0.10 * e)
        let score = min(max(Int(raw.rounded()), 0), 100)

        let label: String
        if score >= 67 {
            label = "High"
        } else if score >= 34 {
            label = "Medium"
        } else {
            label = "Low"
        }

        // Generate reason chips from top contributing factors
        var chips: [(String, Double)] = []

        if exposure.grossExposure > 0 {
            chips.append(("Picks Pending", a))
        }
        if overdue {
            chips.append(("Overdue", d))
        }
        if NSDecimalNumber(decimal: sevenDayPL).doubleValue < -200 {
            chips.append(("On Heater", b))  // Player winning = heater
        }
        if NSDecimalNumber(decimal: sevenDayPL).doubleValue > 200 {
            chips.append(("Cold Streak", b))  // Player losing = cold streak from player perspective
        }
        if e > 0.5 {
            chips.append(("Degen", e))
        }
        if NSDecimalNumber(decimal: avgBet).doubleValue > 200 {
            chips.append(("Whale", 0.8))
        }

        // Parlay heavy: >50% of last 30d bets are parlays
        let cutoff30d = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let recentBets = bets.filter { $0.player?.id == player.id && $0.createdAt >= cutoff30d }
        if !recentBets.isEmpty {
            let parlayCount = recentBets.filter(\.isParlay).count
            if Double(parlayCount) / Double(recentBets.count) > 0.5 {
                chips.append(("Parlay Demon", 0.7))
            }
        }

        // Sort by contribution descending, take top 3
        let topChips = chips.sorted { $0.1 > $1.1 }.prefix(3).map(\.0)

        return PlayerAttentionScore(score: score, label: label, reasonChips: Array(topChips))
    }

    // MARK: - Generate Summaries

    /// Computes analytics summaries for all players, sorted by PAS descending.
    static func generateSummaries(players: [Player], bets: [Bet], ledgerEntries: [LedgerEntry]) -> [PlayerAnalyticsSummary] {
        let summaries = players.map { player -> PlayerAnalyticsSummary in
            let pas = calculatePAS(player: player, bets: bets, ledgerEntries: ledgerEntries)
            let exposure = calculateExposure(player: player, bets: bets)
            let playerEntries = ledgerEntries.filter { $0.player?.id == player.id }
            let balance = BalanceService.balanceOwed(from: playerEntries)
            let sevenDayPL = realizedPL(player: player, bets: bets, days: 7)
            let thirtyDayPL = realizedPL(player: player, bets: bets, days: 30)
            let allTimePL = realizedPL(player: player, bets: bets, days: 0)
            let avgBet = avgBetSize(player: player, bets: bets, days: 30)
            let (overdue, overdueAmt) = isOverdue(player: player, ledgerEntries: ledgerEntries)
            let wr = winRate(player: player, bets: bets)

            return PlayerAnalyticsSummary(
                player: player,
                pas: pas,
                exposure: exposure,
                balanceOwed: balance,
                sevenDayPL: sevenDayPL,
                thirtyDayPL: thirtyDayPL,
                allTimePL: allTimePL,
                avgBetSize30d: avgBet,
                isOverdue: overdue,
                overdueAmount: overdueAmt,
                winRate: wr
            )
        }

        return summaries.sorted { $0.pas.score > $1.pas.score }
    }
}
