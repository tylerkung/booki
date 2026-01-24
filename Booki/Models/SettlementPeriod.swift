import Foundation
import SwiftData

/// Settlement period model representing a weekly settlement window
/// The week is defined by its ending date (Sunday)
@Model
final class SettlementPeriod {
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

    init(
        id: UUID = UUID(),
        weekEndingDate: Date,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.weekEndingDate = weekEndingDate
        self.createdAt = createdAt
    }
}
