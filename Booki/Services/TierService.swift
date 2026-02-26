import Foundation
import SwiftData

/// Centralized tier-checking helpers for the freemium system.
/// Reads from @AppStorage for instant UI access, synced from Supabase on login/sync.
enum TierService {

    // MARK: - AppStorage Key

    static let tierKey = "bookieTier"

    // MARK: - Read Tier

    /// Read the cached tier from UserDefaults (for non-View contexts).
    static var currentTier: BookieTier {
        let raw = UserDefaults.standard.string(forKey: tierKey) ?? BookieTier.free.rawValue
        return BookieTier(rawValue: raw) ?? .free
    }

    /// Whether the cached tier is Pro (tier-only check for non-View contexts)
    static var isPro: Bool {
        currentTier.isPro
    }

    // MARK: - Write Tier

    /// Update the cached tier in UserDefaults
    static func setTier(_ tier: BookieTier) {
        UserDefaults.standard.set(tier.rawValue, forKey: tierKey)
    }

    /// Sync tier from a BookieRecord (call during sync)
    static func syncTier(from record: BookieRecord) {
        let tier = BookieTier(rawValue: record.tier ?? "free") ?? .free
        setTier(tier)
    }

    // MARK: - Member Counting

    /// Count active members for a bookie (players with matching bookieId and non-nil authUserId)
    @MainActor
    static func activeMemberCount(bookieId: UUID, context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<Player>(predicate: #Predicate<Player> {
            $0.bookieId == bookieId && $0.authUserId != nil
        })
        guard let players = try? context.fetch(descriptor) else { return 0 }
        return players.filter { $0.status == .active }.count
    }

    /// Whether the bookie is at their member limit
    @MainActor
    static func isAtMemberLimit(bookieId: UUID, context: ModelContext) -> Bool {
        let count = activeMemberCount(bookieId: bookieId, context: context)
        return count >= currentTier.memberLimit
    }
}
