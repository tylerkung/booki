import Foundation
import SwiftData

/// Settlement period model representing a weekly settlement window
/// The week is defined by its ending date (Sunday)
@Model
final class SettlementPeriod: Syncable {
    @Attribute(.unique) var id: UUID

    /// The Sunday that ends this settlement week
    var weekEndingDate: Date

    /// When this settlement period was created
    var createdAt: Date

    /// Computed: Start of the week (7 days before weekEndingDate)
    var weekStartDate: Date {
        Calendar.current.date(byAdding: .day, value: -6, to: weekEndingDate) ?? weekEndingDate
    }

    /// Computed: Human-readable date range (e.g., "Jan 13 - Jan 19, 2026")
    var dateRangeDescription: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"

        let yearFormatter = DateFormatter()
        yearFormatter.dateFormat = "MMM d, yyyy"

        let startStr = formatter.string(from: weekStartDate)
        let endStr = yearFormatter.string(from: weekEndingDate)

        return "\(startStr) - \(endStr)"
    }

    // MARK: - Syncable Properties

    /// The bookie this settlement period belongs to (for multi-tenant isolation)
    var bookieId: UUID?

    /// Whether this record has local changes that need to be uploaded
    var needsSync: Bool

    /// When this record was last successfully synced with the server
    var lastSyncedAt: Date?

    /// Version number for optimistic locking / conflict detection
    var version: Int

    init(
        id: UUID = UUID(),
        weekEndingDate: Date,
        createdAt: Date = Date(),
        bookieId: UUID? = nil,
        needsSync: Bool = true,
        lastSyncedAt: Date? = nil,
        version: Int = 1
    ) {
        self.id = id
        self.weekEndingDate = weekEndingDate
        self.createdAt = createdAt
        self.bookieId = bookieId
        self.needsSync = needsSync
        self.lastSyncedAt = lastSyncedAt
        self.version = version
    }
}
