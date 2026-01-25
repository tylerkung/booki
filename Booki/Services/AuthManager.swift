import Foundation
import Supabase

/// Represents the user's role in the application
enum UserRole: String, Codable {
    case bookie
    case player
}

/// Centralized auth state manager that tracks login status and current user
/// Provides a single source of truth for authentication state throughout the app
@MainActor
final class AuthManager: ObservableObject {

    // MARK: - Published Properties

    /// Whether the user is currently authenticated
    @Published private(set) var isAuthenticated: Bool = false

    /// Whether auth state is being loaded/checked
    @Published private(set) var isLoading: Bool = true

    /// The current user's ID (nil if not authenticated)
    @Published private(set) var currentUserId: String?

    /// The current user's role (nil if not authenticated or role not set)
    @Published private(set) var userRole: UserRole?

    /// The current bookie's ID from Supabase (nil if not authenticated as bookie)
    /// This is set after login/signup when the bookie record is fetched/created
    @Published private(set) var currentBookieId: UUID?

    /// The current player's auth user ID (nil if not authenticated as player)
    /// This links to player.authUserId in SwiftData
    @Published private(set) var currentPlayerId: UUID?

    /// Error message from bookie record operations (nil if no error)
    @Published private(set) var bookieError: String?

    /// Whether bookie record is being loaded
    @Published private(set) var isLoadingBookie: Bool = false

    // MARK: - Private Properties

    private let supabase: SupabaseClient
    private var authStateTask: Task<Void, Never>?

    // MARK: - Initialization

    init() {
        self.supabase = SupabaseClientManager.shared.client

        // Check current session on init
        Task {
            await checkCurrentSession()
            setupAuthStateListener()
        }
    }

    deinit {
        authStateTask?.cancel()
    }

    // MARK: - Public Methods

    /// Signs out the current user
    func signOut() async throws {
        try await supabase.auth.signOut()
        // Auth state listener will handle updating the published properties
    }

    /// Determines the user's role and fetches appropriate record
    /// Call this after successful login/signup to determine if user is bookie or player
    /// - Parameter name: Optional name to use when creating a new bookie record
    func ensureBookieRecord(name: String? = nil) async {
        isLoadingBookie = true
        bookieError = nil

        // First, try to find an existing bookie record for this user
        do {
            let bookie = try await BookieService.fetchCurrentBookie()
            currentBookieId = bookie.id
            currentPlayerId = nil
            userRole = .bookie
            isLoadingBookie = false
            return
        } catch {
            // No existing bookie record found - this is expected for new users or players
            // Continue to try creating one or checking if they're a player
        }

        // Try to create a bookie record (for new bookie signups)
        do {
            let bookie = try await BookieService.fetchOrCreateBookie(name: name)
            currentBookieId = bookie.id
            currentPlayerId = nil
            userRole = .bookie
        } catch {
            // If we can't create/fetch bookie record, user might be a player
            // Set as player role - the app will check if they have a valid player record
            if let userId = currentUserId, let uuid = UUID(uuidString: userId) {
                currentPlayerId = uuid
                currentBookieId = nil
                userRole = .player
            } else {
                bookieError = error.localizedDescription
                print("Failed to determine user role: \(error)")
            }
        }

        isLoadingBookie = false
    }

    /// Sets the current user as a player
    /// Called when a player successfully claims their account
    func setAsPlayer(authUserId: UUID) {
        currentPlayerId = authUserId
        currentBookieId = nil
        userRole = .player
    }

    /// Sets the current bookie ID directly (used when bookie record is already known)
    func setCurrentBookieId(_ bookieId: UUID) {
        currentBookieId = bookieId
        userRole = .bookie
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
                        updateAuthState(userId: session.user.id.uuidString, isAuthenticated: true)
                        // Fetch or create bookie record after sign in
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
        }
    }
}
