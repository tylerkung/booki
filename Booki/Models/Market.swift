import Foundation
import SwiftData

/// Type of betting market
enum MarketType: String, Codable {
    case spread
    case total
    case moneyline

    var displayName: String {
        switch self {
        case .spread: return "Spread"
        case .total: return "Total"
        case .moneyline: return "Moneyline"
        }
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
