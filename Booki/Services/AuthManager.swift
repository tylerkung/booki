import Foundation
import Observation
@preconcurrency import Supabase

/// Represents the user's role in the application
enum UserRole: String, Codable {
    case bookie
    case player
}

/// Response type for player record lookup from Supabase
private struct PlayerAuthRecord: Codable {
    let id: UUID
    let name: String
    let bookieId: UUID

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case bookieId = "bookie_id"
    }
}

/// Centralized auth state manager that tracks login status and current user
/// Provides a single source of truth for authentication state throughout the app
@MainActor
@Observable
final class AuthManager {

    // MARK: - Published Properties

    /// Whether the user is currently authenticated
    private(set) var isAuthenticated: Bool = false

    /// Whether auth state is being loaded/checked
    private(set) var isLoading: Bool = true

    /// The current user's ID (nil if not authenticated)
    private(set) var currentUserId: String?

    /// The current user's role (nil if not authenticated or role not set)
    private(set) var userRole: UserRole?

    /// The current bookie's ID from Supabase (nil if not authenticated as bookie)
    /// This is set after login/signup when the bookie record is fetched/created
    private(set) var currentBookieId: UUID?

    /// The current player's ID from Supabase players table (nil if not authenticated as player)
    /// This is the player.id, not the auth_user_id
    private(set) var currentPlayerId: UUID?

    /// Error message from bookie record operations (nil if no error)
    private(set) var bookieError: String?

    /// Whether bookie record is being loaded
    private(set) var isLoadingBookie: Bool = false

    /// Whether user agreement is required before accessing the app
    var agreementRequired: Bool = false

    /// Whether the agreement is outdated (true) vs never accepted (false)
    /// Used to display appropriate message to user
    private(set) var agreementIsOutdated: Bool = false

    // MARK: - Private Properties

    private let agreementService: AgreementService

    private let supabase: SupabaseClient
    nonisolated(unsafe) private var authStateTask: Task<Void, Never>?

    /// When true, the auth state listener skips ensureBookieRecord() on .signedIn events.
    /// Used during the player claim flow to prevent a race condition where signUp() triggers
    /// ensureBookieRecord() before claim_player has linked the auth account to the player record.
    var isClaimingPlayerAccount: Bool = false

    // MARK: - Initialization

    init() {
        self.supabase = SupabaseClientManager.shared.client
        self.agreementService = AgreementService()

        // Check current session on init
        Task {
            await checkCurrentSession()
            setupAuthStateListener()
        }
    }

    deinit {
        let task = authStateTask
        task?.cancel()
    }

    // MARK: - Public Methods

    /// Signs out the current user
    func signOut() async throws {
        try await supabase.auth.signOut()
        // Auth state listener will handle updating the published properties
    }

    /// Determines the user's role and fetches appropriate record
    /// Call this after successful login/signup to determine if user is bookie or player
    /// Priority: Check for player record first, then bookie record
    /// - Parameter name: Optional name to use when creating a new bookie record
    func ensureBookieRecord(name: String? = nil) async {
        isLoadingBookie = true
        bookieError = nil

        guard let userId = currentUserId, let authUserId = UUID(uuidString: userId) else {
            bookieError = "No authenticated user found"
            isLoadingBookie = false
            return
        }

        // First, check if this user has a player record (auth_user_id matches)
        // Players are linked via auth_user_id in the players table
        do {
            let playerRecord = try await fetchPlayerRecord(forAuthUserId: authUserId)
            // User is a player - set role, player ID, and bookie ID (for syncing)
            currentPlayerId = playerRecord.id
            currentBookieId = playerRecord.bookieId  // Players need their bookie's ID to sync data
            userRole = .player
            // Clean up spurious bookie record if user signed up before claiming invite
            // get_user_bookie_id() COALESCE checks bookies first, so a leftover bookie
            // record breaks RLS for the player account
            await cleanUpSpuriousBookieRecord(forAuthUserId: authUserId)
            // Check agreement status for player
            await checkAgreementRequired(for: authUserId)
            isLoadingBookie = false
            return
        } catch {
            // No player record found - continue to check for bookie record
            print("No player record found for auth user, checking bookie: \(error)")
        }

        // Second, try to find an existing bookie record for this user
        do {
            let bookie = try await BookieService.fetchCurrentBookie()
            currentBookieId = bookie.id
            currentPlayerId = nil
            userRole = .bookie
            // Check agreement status using auth user ID (not bookie record ID)
            await checkAgreementRequired(for: authUserId)
            isLoadingBookie = false
            return
        } catch {
            // No existing bookie record found - this is expected for new users
            // Continue to try creating one
        }

        // Try to create a bookie record (for new bookie signups)
        do {
            let bookie = try await BookieService.fetchOrCreateBookie(name: name)
            currentBookieId = bookie.id
            currentPlayerId = nil
            userRole = .bookie
            // Check agreement status using auth user ID (not bookie record ID)
            await checkAgreementRequired(for: authUserId)
        } catch {
            bookieError = error.localizedDescription
            print("Failed to determine user role: \(error)")
        }

        isLoadingBookie = false
    }

    /// Removes any bookie record owned by this auth user.
    /// This handles the case where a user signed up as bookie first, then claimed
    /// a player invite. The leftover bookie record breaks get_user_bookie_id() COALESCE.
    private func cleanUpSpuriousBookieRecord(forAuthUserId authUserId: UUID) async {
        do {
            try await supabase
                .from("bookies")
                .delete()
                .eq("auth_user_id", value: authUserId.uuidString)
                .execute()
            print("Cleaned up spurious bookie record for player \(authUserId)")
        } catch {
            // Non-blocking — if no bookie record exists, delete is a no-op
            print("No spurious bookie record to clean up (or error): \(error)")
        }
    }

    /// Fetches a player record from Supabase by auth_user_id
    /// - Parameter authUserId: The authenticated user's UUID
    /// - Returns: The player record if found
    /// - Throws: Error if no player record exists or network error
    private func fetchPlayerRecord(forAuthUserId authUserId: UUID) async throws -> PlayerAuthRecord {
        let response: [PlayerAuthRecord] = try await supabase
            .from("players")
            .select("id, name, bookie_id")
            .eq("auth_user_id", value: authUserId.uuidString)
            .limit(1)
            .execute()
            .value

        guard let player = response.first else {
            throw NSError(domain: "AuthManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "No player record found"])
        }

        return player
    }

    /// Sets the current user as a player
    /// Called when a player successfully claims their account
    /// - Parameter playerId: The player's record UUID (from players table)
    /// - Parameter bookieId: The player's bookie's ID (needed for syncing)
    /// - Parameter authUserId: The player's auth user UUID (for agreement check)
    /// - Parameter checkAgreement: Whether to check agreement status (default true)
    func setAsPlayer(playerId: UUID, bookieId: UUID, authUserId: UUID, checkAgreement: Bool = true) {
        currentPlayerId = playerId
        currentBookieId = bookieId  // Players need their bookie's ID to sync data
        userRole = .player

        // Check agreement status for players on app launch
        if checkAgreement {
            Task {
                await checkAgreementRequired(for: authUserId)
            }
        }
    }

    /// Completes the player claim flow by signing in fresh with confirmed credentials.
    /// The signUp session JWT is invalid (email was unconfirmed at creation time).
    /// claim_player auto-confirmed the email, so a fresh signIn produces a valid JWT.
    func completePlayerClaimFlow(email: String, password: String) async {
        // Keep flag true during sign-out/sign-in so the auth state listener
        // doesn't trigger ensureBookieRecord() concurrently
        do {
            try? await supabase.auth.signOut()
            let session = try await supabase.auth.signIn(email: email, password: password)
            isClaimingPlayerAccount = false
            updateAuthState(userId: session.user.id.uuidString, isAuthenticated: true)
            await ensureBookieRecord()
        } catch {
            isClaimingPlayerAccount = false
            print("Failed to complete player claim flow: \(error)")
            updateAuthState(userId: nil, isAuthenticated: false)
        }
    }

    /// Sets the current bookie ID directly (used when bookie record is already known)
    func setCurrentBookieId(_ bookieId: UUID) {
        currentBookieId = bookieId
        userRole = .bookie
    }

    /// Check if user agreement is required and update agreementRequired flag
    /// - Parameter userId: The user's UUID
    func checkAgreementRequired(for userId: UUID) async {
        do {
            let status = try await agreementService.checkAgreementStatus(userId: userId)
            agreementRequired = (status == .required || status == .outdated)
            agreementIsOutdated = (status == .outdated)
        } catch {
            // On error, don't block the user - agreement check will happen on next launch
            print("Failed to check agreement status: \(error)")
            agreementRequired = false
            agreementIsOutdated = false
        }
    }

    /// Submit agreement acceptance for a user
    /// - Parameters:
    ///   - userId: The user's UUID
    ///   - role: The user's role (bookie or player)
    func submitAgreement(for userId: UUID, role: String) async throws {
        try await agreementService.submitAgreement(
            userId: userId,
            role: role,
            version: AgreementService.currentAgreementVersion
        )
        agreementRequired = false
        agreementIsOutdated = false
    }

    // MARK: - Private Methods

    /// Checks the current Supabase session on initialization
    private func checkCurrentSession() async {
        isLoading = true

        do {
            let session = try await supabase.auth.session
            updateAuthState(userId: session.user.id.uuidString, isAuthenticated: true)
            // Fetch bookie record for existing session
            await ensureBookieRecord()
        } catch {
            // No valid session or error checking session
            updateAuthState(userId: nil, isAuthenticated: false)
        }

        isLoading = false
    }

    /// Sets up the auth state change listener
    private func setupAuthStateListener() {
        authStateTask = Task {
            for await (event, session) in supabase.auth.authStateChanges {
                guard !Task.isCancelled else { return }

                switch event {
                case .initialSession:
                    // Already handled in checkCurrentSession
                    break
                case .signedIn:
                    if let session = session {
                        // During player claim flow, skip ALL auth state updates.
                        // signUp() fires .signedIn but we must keep isAuthenticated=false
                        // so AuthGateView keeps showing InviteClaimView (not the bookie dashboard).
                        // The claim flow signs out when done; the player logs in fresh afterward.
                        if isClaimingPlayerAccount {
                            break
                        }
                        updateAuthState(userId: session.user.id.uuidString, isAuthenticated: true)
                        await ensureBookieRecord()
                    }
                case .signedOut:
                    updateAuthState(userId: nil, isAuthenticated: false)
                case .tokenRefreshed:
                    // Token refreshed, keep current state
                    break
                case .userUpdated:
                    // User data updated, keep current state
                    break
                case .userDeleted:
                    updateAuthState(userId: nil, isAuthenticated: false)
                case .passwordRecovery:
                    // Password recovery flow initiated
                    break
                case .mfaChallengeVerified:
                    // MFA verified
                    break
                }
            }
        }
    }

    /// Updates the auth state properties
    private func updateAuthState(userId: String?, isAuthenticated: Bool) {
        self.currentUserId = userId
        self.isAuthenticated = isAuthenticated

        if !isAuthenticated {
            self.userRole = nil
            self.currentBookieId = nil
            self.currentPlayerId = nil
            self.bookieError = nil
            self.agreementRequired = false
            self.agreementIsOutdated = false
        }
    }
}
