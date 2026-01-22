import Foundation

/// Service for calculating bet liability based on American odds
/// Liability = potential payout amount the bookie would owe if the bet wins
enum LiabilityService {

    /// Calculates the potential payout for a bet based on American odds
    /// - Parameters:
    ///   - stake: The amount wagered
    ///   - odds: American odds (e.g., -110, +150)
    /// - Returns: The potential payout (profit only, not including stake return)
    static func calculatePayout(stake: Decimal, odds: Int) -> Decimal {
        if odds < 0 {
            // Negative odds: payout = stake * (100 / abs(odds))
            // e.g., -110 odds: $110 bet wins $100
            return stake * (Decimal(100) / Decimal(abs(odds)))
        } else {
            // Positive odds: payout = stake * (odds / 100)
            // e.g., +150 odds: $100 bet wins $150
            return stake * (Decimal(odds) / Decimal(100))
        }
    }

    /// Calculates the total liability (potential payout) for a single bet
    /// - Parameter bet: The bet to calculate liability for
    /// - Returns: The potential payout amount
    static func calculateLiability(for bet: Bet) -> Decimal {
        return calculatePayout(stake: bet.stake, odds: bet.odds)
    }

    /// Calculates the total liability for a collection of bets
    /// - Parameter bets: Array of bets to calculate total liability for
    /// - Returns: Sum of all potential payouts
    static func calculateTotalLiability(for bets: [Bet]) -> Decimal {
        return bets.reduce(Decimal.zero) { total, bet in
            total + calculateLiability(for: bet)
        }
    }

    /// Filters bets to only include those that contribute to active liability
    /// (pending and accepted bets only)
    /// - Parameter bets: Array of bets to filter
    /// - Returns: Filtered array containing only pending and accepted bets
    static func activeBets(from bets: [Bet]) -> [Bet] {
        return bets.filter { bet in
            bet.status == .pending || bet.status == .accepted
        }
    }

    /// Calculates total liability for only active bets (pending and accepted)
    /// - Parameter bets: Array of bets to calculate liability for
    /// - Returns: Sum of potential payouts for active bets only
    static func calculateActiveLiability(for bets: [Bet]) -> Decimal {
        return calculateTotalLiability(for: activeBets(from: bets))
    }
}
