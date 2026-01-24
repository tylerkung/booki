import Foundation
import SwiftData

/// Policy for how pushes and voids are handled in parlay bets
enum ParlayPushVoidPolicy: String, Codable, CaseIterable {
    /// Reduce parlay to remaining legs and recalculate payout at adjusted odds
    case reduceLegReprice
    /// Treat the entire parlay as a push (stake returned)
    case treatAsPush

    /// Human-readable display label
    var displayLabel: String {
        switch self {
        case .reduceLegReprice:
            return "Reduce legs & reprice"
        case .treatAsPush:
            return "Treat as push"
        }
    }

    /// Explanatory description for the policy
    var explanation: String {
        switch self {
        case .reduceLegReprice:
            return "If a leg pushes or is voided, remove it from the parlay and recalculate the payout with the remaining legs."
        case .treatAsPush:
            return "If any leg pushes or is voided, the entire parlay becomes a push and the stake is returned."
        }
    }
}

/// AcceptancePolicy model storing bookie's acceptance policy configuration
/// Used to determine if bets should be auto-accepted, queued for review, or rejected
@Model
final class AcceptancePolicy {
    @Attribute(.unique) var id: UUID

    /// Maximum stake amount to auto-accept without review
    var autoAcceptMaxStake: Decimal

    /// Stake amount above which bets require manual review
    var requireReviewAboveStake: Decimal

    /// Whether to auto-accept bets from new players
    var autoAcceptNewPlayers: Bool

    /// Number of bets a player must have before being considered "established"
    var newPlayerBetThreshold: Int

    /// Whether to auto-accept parlay bets
    var autoAcceptParlays: Bool

    /// Maximum number of legs allowed in a parlay for auto-accept
    var parlayMaxLegs: Int

    /// Minutes before event start to lock betting (0 = lock at start time)
    var eventLockOffsetMinutes: Int

    /// Parlay push/void handling policy stored as String for SwiftData compatibility
    /// Use parlayPushVoidPolicyEnum computed property for type-safe access
    var parlayPushVoidPolicy: String

    /// Type-safe access to the parlay push/void policy
    var parlayPushVoidPolicyEnum: ParlayPushVoidPolicy {
        get {
            ParlayPushVoidPolicy(rawValue: parlayPushVoidPolicy) ?? .reduceLegReprice
        }
        set {
            parlayPushVoidPolicy = newValue.rawValue
        }
    }

    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        autoAcceptMaxStake: Decimal = 100,
        requireReviewAboveStake: Decimal = 500,
        autoAcceptNewPlayers: Bool = false,
        newPlayerBetThreshold: Int = 5,
        autoAcceptParlays: Bool = false,
        parlayMaxLegs: Int = 4,
        eventLockOffsetMinutes: Int = 0,
        parlayPushVoidPolicy: String = ParlayPushVoidPolicy.reduceLegReprice.rawValue,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.autoAcceptMaxStake = autoAcceptMaxStake
        self.requireReviewAboveStake = requireReviewAboveStake
        self.autoAcceptNewPlayers = autoAcceptNewPlayers
        self.newPlayerBetThreshold = newPlayerBetThreshold
        self.autoAcceptParlays = autoAcceptParlays
        self.parlayMaxLegs = parlayMaxLegs
        self.eventLockOffsetMinutes = eventLockOffsetMinutes
        self.parlayPushVoidPolicy = parlayPushVoidPolicy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
