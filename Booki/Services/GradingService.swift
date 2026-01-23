import Foundation

/// Errors that can occur during grading operations
enum GradingServiceError: Error, Equatable {
    case invalidBetStatus(current: BetStatus, expected: BetStatus)
    case betNotGraded
    case playerRequired
    case alreadySettled
    case notSettled
    case noSettlementEntryFound
}

/// Service for grading and settling bets
enum GradingService {

    // MARK: - Grading

    /// Grades a bet, transitioning from accepted to graded status
    /// - Parameters:
    ///   - bet: The bet to grade
    ///   - result: The outcome of the bet (win, loss, or push)
    /// - Returns: Result with success or GradingServiceError
    static func gradeBet(_ bet: Bet, result: GradeResult) -> Result<Void, GradingServiceError> {
        guard bet.status == .accepted else {
            return .failure(.invalidBetStatus(current: bet.status, expected: .accepted))
        }

        bet.status = .graded
        bet.gradeResult = result
        return .success(())
    }

    // MARK: - Settlement

    /// Settles a graded bet by creating the appropriate ledger entry
    /// - Parameter bet: The bet to settle (must be graded with a result)
    /// - Returns: Result with the created LedgerEntry on success, or GradingServiceError on failure
    static func settleBet(_ bet: Bet) -> Result<LedgerEntry, GradingServiceError> {
        guard bet.status == .graded else {
            if bet.status == .settled {
                return .failure(.alreadySettled)
            }
            return .failure(.invalidBetStatus(current: bet.status, expected: .graded))
        }

        guard let gradeResult = bet.gradeResult else {
            return .failure(.betNotGraded)
        }

        guard let player = bet.player else {
            return .failure(.playerRequired)
        }

        // Calculate settlement amount based on outcome
        let (amount, description) = calculateSettlement(bet: bet, result: gradeResult)

        // Create ledger entry
        let ledgerEntry = LedgerEntry(
            amount: amount,
            type: .settlement,
            entryDescription: description,
            player: player,
            bet: bet
        )

        // Update bet status to settled
        bet.status = .settled

        return .success(ledgerEntry)
    }

    // MARK: - Reversal

    /// Reverses a settled bet by creating a reversal ledger entry
    /// The bet status changes back to 'graded' so it can be re-settled if needed
    /// - Parameters:
    ///   - bet: The bet to reverse (must be settled)
    ///   - ledgerEntries: All ledger entries to find the original settlement
    /// - Returns: Result with the created reversal LedgerEntry on success, or GradingServiceError on failure
    static func reverseBet(_ bet: Bet, ledgerEntries: [LedgerEntry]) -> Result<LedgerEntry, GradingServiceError> {
        guard bet.status == .settled else {
            return .failure(.notSettled)
        }

        guard let player = bet.player else {
            return .failure(.playerRequired)
        }

        // Find the original settlement entry for this bet
        guard let settlementEntry = ledgerEntries.first(where: { entry in
            entry.bet?.id == bet.id && entry.type == .settlement
        }) else {
            return .failure(.noSettlementEntryFound)
        }

        // Create reversal entry that negates the original settlement
        let reversalAmount = -settlementEntry.amount
        let description = "Reversal of: \(settlementEntry.entryDescription)"

        let reversalEntry = LedgerEntry(
            amount: reversalAmount,
            type: .reversal,
            entryDescription: description,
            player: player,
            bet: bet
        )

        // Transition bet back to graded status (can be re-settled)
        bet.status = .graded

        return .success(reversalEntry)
    }

    // MARK: - Private Helpers

    /// Calculates the settlement amount and description based on bet outcome
    /// - Parameters:
    ///   - bet: The bet being settled
    ///   - result: The grade result (win, loss, push)
    /// - Returns: Tuple of (amount, description) for the ledger entry
    private static func calculateSettlement(bet: Bet, result: GradeResult) -> (Decimal, String) {
        switch result {
        case .win:
            // Win: positive entry for payout amount (profit the player receives)
            let payout = LiabilityService.calculatePayout(stake: bet.stake, odds: bet.odds)
            return (payout, "Win settlement: \(bet.side) @ \(formatOdds(bet.odds))")

        case .loss:
            // Loss: negative entry for stake amount (player loses their stake)
            return (-bet.stake, "Loss settlement: \(bet.side) @ \(formatOdds(bet.odds))")

        case .push:
            // Push: zero-sum entry (stake returned, no profit/loss)
            return (Decimal.zero, "Push settlement: \(bet.side) @ \(formatOdds(bet.odds)) - stake returned")
        }
    }

    /// Formats American odds for display in descriptions
    private static func formatOdds(_ odds: Int) -> String {
        if odds >= 0 {
            return "+\(odds)"
        }
        return "\(odds)"
    }
}
