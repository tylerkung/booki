import Foundation

/// Errors that can occur during bet operations
enum BetServiceError: Error {
    case insufficientCredit(available: Decimal, required: Decimal)
    case invalidBetStatus(current: BetStatus, expected: BetStatus)
    case playerNotActive(status: PlayerStatus)
    case betNotFound
    case playerRequired
    case eventLocked
    case edgeFunctionError(String)
}

extension BetServiceError: Equatable {
    static func == (lhs: BetServiceError, rhs: BetServiceError) -> Bool {
        switch (lhs, rhs) {
        case (.insufficientCredit(let a1, let r1), .insufficientCredit(let a2, let r2)):
            return a1 == a2 && r1 == r2
        case (.invalidBetStatus(let c1, let e1), .invalidBetStatus(let c2, let e2)):
            return c1 == c2 && e1 == e2
        case (.playerNotActive(let s1), .playerNotActive(let s2)):
            return s1 == s2
        case (.betNotFound, .betNotFound):
            return true
        case (.playerRequired, .playerRequired):
            return true
        case (.eventLocked, .eventLocked):
            return true
        case (.edgeFunctionError(let m1), .edgeFunctionError(let m2)):
            return m1 == m2
        default:
            return false
        }
    }
}

// MARK: - Edge Function Types

/// Request body for submit_bet Edge Function
struct SubmitBetRequest: Encodable {
    let eventId: String
    let marketId: String
    let side: String
    let odds: Int
    let stake: String
    let playerId: String
    let bookieId: String
    let idempotencyKey: String

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case marketId = "market_id"
        case side
        case odds
        case stake
        case playerId = "player_id"
        case bookieId = "bookie_id"
        case idempotencyKey = "idempotency_key"
    }
}

/// Bet record returned from submit_bet Edge Function
struct SubmitBetResponseBet: Decodable {
    let id: String
    let bookieId: String
    let playerId: String
    let eventId: String
    let ticketId: String
    let market: String
    let side: String
    let odds: Int
    let stake: Double
    let status: String
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case bookieId = "bookie_id"
        case playerId = "player_id"
        case eventId = "event_id"
        case ticketId = "ticket_id"
        case market
        case side
        case odds
        case stake
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Response from submit_bet Edge Function
struct SubmitBetResponse: Decodable {
    let success: Bool
    let bet: SubmitBetResponseBet?
    let error: String?
}

// MARK: - Parlay Edge Function Types

/// A single leg in a parlay submission
struct ParlayLeg: Encodable {
    let eventId: String
    let marketId: String
    let side: String
    let sideIndicator: String
    let odds: Int

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case marketId = "market_id"
        case side
        case sideIndicator = "side_indicator"
        case odds
    }
}

/// Request body for submit_parlay Edge Function
struct SubmitParlayRequest: Encodable {
    let legs: [ParlayLeg]
    let stake: String
    let playerId: String
    let bookieId: String
    let combinedOdds: Int
    let idempotencyKey: String

    enum CodingKeys: String, CodingKey {
        case legs
        case stake
        case playerId = "player_id"
        case bookieId = "bookie_id"
        case combinedOdds = "combined_odds"
        case idempotencyKey = "idempotency_key"
    }
}

/// Response from submit_parlay Edge Function
struct SubmitParlayResponse: Decodable {
    let success: Bool
    let bets: [SubmitBetResponseBet]?
    let ticketId: String?
    let error: String?
    let debug: SubmitParlayDebug?

    enum CodingKeys: String, CodingKey {
        case success
        case bets
        case ticketId = "ticket_id"
        case error
        case debug
    }
}

/// Debug info from submit_parlay errors
struct SubmitParlayDebug: Decodable {
    let message: String?
    let details: String?
    let hint: String?
    let code: String?
}

/// Service for bet operations including submission and status transitions
enum BetService {

    // MARK: - Server-Side Bet Submission (Edge Function)

    /// Submits a bet via the submit_bet Edge Function for server-authoritative validation
    /// - Parameters:
    ///   - eventId: The event UUID
    ///   - marketId: The market UUID
    ///   - side: The side selected (e.g., "a", "b", or team name)
    ///   - odds: The American odds at time of submission
    ///   - stake: The amount being wagered
    ///   - playerId: The player's UUID
    ///   - bookieId: The bookie's UUID
    /// - Returns: Result with SubmitBetResponse on success, or Error on failure
    static func submitBetToServer(
        eventId: UUID,
        marketId: UUID,
        side: String,
        odds: Int,
        stake: Decimal,
        playerId: UUID,
        bookieId: UUID
    ) async -> Result<SubmitBetResponse, Error> {
        let idempotencyKey = UUID().uuidString

        let request = SubmitBetRequest(
            eventId: eventId.uuidString,
            marketId: marketId.uuidString,
            side: side,
            odds: odds,
            stake: "\(stake)",
            playerId: playerId.uuidString,
            bookieId: bookieId.uuidString,
            idempotencyKey: idempotencyKey
        )

        do {
            let response: SubmitBetResponse = try await EdgeFunctionService.shared.callFunction(
                name: "submit_bet",
                body: request
            )

            if response.success {
                return .success(response)
            } else {
                let errorMessage = response.error ?? "Unknown error"
                return .failure(BetServiceError.edgeFunctionError(errorMessage))
            }
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Server-Side Parlay Submission (Edge Function)

    /// Submits a parlay bet via the submit_parlay Edge Function for server-authoritative validation
    /// - Parameters:
    ///   - legs: Array of ParlayLeg structs representing each leg of the parlay
    ///   - stake: The total amount being wagered on the parlay
    ///   - playerId: The player's UUID
    ///   - bookieId: The bookie's UUID
    ///   - combinedOdds: The combined American odds for the parlay
    /// - Returns: Result with SubmitParlayResponse on success, or Error on failure
    static func submitParlayToServer(
        legs: [ParlayLeg],
        stake: Decimal,
        playerId: UUID,
        bookieId: UUID,
        combinedOdds: Int
    ) async -> Result<SubmitParlayResponse, Error> {
        let idempotencyKey = UUID().uuidString

        let request = SubmitParlayRequest(
            legs: legs,
            stake: "\(stake)",
            playerId: playerId.uuidString,
            bookieId: bookieId.uuidString,
            combinedOdds: combinedOdds,
            idempotencyKey: idempotencyKey
        )

        do {
            let response: SubmitParlayResponse = try await EdgeFunctionService.shared.callFunction(
                name: "submit_parlay",
                body: request
            )

            if response.success {
                return .success(response)
            } else {
                var errorMessage = response.error ?? "Unknown error"
                if let debug = response.debug {
                    let debugParts = [debug.message, debug.details, debug.hint, debug.code].compactMap { $0 }
                    if !debugParts.isEmpty {
                        errorMessage += " | Debug: \(debugParts.joined(separator: ", "))"
                    }
                }
                return .failure(BetServiceError.edgeFunctionError(errorMessage))
            }
        } catch {
            return .failure(error)
        }
    }

    /// Creates a local Bet model from a SubmitBetResponse
    /// - Parameters:
    ///   - response: The successful response from submit_bet Edge Function
    ///   - player: The Player to associate with the bet
    ///   - localSide: The local side value (actual team name) to store locally
    ///   - localMarket: The local market value to store locally
    /// - Returns: A Bet model populated with server and local data
    static func createLocalBetFromResponse(
        _ response: SubmitBetResponse,
        player: Player,
        localSide: String,
        localMarket: String,
        eventDescription: String? = nil,
        sportLeague: String? = nil,
        sideIndicator: String? = nil,
        marketId: UUID? = nil
    ) -> Bet? {
        guard let betResponse = response.bet,
              let betId = UUID(uuidString: betResponse.id),
              let ticketId = UUID(uuidString: betResponse.ticketId),
              let bookieId = UUID(uuidString: betResponse.bookieId) else {
            return nil
        }

        let status = BetStatus(rawValue: betResponse.status) ?? .pending

        let bet = Bet(
            id: betId,
            eventId: betResponse.eventId,
            market: localMarket,
            side: localSide,
            odds: betResponse.odds,
            stake: Decimal(betResponse.stake),
            status: status,
            gradeResult: nil,
            player: player,
            createdAt: Date(),
            ticketId: ticketId,
            policyViolationReason: nil,
            isParlay: false,
            parlayLegs: 1,
            eventDescription: eventDescription,
            sportLeague: sportLeague,
            sideIndicator: sideIndicator,
            marketId: marketId,
            bookieId: bookieId,
            needsSync: false,
            lastSyncedAt: Date(),
            version: 1
        )

        return bet
    }

    /// Creates local Bet models from a SubmitParlayResponse
    /// - Parameters:
    ///   - response: The successful response from submit_parlay Edge Function
    ///   - player: The Player to associate with the bets
    ///   - items: The BetSlipItems used to submit (for local side/market values)
    /// - Returns: Array of Bet models populated with server and local data
    static func createLocalBetsFromParlayResponse(
        _ response: SubmitParlayResponse,
        player: Player,
        items: [BetSlipItem],
        events: [Event] = []
    ) -> [Bet] {
        guard let bets = response.bets,
              let ticketIdString = response.ticketId,
              let ticketId = UUID(uuidString: ticketIdString) else {
            return []
        }

        let totalLegs = bets.count

        return bets.compactMap { betResponse in
            guard let betId = UUID(uuidString: betResponse.id),
                  let bookieId = UUID(uuidString: betResponse.bookieId) else {
                return nil
            }

            // Match server bet to local item by eventId + side indicator
            let matchingItem = items.first { item in
                item.eventId.uuidString.lowercased() == betResponse.eventId.lowercased()
                    && item.sideIndicator == betResponse.side
            }

            let localSide = matchingItem?.side ?? betResponse.side
            let localMarket = matchingItem?.marketType.rawValue ?? betResponse.market
            let status = BetStatus(rawValue: betResponse.status) ?? .pending

            // Look up event description and sport league
            let eventDesc = matchingItem?.eventDescription
            let league = events.first(where: {
                $0.id.uuidString.lowercased() == betResponse.eventId.lowercased()
            })?.league

            return Bet(
                id: betId,
                eventId: betResponse.eventId,
                market: localMarket,
                side: localSide,
                odds: betResponse.odds,
                stake: Decimal(betResponse.stake),
                status: status,
                gradeResult: nil,
                player: player,
                createdAt: Date(),
                ticketId: ticketId,
                policyViolationReason: nil,
                isParlay: true,
                parlayLegs: totalLegs,
                eventDescription: eventDesc,
                sportLeague: league,
                sideIndicator: matchingItem?.sideIndicator,
                marketId: matchingItem?.marketId,
                bookieId: bookieId,
                needsSync: false,
                lastSyncedAt: Date(),
                version: 1
            )
        }
    }

    // MARK: - Local Bet Submission

    /// Submits a new bet request, creating a pending or accepted bet with snapshotted odds
    /// Validates that the player has sufficient available credit and optionally evaluates acceptance policy
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
    ///   - policy: Optional acceptance policy to evaluate bet against
    ///   - isParlay: Whether this is a parlay bet (default false)
    ///   - parlayLegs: Number of legs in the parlay (default 0 for singles)
    ///   - playerBetCount: Number of bets the player has previously placed (default 0)
    ///   - event: The event being bet on (required if policy is provided)
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
        ticketId: UUID = UUID(),
        policy: AcceptancePolicy? = nil,
        isParlay: Bool = false,
        parlayLegs: Int = 0,
        playerBetCount: Int = 0,
        event: Event? = nil
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

        // Evaluate acceptance policy if provided
        var betStatus: BetStatus = .pending
        var policyViolationReason: String? = nil

        if let policy = policy, let event = event {
            let violations = AcceptancePolicyService.evaluateBet(
                stake: stake,
                isParlay: isParlay,
                parlayLegs: parlayLegs,
                playerBetCount: playerBetCount,
                event: event,
                policy: policy
            )

            // If event is locked, return failure instead of creating bet
            if violations.contains(.eventLocked) {
                return .failure(.eventLocked)
            }

            // If no violations, auto-accept; otherwise queue for review
            if violations.isEmpty {
                betStatus = .accepted
            } else {
                betStatus = .pending
                policyViolationReason = AcceptancePolicyService.combinedViolationDescription(violations)
            }
        }
        // If no policy provided, default to .pending (backwards compatible)

        // Create bet with determined status
        let bet = Bet(
            eventId: eventId,
            market: market,
            side: side,
            odds: odds,
            stake: stake,
            status: betStatus,
            player: player,
            ticketId: ticketId,
            policyViolationReason: policyViolationReason,
            isParlay: isParlay,
            parlayLegs: isParlay ? parlayLegs : 1
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

    // MARK: - Bulk Operations

    /// Voids all pending or accepted bets for a specific event
    /// Used when an event is canceled to void all outstanding bets
    /// - Parameters:
    ///   - eventId: The event ID to void bets for
    ///   - bets: All bets to filter from
    /// - Returns: Number of bets voided
    @discardableResult
    static func voidBetsForEvent(eventId: String, bets: [Bet]) -> Int {
        var voidedCount = 0

        for bet in bets {
            // Only void bets for this event that are pending or accepted
            guard bet.eventId == eventId else { continue }
            guard bet.status == .pending || bet.status == .accepted else { continue }

            bet.status = .void
            voidedCount += 1
        }

        return voidedCount
    }
}
