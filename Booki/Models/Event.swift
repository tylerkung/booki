import Foundation
import SwiftData

/// Status for an event
enum EventStatus: String, Codable {
    case scheduled
    case live
    case final
    case postponed
    case canceled
}

/// Event model representing a sports event
@Model
final class Event: Syncable {
    @Attribute(.unique) var id: UUID
    var sport: String
    var league: String
    var homeTeam: String
    var awayTeam: String
    var startTime: Date
    var status: EventStatus
    var finalScore: String?

    /// Relationship: one event has many markets
    @Relationship(deleteRule: .cascade, inverse: \Market.event)
    var markets: [Market]?

    // MARK: - Syncable Properties

    /// The bookie this event belongs to (for multi-tenant isolation)
    var bookieId: UUID?

    /// Whether this record has local changes that need to be uploaded
    var needsSync: Bool

    /// When this record was last successfully synced with the server
    var lastSyncedAt: Date?

    /// Version number for optimistic locking / conflict detection
    var version: Int

    // MARK: - US-005: External API Fields

    /// External ID from the API (e.g., The Odds API event ID)
    var externalId: String?

    /// Source of the external data (e.g., "the-odds-api")
    var externalSource: String?

    /// When odds were last updated from the API
    var lastOddsUpdate: Date?

    /// Final home team score (for auto-grading)
    var homeScore: Int?

    /// Final away team score (for auto-grading)
    var awayScore: Int?

    // MARK: - Auto-Refresh Tracking

    /// When odds were last automatically refreshed by the server
    var lastAutoOddsRefresh: Date?

    /// When scores were last automatically refreshed by the server
    var lastAutoScoreRefresh: Date?

    init(
        id: UUID = UUID(),
        sport: String,
        league: String,
        homeTeam: String,
        awayTeam: String,
        startTime: Date,
        status: EventStatus = .scheduled,
        finalScore: String? = nil,
        markets: [Market]? = nil,
        bookieId: UUID? = nil,
        needsSync: Bool = true,
        lastSyncedAt: Date? = nil,
        version: Int = 1,
        externalId: String? = nil,
        externalSource: String? = nil,
        lastOddsUpdate: Date? = nil,
        homeScore: Int? = nil,
        awayScore: Int? = nil,
        lastAutoOddsRefresh: Date? = nil,
        lastAutoScoreRefresh: Date? = nil
    ) {
        self.id = id
        self.sport = sport
        self.league = league
        self.homeTeam = homeTeam
        self.awayTeam = awayTeam
        self.startTime = startTime
        self.status = status
        self.finalScore = finalScore
        self.markets = markets
        self.bookieId = bookieId
        self.needsSync = needsSync
        self.lastSyncedAt = lastSyncedAt
        self.version = version
        self.externalId = externalId
        self.externalSource = externalSource
        self.lastOddsUpdate = lastOddsUpdate
        self.homeScore = homeScore
        self.awayScore = awayScore
        self.lastAutoOddsRefresh = lastAutoOddsRefresh
        self.lastAutoScoreRefresh = lastAutoScoreRefresh
    }

    // MARK: - Event Lock Logic

    /// Returns the time at which the event becomes locked for betting
    /// - Parameter offsetMinutes: Minutes before start time to lock betting
    /// - Returns: The lock time (startTime minus offset)
    func lockTime(offsetMinutes: Int) -> Date {
        return startTime.addingTimeInterval(-Double(offsetMinutes * 60))
    }

    /// Determines if the event is locked for betting
    /// - Parameter offsetMinutes: Minutes before start time to lock betting
    /// - Returns: true if event is locked (current time >= lock time, or event is live/final/canceled)
    func isLocked(offsetMinutes: Int) -> Bool {
        // Canceled events are always locked
        if status == .canceled {
            return true
        }

        // Events that are live or final are always locked
        if status == .live || status == .final {
            return true
        }

        // Postponed events allow betting (on the new time when rescheduled)
        if status == .postponed {
            return false
        }

        // Check if current time is past the lock time
        return Date() >= lockTime(offsetMinutes: offsetMinutes)
    }
}
