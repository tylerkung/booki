import Foundation

/// Errors that can occur during bet operations
enum BetServiceError: Error, Equatable {
    case insufficientCredit(available: Decimal, required: Decimal)
    case invalidBetStatus(current: BetStatus, expected: BetStatus)
    case playerNotActive(status: PlayerStatus)
    case betNotFound
    case playerRequired
}

/// Service for bet operations including submission and status transitions
enum BetService {

    // MARK: - Bet Submission

    /// Submits a new bet request, creating a pending bet with snapshotted odds
    /// Validates that the player has sufficient available credit
    /// - Parameters:
    ///   - player: The player submitting the bet
    ///   - eventId: The event identifier
    ///   - market: The market type (e.g., "spread", "total", "moneyline")
    ///   - side: The side selected (e.g., team name, over/under)
    ///   - odds: The American odds at time of submission (snapshotted)
    ///   - stake: The amount being wagered
    ///   - existingBets: Player's existing bets (for credit calculation)
    ///   - ledgerEntries: Player's ledger entries (for credit calculation)
    ///   - ticketId: The ticket ID to group bets placed together (defaults to new UUID)
    /// - Returns: Result with the created Bet on success, or BetServiceError on failure
    static func submitBet(
        player: Player,
        eventId: String,
        market: String,
        side: String,
        odds: Int,
        stake: Decimal,
        existingBets: [Bet],
        ledgerEntries: [LedgerEntry],
        ticketId: UUID = UUID()
    ) -> Result<Bet, BetServiceError> {
        // Check player is active
        guard player.status == .active else {
            return .failure(.playerNotActive(status: player.status))
        }

        // Calculate available credit
        let availableCredit = BalanceService.availableCredit(
            for: player,
            bets: existingBets,
            ledgerEntries: ledgerEntries
        )

        // Calculate potential liability for this bet
        let potentialLiability = LiabilityService.calculatePayout(stake: stake, odds: odds)

        // Validate sufficient credit (need credit for potential payout)
        guard availableCredit >= potentialLiability else {
            return .failure(.insufficientCredit(
                available: availableCredit,
                required: potentialLiability
            ))
        }

        // Create pending bet with snapshotted odds
        let bet = Bet(
            eventId: eventId,
            market: market,
            side: side,
            odds: odds,
            stake: stake,
            status: .pending,
            player: player,
            ticketId: ticketId
        )

        return .success(bet)
    }

    // MARK: - Bet Status Transitions

    /// Accepts a pending bet, transitioning it to accepted status
    /// - Parameter bet: The bet to accept
    /// - Returns: Result with success or BetServiceError
    static func acceptBet(_ bet: Bet) -> Result<Void, BetServiceError> {
        guard bet.status == .pending else {
            return .failure(.invalidBetStatus(current: bet.status, expected: .pending))
        }

        bet.status = .accepted
        return .success(())
    }

    /// Declines a pending bet, transitioning it to declined status
    /// - Parameter bet: The bet to decline
    /// - Returns: Result with success or BetServiceError
    static func declineBet(_ bet: Bet) -> Result<Void, BetServiceError> {
        guard bet.status == .pending else {
            return .failure(.invalidBetStatus(current: bet.status, expected: .pending))
        }

        bet.status = .declined
        return .success(())
    }

    /// Voids an accepted bet, transitioning it to void status
    /// - Parameter bet: The bet to void
    /// - Returns: Result with success or BetServiceError
    static func voidBet(_ bet: Bet) -> Result<Void, BetServiceError> {
        guard bet.status == .accepted else {
            return .failure(.invalidBetStatus(current: bet.status, expected: .accepted))
        }

        bet.status = .void
        return .success(())
    }

    // MARK: - Validation Helpers

    /// Validates if a player has sufficient credit for a given stake and odds
    /// - Parameters:
    ///   - player: The player to check
    ///   - stake: The proposed stake amount
    ///   - odds: The odds for the bet
    ///   - existingBets: Player's existing bets
    ///   - ledgerEntries: Player's ledger entries
    /// - Returns: True if player has sufficient credit
    static func hasAvailableCredit(
        player: Player,
        stake: Decimal,
        odds: Int,
        existingBets: [Bet],
        ledgerEntries: [LedgerEntry]
    ) -> Bool {
        let availableCredit = BalanceService.availableCredit(
            for: player,
            bets: existingBets,
            ledgerEntries: ledgerEntries
        )
        let potentialLiability = LiabilityService.calculatePayout(stake: stake, odds: odds)
        return availableCredit >= potentialLiability
    }

    /// Calculates the available credit for a player
    /// Convenience method that delegates to BalanceService
    /// - Parameters:
    ///   - player: The player to check
    ///   - bets: Player's bets
    ///   - ledgerEntries: Player's ledger entries
    /// - Returns: The available credit amount
    static func availableCredit(
        for player: Player,
        bets: [Bet],
        ledgerEntries: [LedgerEntry]
    ) -> Decimal {
        return BalanceService.availableCredit(
            for: player,
            bets: bets,
            ledgerEntries: ledgerEntries
        )
    }
}
