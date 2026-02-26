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
final class Player: Syncable {
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

    /// Unique 8-character alphanumeric invite code for player to claim account
    var inviteCode: String?

    /// When the invite code was generated
    var inviteCodeGeneratedAt: Date?

    /// When the invite code expires (nil = never expires)
    var inviteCodeExpiresAt: Date?

    /// When the player claimed their account
    var claimedAt: Date?

    /// Links to Supabase auth user after player claims account
    var authUserId: UUID?

    /// Bookie-set custom display name (only bookie sees this)
    var displayName: String?

    /// Collection status for tracking outstanding balance follow-ups
    var collectionStatus: CollectionStatus?

    /// Date when collection status was last updated
    var collectionStatusDate: Date?

    /// Optional date when player promised to pay (used with .promised status)
    var promisedPaymentDate: Date?

    /// Relationship: many players belong to one bookie
    var bookie: Bookie?

    // MARK: - Syncable Properties

    /// The bookie this player belongs to (for multi-tenant isolation)
    var bookieId: UUID?

    /// Whether this record has local changes that need to be uploaded
    var needsSync: Bool

    /// When this record was last successfully synced with the server
    var lastSyncedAt: Date?

    /// Version number for optimistic locking / conflict detection
    var version: Int

    init(
        id: UUID = UUID(),
        name: String,
        email: String? = nil,
        creditLimit: Decimal = 0,
        status: PlayerStatus = .active,
        bookie: Bookie? = nil,
        username: String? = nil,
        passwordHash: String? = nil,
        inviteCode: String? = nil,
        inviteCodeGeneratedAt: Date? = nil,
        inviteCodeExpiresAt: Date? = nil,
        claimedAt: Date? = nil,
        authUserId: UUID? = nil,
        displayName: String? = nil,
        collectionStatus: CollectionStatus? = nil,
        collectionStatusDate: Date? = nil,
        promisedPaymentDate: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        bookieId: UUID? = nil,
        needsSync: Bool = true,
        lastSyncedAt: Date? = nil,
        version: Int = 1
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.creditLimit = creditLimit
        self.status = status
        self.bookie = bookie
        self.username = username
        self.passwordHash = passwordHash
        self.inviteCode = inviteCode
        self.inviteCodeGeneratedAt = inviteCodeGeneratedAt
        self.inviteCodeExpiresAt = inviteCodeExpiresAt
        self.claimedAt = claimedAt
        self.authUserId = authUserId
        self.displayName = displayName
        self.collectionStatus = collectionStatus
        self.collectionStatusDate = collectionStatusDate
        self.promisedPaymentDate = promisedPaymentDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.bookieId = bookieId
        self.needsSync = needsSync
        self.lastSyncedAt = lastSyncedAt
        self.version = version
    }
}
