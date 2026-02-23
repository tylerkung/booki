import Foundation
import SwiftData

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
    case edgeFunctionError(String)

    static func == (lhs: GradingServiceError, rhs: GradingServiceError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidBetStatus(let c1, let e1), .invalidBetStatus(let c2, let e2)):
            return c1 == c2 && e1 == e2
        case (.betNotGraded, .betNotGraded): return true
        case (.playerRequired, .playerRequired): return true
        case (.alreadySettled, .alreadySettled): return true
        case (.notSettled, .notSettled): return true
        case (.noSettlementEntryFound, .noSettlementEntryFound): return true
        case (.parlayRequiresGroupSettlement, .parlayRequiresGroupSettlement): return true
        case (.parlayNotFullyGraded(let g1, let t1), .parlayNotFullyGraded(let g2, let t2)):
            return g1 == g2 && t1 == t2
        case (.parlayLegsNotFound, .parlayLegsNotFound): return true
        case (.edgeFunctionError(let m1), .edgeFunctionError(let m2)):
            return m1 == m2
        default: return false
        }
    }
}

// MARK: - Edge Function Request/Response Types

/// Request body for grade_bet Edge Function
private struct GradeBetRequest: Encodable {
    let bet_id: String
    let outcome: String
    let idempotency_key: String
}

/// Request body for settle_bet Edge Function
private struct SettleBetRequest: Encodable {
    let bet_id: String
    let idempotency_key: String
}

/// Generic success response from grade_bet / settle_bet
private struct EdgeFunctionBetResponse: Decodable {
    let success: Bool
    let bet: EdgeBetData?
    let error: String?
}

/// Response from settle_bet that includes ledger_entry
private struct SettleBetResponse: Decodable {
    let success: Bool
    let bet: EdgeBetData?
    let ledgerEntry: EdgeLedgerData?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success
        case bet
        case ledgerEntry = "ledger_entry"
        case error
    }
}

/// Bet data returned from edge functions
private struct EdgeBetData: Decodable {
    let id: String
    let status: String
    let gradeResult: String?

    enum CodingKeys: String, CodingKey {
        case id
        case status
        case gradeResult = "grade_result"
    }
}

/// Ledger entry data returned from settle_bet
private struct EdgeLedgerData: Decodable {
    let id: String
    let amount: Double
    let type: String
    let description: String
    let playerId: String
    let betId: String
    let bookieId: String

    enum CodingKeys: String, CodingKey {
        case id
        case amount
        case type
        case description
        case playerId = "player_id"
        case betId = "bet_id"
        case bookieId = "bookie_id"
    }
}

/// Service for grading and settling bets via server-authoritative edge functions
enum GradingService {

    // MARK: - Grading

    /// Grades a bet via the grade_bet edge function, then updates local model
    /// - Parameters:
    ///   - bet: The bet to grade
    ///   - result: The outcome of the bet (win, loss, or push)
    @MainActor static func gradeBet(_ bet: Bet, result: GradeResult) async throws {
        let request = GradeBetRequest(
            bet_id: bet.id.uuidString.lowercased(),
            outcome: result.rawValue,
            idempotency_key: "grade_\(bet.id.uuidString.lowercased())_\(Int(Date().timeIntervalSince1970))"
        )

        let response: EdgeFunctionBetResponse = try await EdgeFunctionService.shared.callFunction(
            name: "grade_bet",
            body: request
        )

        guard response.success else {
            throw GradingServiceError.edgeFunctionError(response.error ?? "Unknown error")
        }

        // Server accepted — update local model
        bet.status = .graded
        bet.gradeResult = result
    }

    /// Voids a bet via the grade_bet edge function with outcome='void'
    /// - Parameter bet: The bet to void
    @MainActor static func voidBet(_ bet: Bet) async throws {
        let request = GradeBetRequest(
            bet_id: bet.id.uuidString.lowercased(),
            outcome: "void",
            idempotency_key: "void_\(bet.id.uuidString.lowercased())_\(Int(Date().timeIntervalSince1970))"
        )

        let response: EdgeFunctionBetResponse = try await EdgeFunctionService.shared.callFunction(
            name: "grade_bet",
            body: request
        )

        guard response.success else {
            throw GradingServiceError.edgeFunctionError(response.error ?? "Unknown error")
        }

        // Server accepted — update local model
        bet.status = .void
    }

    // MARK: - Settlement

    /// Settles a graded bet via the settle_bet edge function
    /// - Parameters:
    ///   - bet: The bet to settle (must be graded with a result)
    ///   - context: The model context to insert the ledger entry into
    @MainActor static func settleBet(_ bet: Bet, in context: ModelContext) async throws {
        let request = SettleBetRequest(
            bet_id: bet.id.uuidString.lowercased(),
            idempotency_key: "settle_\(bet.id.uuidString.lowercased())_\(Int(Date().timeIntervalSince1970))"
        )

        let response: SettleBetResponse = try await EdgeFunctionService.shared.callFunction(
            name: "settle_bet",
            body: request
        )

        guard response.success else {
            throw GradingServiceError.edgeFunctionError(response.error ?? "Unknown error")
        }

        // Server accepted — update local model
        bet.status = .settled

        // Create local LedgerEntry from response data
        if let ledgerData = response.ledgerEntry, let player = bet.player {
            let ledgerEntry = LedgerEntry(
                amount: Decimal(ledgerData.amount),
                type: .settlement,
                entryDescription: ledgerData.description,
                player: player,
                bet: bet
            )
            context.insert(ledgerEntry)
        }
    }

    /// Settles parlay bets by calling settle_bet for each leg sequentially
    /// - Parameters:
    ///   - parlayBets: All bets (legs) in the parlay
    ///   - policy: The parlay push/void policy to apply
    ///   - context: The model context to insert the ledger entry into
    @MainActor static func settleParlayBets(_ parlayBets: [Bet], policy: ParlayPushVoidPolicy, in context: ModelContext) async throws {
        guard !parlayBets.isEmpty else {
            throw GradingServiceError.parlayLegsNotFound
        }

        guard let firstBet = parlayBets.first, let player = firstBet.player else {
            throw GradingServiceError.playerRequired
        }

        // Settle each leg via edge function; the first leg creates the ledger entry
        var ledgerEntryCreated = false
        for bet in parlayBets {
            // Skip already-settled legs
            guard bet.status != .settled else { continue }
            // Skip void legs (no settlement needed)
            guard bet.status != .void else { continue }

            let request = SettleBetRequest(
                bet_id: bet.id.uuidString.lowercased(),
                idempotency_key: "settle_\(bet.id.uuidString.lowercased())_\(Int(Date().timeIntervalSince1970))"
            )

            let response: SettleBetResponse = try await EdgeFunctionService.shared.callFunction(
                name: "settle_bet",
                body: request
            )

            guard response.success else {
                throw GradingServiceError.edgeFunctionError(response.error ?? "Unknown error")
            }

            bet.status = .settled

            // Create local LedgerEntry from first leg's response only
            if !ledgerEntryCreated, let ledgerData = response.ledgerEntry {
                let ledgerEntry = LedgerEntry(
                    amount: Decimal(ledgerData.amount),
                    type: .settlement,
                    entryDescription: ledgerData.description,
                    player: player,
                    bet: bet
                )
                context.insert(ledgerEntry)
                ledgerEntryCreated = true
            }
        }
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
