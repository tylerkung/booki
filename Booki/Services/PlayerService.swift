import Foundation

/// Errors that can occur during player operations
enum PlayerServiceError: Error, Equatable {
    case playerNotFound
    case cannotArchiveWithOpenBets
    case cannotBanWithOpenBets
    case invalidStatusTransition(current: PlayerStatus, target: PlayerStatus)
}

/// Service for player management operations including CRUD and status changes
enum PlayerService {

    // MARK: - Player Creation

    /// Adds a new player to a bookie's book
    /// - Parameters:
    ///   - name: The player's name (required)
    ///   - email: The player's email (optional)
    ///   - creditLimit: The player's credit limit (defaults to 0)
    ///   - bookie: The bookie this player belongs to (optional)
    ///   - username: The player's username for authentication (optional)
    /// - Returns: The newly created Player
    static func addPlayer(
        name: String,
        email: String? = nil,
        creditLimit: Decimal = 0,
        bookie: Bookie? = nil,
        username: String? = nil
    ) -> Player {
        return Player(
            name: name,
            email: email,
            creditLimit: creditLimit,
            status: .active,
            bookie: bookie,
            username: username
        )
    }

    // MARK: - Player Status Changes

    /// Archives a player, keeping their history but excluding them from active counts
    /// Archived players retain their bet history and ledger entries
    /// - Parameter player: The player to archive
    /// - Returns: Result with success or PlayerServiceError
    static func archivePlayer(_ player: Player) -> Result<Void, PlayerServiceError> {
        guard player.status != .archived else {
            return .failure(.invalidStatusTransition(current: player.status, target: .archived))
        }

        player.status = .archived
        player.updatedAt = Date()
        return .success(())
    }

    /// Bans a player, preventing them from submitting new bets
    /// Banned players cannot place new bets but retain their history
    /// - Parameter player: The player to ban
    /// - Returns: Result with success or PlayerServiceError
    static func banPlayer(_ player: Player) -> Result<Void, PlayerServiceError> {
        guard player.status != .banned else {
            return .failure(.invalidStatusTransition(current: player.status, target: .banned))
        }

        player.status = .banned
        player.updatedAt = Date()
        return .success(())
    }

    /// Reactivates an archived or banned player
    /// - Parameter player: The player to reactivate
    /// - Returns: Result with success or PlayerServiceError
    static func reactivatePlayer(_ player: Player) -> Result<Void, PlayerServiceError> {
        guard player.status != .active else {
            return .failure(.invalidStatusTransition(current: player.status, target: .active))
        }

        player.status = .active
        player.updatedAt = Date()
        return .success(())
    }

    // MARK: - Balance Operations

    /// Creates a balance adjustment ledger entry for a player
    /// Used for manual adjustments like bonuses, corrections, or payment logging
    /// - Parameters:
    ///   - player: The player to adjust
    ///   - amount: The adjustment amount (positive adds credit, negative deducts)
    ///   - description: Description of the adjustment reason
    /// - Returns: The created LedgerEntry
    static func adjustBalance(
        for player: Player,
        amount: Decimal,
        description: String
    ) -> LedgerEntry {
        return LedgerEntry(
            amount: amount,
            type: .adjustment,
            entryDescription: description,
            player: player
        )
    }

    /// Logs a payment for a player (creates a ledger entry)
    /// Used when a player pays their balance or receives a payout
    /// - Parameters:
    ///   - player: The player making/receiving payment
    ///   - amount: The payment amount (positive = player paid bookie, negative = bookie paid player)
    ///   - description: Description of the payment
    /// - Returns: The created LedgerEntry
    static func logPayment(
        for player: Player,
        amount: Decimal,
        description: String
    ) -> LedgerEntry {
        return LedgerEntry(
            amount: amount,
            type: .paymentLogged,
            entryDescription: description,
            player: player
        )
    }

    // MARK: - Query Helpers

    /// Filters a list of players to only active players
    /// Excludes archived and banned players
    /// - Parameter players: Array of players to filter
    /// - Returns: Array of active players only
    static func activePlayers(from players: [Player]) -> [Player] {
        return players.filter { $0.status == .active }
    }

    /// Checks if a player can submit bets
    /// Only active players can submit new bets
    /// - Parameter player: The player to check
    /// - Returns: True if the player can submit bets
    static func canSubmitBets(_ player: Player) -> Bool {
        return player.status == .active
    }

    /// Updates a player's credit limit
    /// - Parameters:
    ///   - player: The player to update
    ///   - newLimit: The new credit limit value
    static func updateCreditLimit(for player: Player, newLimit: Decimal) {
        player.creditLimit = newLimit
        player.updatedAt = Date()
    }

    /// Updates a player's basic information
    /// - Parameters:
    ///   - player: The player to update
    ///   - name: New name (optional, nil means no change)
    ///   - email: New email (optional, nil means no change)
    static func updatePlayer(
        _ player: Player,
        name: String? = nil,
        email: String? = nil
    ) {
        if let name = name {
            player.name = name
        }
        if let email = email {
            player.email = email
        }
        player.updatedAt = Date()
    }
}
