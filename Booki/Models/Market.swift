import Foundation
import SwiftData

/// Type of betting market
enum MarketType: String, Codable {
    case spread
    case total
    case moneyline
    case alternateSpread = "alternate_spread"
    case alternateTotal = "alternate_total"
    case teamTotal = "team_total"
    case outright

    var displayName: String {
        switch self {
        case .spread: return "Spread"
        case .total: return "Total"
        case .moneyline: return "Moneyline"
        case .alternateSpread: return "Alt Spread"
        case .alternateTotal: return "Alt Total"
        case .teamTotal: return "Team Total"
        case .outright: return "Outright"
        }
    }

    /// Whether this market grades like a spread (team + point value)
    var gradesAsSpread: Bool {
        self == .spread || self == .alternateSpread
    }

    /// Whether this market grades like a total (over/under a number)
    var gradesAsTotal: Bool {
        self == .total || self == .alternateTotal || self == .teamTotal
    }

    /// Whether this is an alternate or non-main line
    var isAlternate: Bool {
        self == .alternateSpread || self == .alternateTotal || self == .teamTotal
    }

    /// Whether this is a main line (spread, total, moneyline)
    var isMainLine: Bool {
        self == .spread || self == .total || self == .moneyline
    }

    /// Whether this is an outright/futures market
    var isOutright: Bool {
        self == .outright
    }
}

/// Market model representing a betting market for an event
@Model
final class Market {
    @Attribute(.unique) var id: UUID
    var type: MarketType
    var sideA: String
    var sideB: String
    var oddsA: Int
    var oddsB: Int
    var updatedAt: Date

    /// Relationship: market belongs to one event
    var event: Event?

    init(
        id: UUID = UUID(),
        type: MarketType,
        sideA: String,
        sideB: String,
        oddsA: Int,
        oddsB: Int,
        event: Event? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.sideA = sideA
        self.sideB = sideB
        self.oddsA = oddsA
        self.oddsB = oddsB
        self.event = event
        self.updatedAt = updatedAt
    }
}
