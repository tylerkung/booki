import Foundation
import SwiftData

/// Status for a bet through its lifecycle
enum BetStatus: String, Codable {
    case pending
    case accepted
    case declined
    case readyToGrade
    case graded
    case settled
    case void
}

/// Result of grading a bet
enum GradeResult: String, Codable {
    case win
    case loss
    case push
}

/// Bet model representing a wager placed by a player
@Model
final class Bet {
    @Attribute(.unique) var id: UUID
    var eventId: String
    var market: String
    var side: String
    var odds: Int
    var stake: Decimal
    var status: BetStatus
    var gradeResult: GradeResult?
    var createdAt: Date

    /// Ticket ID to group bets placed together in the same submission
    var ticketId: UUID

    /// Human-readable reason why bet was queued for review (nil for auto-accepted bets)
    var policyViolationReason: String?

    /// Relationship: many bets belong to one player
    var player: Player?

    init(
        id: UUID = UUID(),
        eventId: String,
        market: String,
        side: String,
        odds: Int,
        stake: Decimal,
        status: BetStatus = .pending,
        gradeResult: GradeResult? = nil,
        player: Player? = nil,
        createdAt: Date = Date(),
        ticketId: UUID = UUID(),
        policyViolationReason: String? = nil
    ) {
        self.id = id
        self.eventId = eventId
        self.market = market
        self.side = side
        self.odds = odds
        self.stake = stake
        self.status = status
        self.gradeResult = gradeResult
        self.player = player
        self.createdAt = createdAt
        self.ticketId = ticketId
        self.policyViolationReason = policyViolationReason
    }
}
