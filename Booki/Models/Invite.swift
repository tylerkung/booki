import Foundation
import SwiftData

@Model
final class Invite {
    @Attribute(.unique) var id: UUID
    var bookieId: UUID
    var inviteCode: String
    var email: String?
    var createdAt: Date
    var expiresAt: Date
    var claimedAt: Date?
    var claimedByPlayerId: UUID?
    var needsSync: Bool
    var version: Int

    // MARK: - Computed Properties

    var isExpired: Bool {
        expiresAt < Date()
    }

    var isPending: Bool {
        claimedAt == nil && !isExpired
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        bookieId: UUID,
        inviteCode: String,
        email: String? = nil,
        createdAt: Date = Date(),
        expiresAt: Date,
        claimedAt: Date? = nil,
        claimedByPlayerId: UUID? = nil,
        needsSync: Bool = false,
        version: Int = 0
    ) {
        self.id = id
        self.bookieId = bookieId
        self.inviteCode = inviteCode
        self.email = email
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.claimedAt = claimedAt
        self.claimedByPlayerId = claimedByPlayerId
        self.needsSync = needsSync
        self.version = version
    }
}
