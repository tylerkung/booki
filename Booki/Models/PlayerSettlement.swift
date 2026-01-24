import Foundation
import SwiftData

/// Model to track per-player settlement status within a settlement period
@Model
final class PlayerSettlement: Syncable {
    @Attribute(.unique) var id: UUID

    /// Whether the player has been marked as settled for this period
    var isSettled: Bool

    /// Timestamp when the player was marked as settled (nil until settled)
    var settledAt: Date?

    /// Optional notes from bookie about this settlement
    var notes: String?

    /// The week ending date (Sunday) linking this to a settlement period
    /// Uses date instead of relationship for simplicity
    var periodWeekEndingDate: Date

    /// Relationship: the player this settlement record belongs to
    var player: Player?

    // MARK: - Syncable Properties

    /// The bookie this player settlement belongs to (for multi-tenant isolation)
    var bookieId: UUID?

    /// Whether this record has local changes that need to be uploaded
    var needsSync: Bool

    /// When this record was last successfully synced with the server
    var lastSyncedAt: Date?

    /// Version number for optimistic locking / conflict detection
    var version: Int

    init(
        id: UUID = UUID(),
        isSettled: Bool = false,
        settledAt: Date? = nil,
        notes: String? = nil,
        periodWeekEndingDate: Date,
        player: Player? = nil,
        bookieId: UUID? = nil,
        needsSync: Bool = true,
        lastSyncedAt: Date? = nil,
        version: Int = 1
    ) {
        self.id = id
        self.isSettled = isSettled
        self.settledAt = settledAt
        self.notes = notes
        self.periodWeekEndingDate = periodWeekEndingDate
        self.player = player
        self.bookieId = bookieId
        self.needsSync = needsSync
        self.lastSyncedAt = lastSyncedAt
        self.version = version
    }
}
