import Foundation
import Supabase

/// Error types for bookie service operations
enum BookieServiceError: Error, LocalizedError {
    case notAuthenticated
    case networkError(Error)
    case bookieNotFound
    case creationFailed(String)
    case unknownError

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User is not authenticated"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .bookieNotFound:
            return "Bookie record not found"
        case .creationFailed(let message):
            return "Failed to create bookie: \(message)"
        case .unknownError:
            return "An unknown error occurred"
        }
    }
}

/// Response type for bookie record from Supabase
struct BookieRecord: Codable {
    let id: UUID
    let authUserId: UUID
    let name: String
    let email: String?
    let subscriptionStatus: String
    let createdAt: Date
    let updatedAt: Date
    // Auto-pilot settings (US-008, US-009, US-010)
    let manualBetAcceptance: Bool?
    let manualBetGrading: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case authUserId = "auth_user_id"
        case name
        case email
        case subscriptionStatus = "subscription_status"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case manualBetAcceptance = "manual_bet_acceptance"
        case manualBetGrading = "manual_bet_grading"
    }
}

/// Update type for modifying auto-pilot settings
struct BookieSettingsUpdate: Codable {
    let manualBetAcceptance: Bool?
    let manualBetGrading: Bool?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case manualBetAcceptance = "manual_bet_acceptance"
        case manualBetGrading = "manual_bet_grading"
        case updatedAt = "updated_at"
    }
}

/// Insert type for creating a new bookie record
struct BookieInsert: Codable {
    let authUserId: UUID
    let name: String
    let email: String?

    enum CodingKeys: String, CodingKey {
        case authUserId = "auth_user_id"
        case name
        case email
    }
}

/// Service for managing bookie records in Supabase
/// Handles creation and retrieval of bookie records linked to auth users
enum BookieService {

    private static var supabase: SupabaseClient {
        SupabaseClientManager.shared.client
    }

    // MARK: - Fetch Bookie Record

    /// Fetches the bookie record for the current authenticated user
    /// - Returns: The bookie record if found
    /// - Throws: BookieServiceError if not found or network error
    static func fetchCurrentBookie() async throws -> BookieRecord {
        // Get current user
        guard let user = try? await supabase.auth.session.user else {
            throw BookieServiceError.notAuthenticated
        }

        return try await fetchBookie(forAuthUserId: user.id)
    }

    /// Fetches the bookie record for a specific auth user ID
    /// - Parameter authUserId: The auth user ID to look up
    /// - Returns: The bookie record if found
    /// - Throws: BookieServiceError if not found or network error
    static func fetchBookie(forAuthUserId authUserId: UUID) async throws -> BookieRecord {
        do {
            let response: [BookieRecord] = try await supabase
                .from("bookies")
                .select()
                .eq("auth_user_id", value: authUserId.uuidString)
                .limit(1)
                .execute()
                .value

            guard let bookie = response.first else {
                throw BookieServiceError.bookieNotFound
            }

            return bookie
        } catch let error as BookieServiceError {
            throw error
        } catch {
            throw BookieServiceError.networkError(error)
        }
    }

    // MARK: - Create Bookie Record

    /// Creates a new bookie record for the current authenticated user
    /// - Parameter name: The bookie's display name (optional, will use email prefix if nil)
    /// - Returns: The newly created bookie record
    /// - Throws: BookieServiceError if creation fails
    static func createBookie(name: String? = nil) async throws -> BookieRecord {
        // Get current user
        guard let user = try? await supabase.auth.session.user else {
            throw BookieServiceError.notAuthenticated
        }

        return try await createBookie(forAuthUserId: user.id, email: user.email, name: name)
    }

    /// Creates a new bookie record for a specific auth user
    /// - Parameters:
    ///   - authUserId: The auth user ID to link
    ///   - email: The user's email (used for deriving name if not provided)
    ///   - name: The bookie's display name (optional)
    /// - Returns: The newly created bookie record
    /// - Throws: BookieServiceError if creation fails
    static func createBookie(forAuthUserId authUserId: UUID, email: String?, name: String? = nil) async throws -> BookieRecord {
        // Derive name from email if not provided
        let bookieName = name ?? deriveNameFromEmail(email)

        let insert = BookieInsert(
            authUserId: authUserId,
            name: bookieName,
            email: email
        )

        do {
            let response: [BookieRecord] = try await supabase
                .from("bookies")
                .insert(insert)
                .select()
                .execute()
                .value

            guard let bookie = response.first else {
                throw BookieServiceError.creationFailed("No record returned after insert")
            }

            return bookie
        } catch let error as BookieServiceError {
            throw error
        } catch {
            throw BookieServiceError.networkError(error)
        }
    }

    // MARK: - Fetch or Create Bookie Record

    /// Fetches the existing bookie record or creates one if it doesn't exist
    /// This is the primary method to use after login/signup to ensure bookie record exists
    /// - Parameter name: The bookie's display name (used only if creating)
    /// - Returns: The existing or newly created bookie record
    /// - Throws: BookieServiceError if both fetch and create fail
    static func fetchOrCreateBookie(name: String? = nil) async throws -> BookieRecord {
        // Get current user
        guard let user = try? await supabase.auth.session.user else {
            throw BookieServiceError.notAuthenticated
        }

        // Try to fetch existing bookie record
        do {
            return try await fetchBookie(forAuthUserId: user.id)
        } catch BookieServiceError.bookieNotFound {
            // Bookie record doesn't exist, create one
            return try await createBookie(forAuthUserId: user.id, email: user.email, name: name)
        }
    }

    // MARK: - Update Bookie Settings

    /// Updates auto-pilot settings for the current bookie
    /// - Parameters:
    ///   - bookieId: The bookie ID to update
    ///   - manualBetAcceptance: Whether to require manual bet acceptance (nil = don't change)
    ///   - manualBetGrading: Whether to require manual bet grading (nil = don't change)
    /// - Throws: BookieServiceError if update fails
    static func updateSettings(
        bookieId: UUID,
        manualBetAcceptance: Bool? = nil,
        manualBetGrading: Bool? = nil
    ) async throws {
        let update = BookieSettingsUpdate(
            manualBetAcceptance: manualBetAcceptance,
            manualBetGrading: manualBetGrading,
            updatedAt: Date()
        )

        do {
            try await supabase
                .from("bookies")
                .update(update)
                .eq("id", value: bookieId.uuidString)
                .execute()
        } catch {
            throw BookieServiceError.networkError(error)
        }
    }

    // MARK: - Helpers

    /// Derives a display name from an email address
    /// Uses the part before @ as the name
    /// - Parameter email: The email address
    /// - Returns: Derived name or "Bookie" if email is nil/empty
    private static func deriveNameFromEmail(_ email: String?) -> String {
        guard let email = email, !email.isEmpty else {
            return "Bookie"
        }

        // Get the part before @
        if let atIndex = email.firstIndex(of: "@") {
            let prefix = String(email[..<atIndex])
            // Capitalize first letter
            return prefix.prefix(1).uppercased() + prefix.dropFirst()
        }

        return email
    }
}
