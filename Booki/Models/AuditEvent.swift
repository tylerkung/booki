import Foundation
import SwiftData

/// Audit event record for tracking state changes in the system
/// The server (audit_events table) is the source of truth; this model caches audit history locally
@Model
final class AuditEvent {
    @Attribute(.unique) var id: UUID
    var bookieId: UUID
    var actorUserId: UUID
    var entityType: String
    var entityId: UUID
    var actionType: String
    var previousState: String?  // JSON string
    var newState: String        // JSON string
    var reason: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        bookieId: UUID,
        actorUserId: UUID,
        entityType: String,
        entityId: UUID,
        actionType: String,
        previousState: String? = nil,
        newState: String,
        reason: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.bookieId = bookieId
        self.actorUserId = actorUserId
        self.entityType = entityType
        self.entityId = entityId
        self.actionType = actionType
        self.previousState = previousState
        self.newState = newState
        self.reason = reason
        self.createdAt = createdAt
    }
}
