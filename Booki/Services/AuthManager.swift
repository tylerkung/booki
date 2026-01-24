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

    // MARK: - Private Methods

    /// Checks the current Supabase session on initialization
    private func checkCurrentSession() async {
        isLoading = true

        do {
            let session = try await supabase.auth.session
            updateAuthState(userId: session.user.id.uuidString, isAuthenticated: true)
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
        }
    }
}
