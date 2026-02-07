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
final class Bet: Syncable {
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

    /// Whether this bet is part of a parlay (default false for singles)
    var isParlay: Bool

    /// Number of legs in the parlay (1 for singles, N for parlays)
    var parlayLegs: Int

    /// Human-readable event description for offline display (e.g., "Lakers @ Celtics")
    var eventDescription: String?

    /// Sport league abbreviation for display (e.g., "NBA", "NFL")
    var sportLeague: String?

    /// Server-side indicator for which side of the market was selected ('a' or 'b')
    var sideIndicator: String?

    /// Relationship: many bets belong to one player
    var player: Player?

    // MARK: - Syncable Properties

    /// The bookie this bet belongs to (for multi-tenant isolation)
    var bookieId: UUID?

    /// Whether this record has local changes that need to be uploaded
    var needsSync: Bool

    /// When this record was last successfully synced with the server
    var lastSyncedAt: Date?

    /// Version number for optimistic locking / conflict detection
    var version: Int

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
        policyViolationReason: String? = nil,
        isParlay: Bool = false,
        parlayLegs: Int = 1,
        eventDescription: String? = nil,
        sportLeague: String? = nil,
        sideIndicator: String? = nil,
        bookieId: UUID? = nil,
        needsSync: Bool = true,
        lastSyncedAt: Date? = nil,
        version: Int = 1
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
        self.isParlay = isParlay
        self.parlayLegs = parlayLegs
        self.eventDescription = eventDescription
        self.sportLeague = sportLeague
        self.sideIndicator = sideIndicator
        self.bookieId = bookieId
        self.needsSync = needsSync
        self.lastSyncedAt = lastSyncedAt
        self.version = version
    }
}
