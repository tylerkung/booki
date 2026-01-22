import Foundation
import SwiftData

/// Status for a player in a bookie's book
enum PlayerStatus: String, Codable {
    case active
    case archived
    case banned
}

/// Player model representing a player seat that belongs to a bookie
@Model
final class Player {
    @Attribute(.unique) var id: UUID
    var name: String
    var email: String?
    var creditLimit: Decimal
    var status: PlayerStatus
    var createdAt: Date
    var updatedAt: Date

    /// Relationship: many players belong to one bookie
    var bookie: Bookie?

    init(
        id: UUID = UUID(),
        name: String,
        email: String? = nil,
        creditLimit: Decimal = 0,
        status: PlayerStatus = .active,
        bookie: Bookie? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.creditLimit = creditLimit
        self.status = status
        self.bookie = bookie
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
