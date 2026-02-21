import Foundation

/// Service for calculating player balances derived from the append-only ledger
/// No stored balance field - always derived from ledger entries
enum BalanceService {

    /// Calculates the balance by summing all ledger entries for a player
    /// Internal convention: positive = player owes bookie, negative = bookie owes player
    /// Note: For user-facing display, negate this value so positive = player credit
    /// - Parameter ledgerEntries: All ledger entries for the player
    /// - Returns: The net balance from all ledger entries
    static func calculateBalance(from ledgerEntries: [LedgerEntry]) -> Decimal {
        return ledgerEntries.reduce(Decimal.zero) { total, entry in
            total + entry.amount
        }
    }

    /// Calculates the current balance for a player
    /// Internal convention: positive = player owes bookie, negative = bookie owes player
    /// - Parameter ledgerEntries: All ledger entries for the player
    /// - Returns: The balance (negate for display purposes)
    static func balanceOwed(from ledgerEntries: [LedgerEntry]) -> Decimal {
        return calculateBalance(from: ledgerEntries)
    }

    /// Calculates the open liability for a player's active bets (bookie-facing)
    /// Open liability = sum of potential payouts for pending and accepted bets
    /// - Parameter bets: All bets for the player
    /// - Returns: Total potential payout the bookie would owe if all active bets win
    static func openLiability(from bets: [Bet]) -> Decimal {
        return LiabilityService.calculateActiveLiability(for: bets)
    }

    /// Calculates the total stakes at risk for a player's active bets (credit calculation)
    /// Open stakes = sum of stakes for pending and accepted bets
    /// - Parameter bets: All bets for the player
    /// - Returns: Total stakes committed on open bets
    static func openStakes(from bets: [Bet]) -> Decimal {
        let activeBets = bets.filter { $0.status == .pending || $0.status == .accepted }
        return activeBets.reduce(Decimal.zero) { total, bet in
            total + bet.stake
        }
    }

    /// Calculates the available credit for a player
    /// Available credit = creditLimit - openStakes - balanceOwed
    /// This represents how much more the player can bet
    /// - Parameters:
    ///   - creditLimit: The player's credit limit
    ///   - bets: All bets for the player (used to calculate open stakes)
    ///   - ledgerEntries: All ledger entries for the player (used to calculate balance owed)
    /// - Returns: The available credit amount (may be negative if over limit)
    static func availableCredit(
        creditLimit: Decimal,
        bets: [Bet],
        ledgerEntries: [LedgerEntry]
    ) -> Decimal {
        let stakes = openStakes(from: bets)
        let owed = balanceOwed(from: ledgerEntries)
        return creditLimit - stakes - owed
    }

    /// Convenience method to calculate available credit for a player
    /// - Parameters:
    ///   - player: The player to calculate available credit for
    ///   - bets: All bets for the player
    ///   - ledgerEntries: All ledger entries for the player
    /// - Returns: The available credit amount
    static func availableCredit(
        for player: Player,
        bets: [Bet],
        ledgerEntries: [LedgerEntry]
    ) -> Decimal {
        return availableCredit(
            creditLimit: player.creditLimit,
            bets: bets,
            ledgerEntries: ledgerEntries
        )
    }

    /// Calculates a summary of a player's financial state
    /// - Parameters:
    ///   - player: The player to summarize
    ///   - bets: All bets for the player
    ///   - ledgerEntries: All ledger entries for the player
    /// - Returns: A summary containing all balance-related values
    static func playerSummary(
        for player: Player,
        bets: [Bet],
        ledgerEntries: [LedgerEntry]
    ) -> PlayerBalanceSummary {
        let stakes = openStakes(from: bets)
        let liability = openLiability(from: bets)
        let owed = balanceOwed(from: ledgerEntries)
        let available = player.creditLimit - stakes - owed

        return PlayerBalanceSummary(
            creditLimit: player.creditLimit,
            openStakes: stakes,
            openLiability: liability,
            balanceOwed: owed,
            availableCredit: available
        )
    }
}

/// Summary of a player's financial state
struct PlayerBalanceSummary {
    /// The player's credit limit
    let creditLimit: Decimal
    /// Total stakes committed on open bets (used for credit calculation)
    let openStakes: Decimal
    /// Total potential payouts from active bets (bookie-facing exposure)
    let openLiability: Decimal
    /// Net balance from all ledger entries (internal: positive = player owes, negate for display)
    let balanceOwed: Decimal
    /// How much more the player can bet
    let availableCredit: Decimal
}
