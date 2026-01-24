import Foundation
import SwiftData

/// Model to track per-player settlement status within a settlement period
@Model
final class PlayerSettlement {
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

    init(
        id: UUID = UUID(),
        isSettled: Bool = false,
        settledAt: Date? = nil,
        notes: String? = nil,
        periodWeekEndingDate: Date,
        player: Player? = nil
    ) {
        self.id = id
        self.isSettled = isSettled
        self.settledAt = settledAt
        self.notes = notes
        self.periodWeekEndingDate = periodWeekEndingDate
        self.player = player
    }
}
