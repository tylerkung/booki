import Foundation

/// Outcome of grading a parlay bet
enum ParlayOutcome: Equatable {
    /// All legs pending, no grades yet
    case pending
    /// All legs won - includes calculated payout (profit only, not including stake)
    case win(payout: Decimal)
    /// At least one leg lost - parlay loses
    case loss
    /// Parlay results in a push (stake returned)
    case push
    /// Some legs graded, others still pending
    case partiallyGraded(gradedCount: Int, totalCount: Int)
}

/// Service for calculating parlay outcomes based on leg results
enum ParlayGradingService {

    // MARK: - Parlay Outcome Calculation

    /// Calculates the outcome of a parlay based on all leg results and the push/void policy
    /// - Parameters:
    ///   - bets: All bets (legs) in the parlay (should share the same ticketId)
    ///   - policy: The policy for handling pushed or voided legs
    /// - Returns: The calculated parlay outcome
    static func calculateParlayOutcome(bets: [Bet], policy: ParlayPushVoidPolicy) -> ParlayOutcome {
        guard !bets.isEmpty else {
            return .pending
        }

        let totalCount = bets.count

        // Categorize legs by their grade status
        var winCount = 0
        var lossCount = 0
        var pushCount = 0
        var voidCount = 0
        var pendingCount = 0

        for bet in bets {
            // Check for void status first (status-based, not gradeResult)
            if bet.status == .void {
                voidCount += 1
                continue
            }

            // Check grade result
            guard let result = bet.gradeResult else {
                pendingCount += 1
                continue
            }

            switch result {
            case .win:
                winCount += 1
            case .loss:
                lossCount += 1
            case .push:
                pushCount += 1
            }
        }

        let gradedCount = winCount + lossCount + pushCount + voidCount
        let pushVoidCount = pushCount + voidCount

        // If any leg lost, the entire parlay loses
        if lossCount > 0 {
            return .loss
        }

        // If there are still pending legs, return appropriate status
        if pendingCount > 0 {
            if gradedCount == 0 {
                return .pending
            }
            return .partiallyGraded(gradedCount: gradedCount, totalCount: totalCount)
        }

        // All legs are graded at this point (no pending, no losses)
        // Handle push/void legs based on policy

        if pushVoidCount > 0 {
            switch policy {
            case .treatAsPush:
                // Any push or void means entire parlay is a push
                return .push

            case .reduceLegReprice:
                // Remove pushed/voided legs and calculate with remaining
                let validLegs = bets.filter { bet in
                    bet.status != .void && bet.gradeResult != .push
                }

                // If no valid legs remain, it's a push (return stake)
                if validLegs.isEmpty {
                    return .push
                }

                // All remaining legs are wins, calculate payout
                let stake = bets.first?.stake ?? Decimal.zero
                let payout = calculateParlayPayout(stake: stake, bets: validLegs, excludeVoidPush: false)
                return .win(payout: payout)
            }
        }

        // All legs won with no pushes/voids
        let stake = bets.first?.stake ?? Decimal.zero
        let payout = calculateParlayPayout(stake: stake, bets: bets, excludeVoidPush: false)
        return .win(payout: payout)
    }

    // MARK: - Payout Calculation

    /// Calculates the parlay payout using American odds multiplication
    /// - Parameters:
    ///   - stake: The total stake amount for the parlay
    ///   - bets: The bets (legs) to include in the calculation
    ///   - excludeVoidPush: If true, excludes legs with push grade or void status
    /// - Returns: The profit amount (payout minus stake)
    static func calculateParlayPayout(stake: Decimal, bets: [Bet], excludeVoidPush: Bool) -> Decimal {
        let legsToInclude: [Bet]

        if excludeVoidPush {
            legsToInclude = bets.filter { bet in
                bet.status != .void && bet.gradeResult != .push
            }
        } else {
            legsToInclude = bets
        }

        // If no valid legs remain, return 0 (stake returned separately)
        guard !legsToInclude.isEmpty else {
            return Decimal.zero
        }

        // Calculate combined multiplier by multiplying all decimal odds
        var combinedMultiplier = Decimal(1)
        for bet in legsToInclude {
            let decimalOdds = americanToDecimal(odds: bet.odds)
            combinedMultiplier *= decimalOdds
        }

        // Calculate profit: stake × combinedMultiplier - stake
        let totalPayout = stake * combinedMultiplier
        let profit = totalPayout - stake

        return profit
    }

    // MARK: - Odds Conversion

    /// Converts American odds to decimal odds format
    /// - Parameter odds: American odds (positive like +150 or negative like -110)
    /// - Returns: Decimal odds (e.g., +150 → 2.5, -110 → 1.909...)
    static func americanToDecimal(odds: Int) -> Decimal {
        if odds >= 0 {
            // Positive odds: 1 + odds/100
            // e.g., +150 → 1 + 150/100 = 2.5
            return Decimal(1) + Decimal(odds) / Decimal(100)
        } else {
            // Negative odds: 1 + 100/|odds|
            // e.g., -110 → 1 + 100/110 = 1.909...
            return Decimal(1) + Decimal(100) / Decimal(abs(odds))
        }
    }
}
