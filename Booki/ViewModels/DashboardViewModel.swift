import Foundation
import SwiftData

/// View model for the Dashboard view
/// Manages loading and calculating dashboard metrics
@MainActor
@Observable
class DashboardViewModel {

    // MARK: - Published Properties

    /// Total open exposure across all events
    var totalExposure: Decimal = 0

    /// Count of pending bets requiring action
    var pendingBetsCount: Int = 0

    /// Top events by exposure (max 5)
    var topRiskEvents: [EventRiskItem] = []

    /// Pending bets for action queue
    var pendingBets: [Bet] = []

    /// Loading state
    var isLoading: Bool = false

    // MARK: - Data Loading

    /// Refreshes all dashboard data from the model context
    /// - Parameters:
    ///   - bets: All bets from the data store
    ///   - events: All events from the data store
    func refresh(bets: [Bet], events: [Event]) {
        isLoading = true

        // Calculate total exposure
        totalExposure = ExposureService.calculateTotalExposure(from: bets)

        // Count pending bets
        pendingBets = bets.filter { $0.status == .pending }
        pendingBetsCount = pendingBets.count

        // Calculate event exposures and get top 5
        let eventExposures = ExposureService.calculateAllEventExposures(from: bets)

        // Map event exposures to risk items with event details
        let eventDict = Dictionary(uniqueKeysWithValues: events.map { ($0.id.uuidString, $0) })

        let riskItems = eventExposures.compactMap { exposure -> EventRiskItem? in
            guard let event = eventDict[exposure.eventId] else {
                // Try to create a basic item even without full event details
                return EventRiskItem(
                    eventId: exposure.eventId,
                    displayName: "Event \(exposure.eventId.prefix(8))",
                    exposure: exposure.maxExposure,
                    startTime: nil
                )
            }
            return EventRiskItem(
                eventId: exposure.eventId,
                displayName: "\(event.awayTeam) @ \(event.homeTeam)",
                exposure: exposure.maxExposure,
                startTime: event.startTime
            )
        }

        // Sort by exposure (descending) and take top 5
        topRiskEvents = riskItems
            .sorted { $0.exposure > $1.exposure }
            .prefix(5)
            .map { $0 }

        isLoading = false
    }
}

/// Represents an event with its risk/exposure information for display
struct EventRiskItem: Identifiable {
    let eventId: String
    let displayName: String
    let exposure: Decimal
    let startTime: Date?

    var id: String { eventId }

    /// Formatted exposure string
    var formattedExposure: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: exposure as NSDecimalNumber) ?? "$\(exposure)"
    }

    /// Formatted start time string
    var formattedStartTime: String? {
        guard let startTime = startTime else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: startTime)
    }
}
