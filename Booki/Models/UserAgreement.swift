import Foundation
import SwiftData

/// Cached record of a user's acceptance of the Terms of Service
/// The server (user_agreements table) is the source of truth; this model caches the status locally
@Model
final class UserAgreement {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var role: String
    var version: String
    var acceptedAt: Date

    init(
        id: UUID = UUID(),
        userId: UUID,
        role: String,
        version: String,
        acceptedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.role = role
        self.version = version
        self.acceptedAt = acceptedAt
    }
}
