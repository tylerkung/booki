import Foundation
import SwiftData

/// Service for generating and validating player invite codes
@MainActor
final class InviteCodeService {

    // MARK: - Constants

    /// Characters used for generating invite codes (excludes confusing chars: 0/O, 1/I/L)
    private static let codeCharacters = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"

    /// Length of generated invite codes
    private static let codeLength = 8

    // MARK: - Properties

    private let modelContext: ModelContext

    // MARK: - Initialization

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Code Generation

    /// Generates a random 8-character alphanumeric invite code
    /// - Returns: A unique invite code string
    func generateCode() -> String {
        let characters = Array(Self.codeCharacters)
        var code = ""
        for _ in 0..<Self.codeLength {
            if let randomChar = characters.randomElement() {
                code.append(randomChar)
            }
        }
        return code
    }

    /// Generates and assigns an invite code to a player
    /// - Parameters:
    ///   - player: The player to assign the code to
    ///   - expiresIn: Optional expiration time interval (nil = never expires)
    func generateInviteForPlayer(_ player: Player, expiresIn: TimeInterval? = nil) {
        let code = generateCode()
        let now = Date()

        player.inviteCode = code
        player.inviteCodeGeneratedAt = now

        if let expiresIn = expiresIn {
            player.inviteCodeExpiresAt = now.addingTimeInterval(expiresIn)
        } else {
            player.inviteCodeExpiresAt = nil
        }

        player.needsSync = true
        player.updatedAt = now

        // Explicitly save to ensure persistence
        do {
            try modelContext.save()
        } catch {
        }
    }

    // MARK: - Code Validation

    /// Validates an invite code and returns the associated player if valid
    /// - Parameter code: The invite code to validate
    /// - Returns: The player associated with the code, or nil if invalid/expired
    func validateCode(_ code: String) -> Player? {
        let normalizedCode = code.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Fetch player with matching invite code
        let predicate = #Predicate<Player> { player in
            player.inviteCode == normalizedCode
        }

        var fetchDescriptor = FetchDescriptor<Player>(predicate: predicate)
        fetchDescriptor.fetchLimit = 1

        do {
            let players = try modelContext.fetch(fetchDescriptor)
            guard let player = players.first else {
                return nil
            }

            // Check if already claimed
            if player.claimedAt != nil {
                return nil
            }

            // Check expiration
            if let expiresAt = player.inviteCodeExpiresAt, Date() > expiresAt {
                return nil
            }

            return player
        } catch {
            print("Error validating invite code: \(error)")
            return nil
        }
    }

    // MARK: - Code Management

    /// Revokes the invite code for a player
    /// - Parameter player: The player whose code should be revoked
    func revokeCode(for player: Player) {
        player.inviteCode = nil
        player.inviteCodeGeneratedAt = nil
        player.inviteCodeExpiresAt = nil
        player.needsSync = true
        player.updatedAt = Date()
    }

    /// Marks a player's account as claimed
    /// - Parameters:
    ///   - player: The player to mark as claimed
    ///   - authUserId: The Supabase auth user ID for the player
    func claimAccount(for player: Player, authUserId: UUID) {
        player.claimedAt = Date()
        player.authUserId = authUserId
        player.needsSync = true
        player.updatedAt = Date()
    }
}
