import Foundation
import SwiftData

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
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
