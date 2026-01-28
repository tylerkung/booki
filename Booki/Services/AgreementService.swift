import Foundation
import Supabase

/// Status of user agreement acceptance
enum AgreementStatus: Equatable {
    case accepted
    case required
    case outdated
}

/// Error types for agreement operations
enum AgreementServiceError: Error, LocalizedError {
    case notAuthenticated
    case networkError(Error)
    case databaseError(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User is not authenticated"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .databaseError(let message):
            return "Database error: \(message)"
        }
    }
}

/// Service for checking and submitting user agreement acceptances to Supabase
/// This service communicates with the user_agreements table to track legal acknowledgments
final class AgreementService {

    // MARK: - Constants

    /// Current version of the terms of service
    /// Increment this when terms are updated to require re-acceptance
    static let currentAgreementVersion = "1.0"

    // MARK: - Private Properties

    private let supabase: SupabaseClient

    // MARK: - Initialization

    init() {
        self.supabase = SupabaseClientManager.shared.client
    }

    // MARK: - Public Methods

    /// Check the agreement status for a user
    /// - Parameter userId: The UUID of the user to check
    /// - Returns: AgreementStatus indicating whether user has accepted current terms
    /// - Throws: AgreementServiceError on failure
    func checkAgreementStatus(userId: UUID) async throws -> AgreementStatus {
        do {
            // Query user_agreements for this user, ordered by accepted_at descending
            // to get the most recent agreement
            let records: [UserAgreementRecord] = try await supabase
                .from("user_agreements")
                .select()
                .eq("user_id", value: userId.uuidString)
                .order("accepted_at", ascending: false)
                .limit(1)
                .execute()
                .value

            // If no agreement found, user needs to accept terms
            guard let latestAgreement = records.first else {
                return .required
            }

            // Check if the accepted version matches current version
            if latestAgreement.version == Self.currentAgreementVersion {
                return .accepted
            } else {
                // User has accepted an older version, needs to accept new terms
                return .outdated
            }
        } catch {
            throw AgreementServiceError.networkError(error)
        }
    }

    /// Submit a new agreement acceptance for a user
    /// - Parameters:
    ///   - userId: The UUID of the user accepting the agreement
    ///   - role: The user's role (bookie or player)
    ///   - version: The version of the agreement being accepted
    /// - Throws: AgreementServiceError on failure
    func submitAgreement(userId: UUID, role: String, version: String) async throws {
        do {
            let agreement = UserAgreementInsert(
                userId: userId,
                role: role,
                version: version
            )

            try await supabase
                .from("user_agreements")
                .insert(agreement)
                .execute()

        } catch {
            throw AgreementServiceError.networkError(error)
        }
    }
}

// MARK: - Supabase Record Types

/// Record type for reading from user_agreements table
private struct UserAgreementRecord: Codable {
    let id: UUID
    let userId: UUID
    let role: String
    let version: String
    let acceptedAt: Date
    let ipAddress: String?
    let userAgent: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case role
        case version
        case acceptedAt = "accepted_at"
        case ipAddress = "ip_address"
        case userAgent = "user_agent"
    }
}

/// Record type for inserting into user_agreements table
private struct UserAgreementInsert: Codable {
    let userId: UUID
    let role: String
    let version: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case role
        case version
    }
}
