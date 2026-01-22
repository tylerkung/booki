import Foundation
import SwiftData

/// Subscription status for a bookie account
enum SubscriptionStatus: String, Codable {
    case active
    case inactive
    case trial
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

    init(
        id: UUID = UUID(),
        email: String,
        name: String,
        subscriptionStatus: SubscriptionStatus = .trial,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.email = email
        self.name = name
        self.subscriptionStatus = subscriptionStatus
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
