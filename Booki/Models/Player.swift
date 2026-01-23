import Foundation
import SwiftData

/// Status for a player in a bookie's book
enum PlayerStatus: String, Codable {
    case active
    case archived
    case banned
}

/// Collection status for tracking outstanding balance follow-ups
enum CollectionStatus: String, Codable, CaseIterable, Identifiable {
    case noStatus
    case reminded
    case promised
    case overdue

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .noStatus: return "None"
        case .reminded: return "Reminded"
        case .promised: return "Promised"
        case .overdue: return "Overdue"
        }
    }

    var color: String {
        switch self {
        case .noStatus: return "gray"
        case .reminded: return "yellow"
        case .promised: return "blue"
        case .overdue: return "red"
        }
    }
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

    /// Optional username for player authentication (future use)
    var username: String?

    /// Optional password hash for player authentication (never store plain text passwords)
    var passwordHash: String?

    /// Collection status for tracking outstanding balance follow-ups
    var collectionStatus: CollectionStatus?

    /// Date when collection status was last updated
    var collectionStatusDate: Date?

    /// Optional date when player promised to pay (used with .promised status)
    var promisedPaymentDate: Date?

    /// Relationship: many players belong to one bookie
    var bookie: Bookie?

    init(
        id: UUID = UUID(),
        name: String,
        email: String? = nil,
        creditLimit: Decimal = 0,
        status: PlayerStatus = .active,
        bookie: Bookie? = nil,
        username: String? = nil,
        passwordHash: String? = nil,
        collectionStatus: CollectionStatus? = nil,
        collectionStatusDate: Date? = nil,
        promisedPaymentDate: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.creditLimit = creditLimit
        self.status = status
        self.bookie = bookie
        self.username = username
        self.passwordHash = passwordHash
        self.collectionStatus = collectionStatus
        self.collectionStatusDate = collectionStatusDate
        self.promisedPaymentDate = promisedPaymentDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
