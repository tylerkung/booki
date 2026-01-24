import Foundation

/// Report summarizing a player's settlement data for a specific period
struct PlayerSettlementReport {
    /// The player this report is for
    let player: Player
    /// Balance at the start of the period (sum of ledger entries before periodStart)
    let startingBalance: Decimal
    /// Net results from bet settlements within the period
    let netBetResults: Decimal
    /// Payments received within the period
    let paymentsReceived: Decimal
    /// Adjustments made within the period
    let adjustments: Decimal
    /// Ending balance = startingBalance + netBetResults - paymentsReceived + adjustments
    let endingBalance: Decimal
    /// Number of bets settled in this period
    let betsSettledCount: Int
    /// Number of bets won in this period
    let betsWonCount: Int
    /// Number of bets lost in this period
    let betsLostCount: Int
}

/// Service for calculating settlement report data
/// Note: positive balance means player owes bookie (internal convention)
enum SettlementService {

    /// Calculates a settlement report for a player within a specific time period
    /// - Parameters:
    ///   - player: The player to generate the report for
    ///   - periodStart: Start date of the settlement period (inclusive)
    ///   - periodEnd: End date of the settlement period (inclusive)
    ///   - bets: All bets for the player (will be filtered to period)
    ///   - ledgerEntries: All ledger entries for the player (will be filtered/summed)
    /// - Returns: A PlayerSettlementReport with all calculated values
    static func calculatePlayerReport(
        player: Player,
        periodStart: Date,
        periodEnd: Date,
        bets: [Bet],
        ledgerEntries: [LedgerEntry]
    ) -> PlayerSettlementReport {
        // Filter ledger entries for this player
        let playerEntries = ledgerEntries.filter { $0.player?.id == player.id }

        // Starting balance = sum of all ledger entries BEFORE periodStart
        let startingBalance = playerEntries
            .filter { $0.createdAt < periodStart }
            .reduce(Decimal.zero) { $0 + $1.amount }

        // Entries within the period
        let periodEntries = playerEntries.filter {
            $0.createdAt >= periodStart && $0.createdAt <= periodEnd
        }

        // Net bet results = sum of settlement entries within period
        let netBetResults = periodEntries
            .filter { $0.type == .settlement }
            .reduce(Decimal.zero) { $0 + $1.amount }

        // Payments received = sum of payment entries within period
        // Note: payments are logged as negative amounts (reduce what player owes)
        // So we negate to get a positive "received" value
        let paymentsReceived = -periodEntries
            .filter { $0.type == .paymentLogged }
            .reduce(Decimal.zero) { $0 + $1.amount }

        // Adjustments = sum of adjustment and reversal entries within period
        let adjustments = periodEntries
            .filter { $0.type == .adjustment || $0.type == .reversal }
            .reduce(Decimal.zero) { $0 + $1.amount }

        // Ending balance = startingBalance + netBetResults - paymentsReceived + adjustments
        let endingBalance = startingBalance + netBetResults - paymentsReceived + adjustments

        // Filter bets for this player within the period
        let playerBets = bets.filter { $0.player?.id == player.id }
        let periodBets = playerBets.filter {
            $0.status == .settled && $0.createdAt >= periodStart && $0.createdAt <= periodEnd
        }

        let betsSettledCount = periodBets.count
        let betsWonCount = periodBets.filter { $0.gradeResult == .win }.count
        let betsLostCount = periodBets.filter { $0.gradeResult == .loss }.count

        return PlayerSettlementReport(
            player: player,
            startingBalance: startingBalance,
            netBetResults: netBetResults,
            paymentsReceived: paymentsReceived,
            adjustments: adjustments,
            endingBalance: endingBalance,
            betsSettledCount: betsSettledCount,
            betsWonCount: betsWonCount,
            betsLostCount: betsLostCount
        )
    }
}
