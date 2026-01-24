import Foundation

/// Errors that can occur during grading operations
enum GradingServiceError: Error, Equatable {
    case invalidBetStatus(current: BetStatus, expected: BetStatus)
    case betNotGraded
    case playerRequired
    case alreadySettled
    case notSettled
    case noSettlementEntryFound
    case parlayRequiresGroupSettlement
    case parlayNotFullyGraded(gradedCount: Int, totalCount: Int)
    case parlayLegsNotFound
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

    /// Voids a bet, transitioning from accepted to void status
    /// Voided bets are excluded from parlay calculations based on policy
    /// - Parameter bet: The bet to void
    /// - Returns: Result with success or GradingServiceError
    static func voidBet(_ bet: Bet) -> Result<Void, GradingServiceError> {
        guard bet.status == .accepted else {
            return .failure(.invalidBetStatus(current: bet.status, expected: .accepted))
        }

        bet.status = .void
        // Note: gradeResult remains nil for voided bets - void is a status, not a grade
        return .success(())
    }

    // MARK: - Settlement

    /// Settles a graded bet by creating the appropriate ledger entry
    /// - Parameter bet: The bet to settle (must be graded with a result)
    /// - Returns: Result with the created LedgerEntry on success, or GradingServiceError on failure
    /// - Note: For parlay bets, use `settleParlayBets` instead which handles all legs together
    static func settleBet(_ bet: Bet) -> Result<LedgerEntry, GradingServiceError> {
        // For parlay bets, require group settlement
        if bet.isParlay {
            return .failure(.parlayRequiresGroupSettlement)
        }

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

    /// Settles a parlay bet by creating a single ledger entry for the combined outcome
    /// - Parameters:
    ///   - parlayBets: All bets (legs) in the parlay (must share the same ticketId)
    ///   - policy: The parlay push/void policy to apply
    /// - Returns: Result with the created LedgerEntry on success, or GradingServiceError on failure
    static func settleParlayBets(_ parlayBets: [Bet], policy: ParlayPushVoidPolicy) -> Result<LedgerEntry, GradingServiceError> {
        guard !parlayBets.isEmpty else {
            return .failure(.parlayLegsNotFound)
        }

        guard let firstBet = parlayBets.first,
              let player = firstBet.player else {
            return .failure(.playerRequired)
        }

        let totalLegs = parlayBets.count

        // Check if already settled
        if parlayBets.allSatisfy({ $0.status == .settled }) {
            return .failure(.alreadySettled)
        }

        // Check if all legs are graded (gradeResult != nil or status == .void)
        let ungradedLegs = parlayBets.filter { bet in
            bet.gradeResult == nil && bet.status != .void
        }

        if !ungradedLegs.isEmpty {
            let gradedCount = totalLegs - ungradedLegs.count
            return .failure(.parlayNotFullyGraded(gradedCount: gradedCount, totalCount: totalLegs))
        }

        // Calculate parlay outcome using ParlayGradingService
        let outcome = ParlayGradingService.calculateParlayOutcome(bets: parlayBets, policy: policy)

        // Calculate settlement amount and description based on outcome
        let (amount, description) = calculateParlaySettlement(
            stake: firstBet.stake,
            outcome: outcome,
            totalLegs: totalLegs
        )

        // Create single ledger entry for the parlay
        // Link to first bet as representative (for display/tracking purposes)
        let ledgerEntry = LedgerEntry(
            amount: amount,
            type: .settlement,
            entryDescription: description,
            player: player,
            bet: firstBet
        )

        // Mark all parlay legs as settled
        for bet in parlayBets {
            bet.status = .settled
        }

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

    /// Calculates the settlement amount and description for a parlay based on combined outcome
    /// - Parameters:
    ///   - stake: The stake amount for the parlay
    ///   - outcome: The calculated parlay outcome from ParlayGradingService
    ///   - totalLegs: Total number of legs in the parlay
    /// - Returns: Tuple of (amount, description) for the ledger entry
    private static func calculateParlaySettlement(stake: Decimal, outcome: ParlayOutcome, totalLegs: Int) -> (Decimal, String) {
        switch outcome {
        case .win(let payout):
            // Win: positive entry for payout amount (profit the player receives)
            return (payout, "Parlay (\(totalLegs) legs) - Win: +\(formatDecimal(payout))")

        case .loss:
            // Loss: negative entry for stake amount (player loses their stake)
            return (-stake, "Parlay (\(totalLegs) legs) - Loss: -\(formatDecimal(stake))")

        case .push:
            // Push: zero-sum entry (stake returned, no profit/loss)
            return (Decimal.zero, "Parlay (\(totalLegs) legs) - Push: stake returned")

        case .pending, .partiallyGraded:
            // Should not reach here - settlement requires all legs graded
            return (Decimal.zero, "Parlay (\(totalLegs) legs) - Incomplete")
        }
    }

    /// Formats a decimal for currency display in descriptions
    private static func formatDecimal(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }

    /// Formats American odds for display in descriptions
    private static func formatOdds(_ odds: Int) -> String {
        if odds >= 0 {
            return "+\(odds)"
        }
        return "\(odds)"
    }
}
