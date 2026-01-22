import Foundation
import SwiftData

/// Type of ledger entry for tracking balance changes
enum EntryType: String, Codable {
    case settlement
    case adjustment
    case paymentLogged
    case reversal
}

/// Append-only ledger entry for tracking all balance changes
/// Note: This model is designed to be append-only - entries should never be updated or deleted
@Model
final class LedgerEntry {
    @Attribute(.unique) var id: UUID
    var amount: Decimal
    var type: EntryType
    var entryDescription: String
    var createdAt: Date

    /// Relationship: ledger entry belongs to one player (required)
    var player: Player?

    /// Relationship: ledger entry may be associated with a bet (optional)
    var bet: Bet?

    init(
        id: UUID = UUID(),
        amount: Decimal,
        type: EntryType,
        entryDescription: String,
        player: Player,
        bet: Bet? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.amount = amount
        self.type = type
        self.entryDescription = entryDescription
        self.player = player
        self.bet = bet
        self.createdAt = createdAt
    }
}
