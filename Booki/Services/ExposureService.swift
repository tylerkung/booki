import Foundation

/// Represents the exposure breakdown for a single side of an event
struct SideExposure {
    let side: String
    let softExposure: Decimal  // Pending bets liability
    let hardExposure: Decimal  // Accepted bets liability

    var totalExposure: Decimal {
        softExposure + hardExposure
    }
}

/// Represents the exposure breakdown for an event
struct EventExposure {
    let eventId: String
    let sides: [SideExposure]

    /// Event exposure is the maximum total liability across all sides
    var maxExposure: Decimal {
        sides.map { $0.totalExposure }.max() ?? Decimal.zero
    }

    /// Maximum soft exposure (pending bets only)
    var maxSoftExposure: Decimal {
        sides.map { $0.softExposure }.max() ?? Decimal.zero
    }

    /// Maximum hard exposure (accepted bets only)
    var maxHardExposure: Decimal {
        sides.map { $0.hardExposure }.max() ?? Decimal.zero
    }
}

/// Service for calculating exposure (risk) across events and sides
/// Exposure = potential liability if bets win, grouped by event and side
enum ExposureService {

    /// Filters bets to only include those that contribute to exposure
    /// (pending and accepted bets only - excludes declined, void, graded, settled)
    /// - Parameter bets: Array of bets to filter
    /// - Returns: Filtered array containing only pending and accepted bets
    static func exposureBets(from bets: [Bet]) -> [Bet] {
        return bets.filter { bet in
            bet.status == .pending || bet.status == .accepted
        }
    }

    /// Groups bets by their event ID
    /// - Parameter bets: Array of bets to group
    /// - Returns: Dictionary with eventId as key and array of bets as value
    static func groupBetsByEvent(_ bets: [Bet]) -> [String: [Bet]] {
        return Dictionary(grouping: bets, by: { $0.eventId })
    }

    /// Calculates exposure for a single event by grouping bets by side
    /// - Parameters:
    ///   - eventId: The event identifier
    ///   - bets: Array of bets for this event (should already be filtered for exposure)
    /// - Returns: EventExposure with breakdown by side
    static func calculateEventExposure(eventId: String, bets: [Bet]) -> EventExposure {
        // Group bets by side
        let betsBySide = Dictionary(grouping: bets, by: { $0.side })

        // Calculate exposure for each side
        let sideExposures = betsBySide.map { (side, sideBets) -> SideExposure in
            let pendingBets = sideBets.filter { $0.status == .pending }
            let acceptedBets = sideBets.filter { $0.status == .accepted }

            let softExposure = LiabilityService.calculateTotalLiability(for: pendingBets)
            let hardExposure = LiabilityService.calculateTotalLiability(for: acceptedBets)

            return SideExposure(side: side, softExposure: softExposure, hardExposure: hardExposure)
        }

        return EventExposure(eventId: eventId, sides: sideExposures)
    }

    /// Calculates exposure across all events from a collection of bets
    /// - Parameter bets: Array of all bets (will be filtered internally)
    /// - Returns: Array of EventExposure for each event with active bets
    static func calculateAllEventExposures(from bets: [Bet]) -> [EventExposure] {
        let activeBets = exposureBets(from: bets)
        let betsByEvent = groupBetsByEvent(activeBets)

        return betsByEvent.map { (eventId, eventBets) in
            calculateEventExposure(eventId: eventId, bets: eventBets)
        }
    }

    /// Calculates total exposure across all events
    /// - Parameter bets: Array of all bets (will be filtered internally)
    /// - Returns: Sum of max exposure for each event
    static func calculateTotalExposure(from bets: [Bet]) -> Decimal {
        let eventExposures = calculateAllEventExposures(from: bets)
        return eventExposures.reduce(Decimal.zero) { total, eventExposure in
            total + eventExposure.maxExposure
        }
    }

    /// Calculates exposure for a specific event from a collection of bets
    /// - Parameters:
    ///   - eventId: The event to calculate exposure for
    ///   - bets: Array of all bets (will be filtered internally)
    /// - Returns: EventExposure for the specified event, or nil if no bets exist
    static func calculateExposure(forEvent eventId: String, from bets: [Bet]) -> EventExposure? {
        let activeBets = exposureBets(from: bets)
        let eventBets = activeBets.filter { $0.eventId == eventId }

        guard !eventBets.isEmpty else { return nil }

        return calculateEventExposure(eventId: eventId, bets: eventBets)
    }
}
