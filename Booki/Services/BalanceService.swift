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

    /// Calculates the open liability for a player's active bets
    /// Open liability = sum of potential payouts for pending and accepted bets
    /// - Parameter bets: All bets for the player
    /// - Returns: Total potential payout the bookie would owe if all active bets win
    static func openLiability(from bets: [Bet]) -> Decimal {
        return LiabilityService.calculateActiveLiability(for: bets)
    }

    /// Calculates the available credit for a player
    /// Available credit = creditLimit - openLiability - balanceOwed
    /// This represents how much more the player can bet
    /// - Parameters:
    ///   - creditLimit: The player's credit limit
    ///   - bets: All bets for the player (used to calculate open liability)
    ///   - ledgerEntries: All ledger entries for the player (used to calculate balance owed)
    /// - Returns: The available credit amount (may be negative if over limit)
    static func availableCredit(
        creditLimit: Decimal,
        bets: [Bet],
        ledgerEntries: [LedgerEntry]
    ) -> Decimal {
        let liability = openLiability(from: bets)
        let owed = balanceOwed(from: ledgerEntries)
        return creditLimit - liability - owed
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
        let liability = openLiability(from: bets)
        let owed = balanceOwed(from: ledgerEntries)
        let available = player.creditLimit - liability - owed

        return PlayerBalanceSummary(
            creditLimit: player.creditLimit,
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
    /// Total potential payout from active bets
    let openLiability: Decimal
    /// Net balance from all ledger entries (internal: positive = player owes, negate for display)
    let balanceOwed: Decimal
    /// How much more the player can bet
    let availableCredit: Decimal
}
