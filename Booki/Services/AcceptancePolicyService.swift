import Foundation

/// Reasons why a bet may violate the acceptance policy
enum PolicyViolation: Equatable {
    case stakeTooHigh
    case stakeRequiresReview
    case newPlayer
    case parlayNotAllowed
    case parlayTooManyLegs
    case eventLocked
}

/// Service for evaluating bets against acceptance policy rules
enum AcceptancePolicyService {

    /// Evaluates a bet against the acceptance policy and returns any violations
    /// - Parameters:
    ///   - stake: The bet stake amount
    ///   - isParlay: Whether this is a parlay bet
    ///   - parlayLegs: Number of legs in the parlay (0 for singles)
    ///   - playerBetCount: Number of bets the player has previously placed
    ///   - event: The event being bet on
    ///   - policy: The acceptance policy to evaluate against
    /// - Returns: Array of policy violations (empty if bet should be auto-accepted)
    static func evaluateBet(
        stake: Decimal,
        isParlay: Bool,
        parlayLegs: Int,
        playerBetCount: Int,
        event: Event,
        policy: AcceptancePolicy
    ) -> [PolicyViolation] {
        var violations: [PolicyViolation] = []

        // Stake check: stake > policy.autoAcceptMaxStake returns .stakeTooHigh
        if stake > policy.autoAcceptMaxStake {
            violations.append(.stakeTooHigh)
        }

        // Stake check: stake > policy.requireReviewAboveStake returns .stakeRequiresReview
        if stake > policy.requireReviewAboveStake {
            violations.append(.stakeRequiresReview)
        }

        // New player check: playerBetCount < policy.newPlayerBetThreshold AND !policy.autoAcceptNewPlayers returns .newPlayer
        if playerBetCount < policy.newPlayerBetThreshold && !policy.autoAcceptNewPlayers {
            violations.append(.newPlayer)
        }

        // Parlay check: isParlay AND !policy.autoAcceptParlays returns .parlayNotAllowed
        if isParlay && !policy.autoAcceptParlays {
            violations.append(.parlayNotAllowed)
        }

        // Parlay legs check: isParlay AND parlayLegs > policy.parlayMaxLegs returns .parlayTooManyLegs
        if isParlay && parlayLegs > policy.parlayMaxLegs {
            violations.append(.parlayTooManyLegs)
        }

        // Event lock check: event.startTime <= Date() + policy.eventLockOffsetMinutes returns .eventLocked
        let lockTime = event.startTime.addingTimeInterval(-Double(policy.eventLockOffsetMinutes * 60))
        if Date() >= lockTime {
            violations.append(.eventLocked)
        }

        // Also check if event is already live or final
        if event.status == .live || event.status == .final {
            if !violations.contains(.eventLocked) {
                violations.append(.eventLocked)
            }
        }

        return violations
    }

    /// Returns a human-readable description for a policy violation
    /// - Parameter violation: The violation to describe
    /// - Returns: Human-readable text explaining the violation
    static func violationDescription(_ violation: PolicyViolation) -> String {
        switch violation {
        case .stakeTooHigh:
            return "Stake exceeds auto-accept limit"
        case .stakeRequiresReview:
            return "Stake requires manual review"
        case .newPlayer:
            return "New player requires review"
        case .parlayNotAllowed:
            return "Parlays require manual review"
        case .parlayTooManyLegs:
            return "Parlay has too many legs"
        case .eventLocked:
            return "Event is locked for betting"
        }
    }

    /// Returns a combined description for multiple violations
    /// - Parameter violations: Array of violations to describe
    /// - Returns: Comma-separated human-readable text
    static func combinedViolationDescription(_ violations: [PolicyViolation]) -> String {
        violations.map { violationDescription($0) }.joined(separator: ", ")
    }
}
