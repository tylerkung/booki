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
}
