import Foundation
import SwiftData

/// Status for an event
enum EventStatus: String, Codable {
    case scheduled
    case live
    case final
}

/// Event model representing a sports event
@Model
final class Event {
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

    init(
        id: UUID = UUID(),
        sport: String,
        league: String,
        homeTeam: String,
        awayTeam: String,
        startTime: Date,
        status: EventStatus = .scheduled,
        finalScore: String? = nil,
        markets: [Market]? = nil
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
    /// - Returns: true if event is locked (current time >= lock time, or event is live/final)
    func isLocked(offsetMinutes: Int) -> Bool {
        // Events that are live or final are always locked
        if status == .live || status == .final {
            return true
        }

        // Check if current time is past the lock time
        return Date() >= lockTime(offsetMinutes: offsetMinutes)
    }
}
