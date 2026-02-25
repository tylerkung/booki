import Foundation
import SwiftData

/// Subscription tier for a bookie account
enum SubscriptionStatus: String, Codable {
    case free
    case pro
    case ultra
    // Legacy cases for migration
    case active
    case inactive
    case trial
}

/// Tier level controlling feature access
enum BookieTier: String, Codable {
    case `default`
    case chart
}

/// Bookie model representing a bookie account
@Model
final class Bookie {
    @Attribute(.unique) var id: UUID
    var email: String
    var name: String
    var subscriptionStatus: SubscriptionStatus
    var createdAt: Date
    var updatedAt: Date

    // Auto-pilot settings (US-008, US-009)
    // When false (default), bets are auto-accepted and auto-graded
    var manualBetAcceptance: Bool
    var manualBetGrading: Bool

    // When false, players cannot include outright/futures picks in multi-picks
    var allowFuturesParlays: Bool

    // Feature tier
    var tier: BookieTier

    init(
        id: UUID = UUID(),
        email: String,
        name: String,
        subscriptionStatus: SubscriptionStatus = .free,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        manualBetAcceptance: Bool = false,
        manualBetGrading: Bool = false,
        allowFuturesParlays: Bool = true,
        tier: BookieTier = .default
    ) {
        self.id = id
        self.email = email
        self.name = name
        self.subscriptionStatus = subscriptionStatus
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.manualBetAcceptance = manualBetAcceptance
        self.manualBetGrading = manualBetGrading
        self.allowFuturesParlays = allowFuturesParlays
        self.tier = tier
    }
}
