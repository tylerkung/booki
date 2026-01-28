import SwiftUI

/// Auth gate view that controls access to the main app
/// Shows login/signup when unauthenticated and main app when authenticated
struct AuthGateView: View {

    // MARK: - Environment

    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var syncService: SyncService
    @EnvironmentObject private var realtimeService: RealtimeService
    @EnvironmentObject private var networkMonitor: NetworkMonitor

    // MARK: - State

    /// Tracks which auth view is currently displayed
    @State private var currentAuthView: AuthViewType = .login

    /// Whether to show the bookie error alert
    @State private var showBookieErrorAlert: Bool = false

    /// Tracks if initial sync has been triggered for this session
    @State private var hasTriggeredInitialSync: Bool = false

    // MARK: - Body

    var body: some View {
        Group {
            if authManager.isLoading || (authManager.isAuthenticated && authManager.isLoadingBookie) {
                loadingView
            } else if authManager.isAuthenticated {
                // Check if agreement is required for any authenticated user (bookie or player)
                if authManager.agreementRequired {
                    agreementView
                } else {
                    // Route based on user role
                    switch authManager.userRole {
                    case .player:
                        PlayerMainView()
                    case .bookie, nil:
                        ContentView()
                    }
                }
            } else {
                authFlowView
            }
        }
        .animation(.easeInOut(duration: 0.3), value: authManager.isAuthenticated)
        .animation(.easeInOut(duration: 0.2), value: authManager.isLoading)
        .animation(.easeInOut(duration: 0.2), value: authManager.isLoadingBookie)
        .onChange(of: authManager.bookieError) { _, newError in
            showBookieErrorAlert = newError != nil
        }
        .alert("Setup Issue", isPresented: $showBookieErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(authManager.bookieError ?? "An error occurred setting up your account. Some features may not work correctly.")
        }
        .onChange(of: authManager.currentBookieId) { _, newBookieId in
            // Trigger initial sync and realtime subscription when bookie ID becomes available
            if newBookieId != nil && !hasTriggeredInitialSync {
                hasTriggeredInitialSync = true
                Task {
                    // First sync all data
                    await syncService.sync()
                    // Then subscribe to realtime updates
                    await realtimeService.subscribe()
                }
            }
        }
        .onChange(of: authManager.isAuthenticated) { _, isAuthenticated in
            // Reset sync flag and unsubscribe from realtime when user logs out
            if !isAuthenticated {
                hasTriggeredInitialSync = false
                Task {
                    await realtimeService.unsubscribe()
                }
            }
        }
        // MARK: - Network Status Change Handler
        .onChange(of: networkMonitor.isConnected) { wasConnected, isConnected in
            // When connection is restored, trigger sync
            if !wasConnected && isConnected {
                // Connection restored
                syncService.setOnline()

                // Trigger sync if authenticated
                if authManager.currentBookieId != nil {
                    Task {
                        await syncService.sync()
                        // Reconnect realtime if needed
                        await realtimeService.reconnect()
                    }
                }
            } else if wasConnected && !isConnected {
                // Connection lost
                syncService.setOffline()
            }
        }
    }

    // MARK: - Agreement View

    /// Agreement view for users who need to accept terms (bookies or players)
    private var agreementView: some View {
        UserAgreementView(
            onAccept: {
                Task {
                    // Determine user ID and role based on current authentication state
                    let userId: UUID?
                    let role: String

                    switch authManager.userRole {
                    case .bookie:
                        userId = authManager.currentBookieId
                        role = "bookie"
                    case .player:
                        userId = authManager.currentPlayerId
                        role = "player"
                    case nil:
                        return
                    }

                    guard let userId = userId else { return }

                    do {
                        try await authManager.submitAgreement(for: userId, role: role)
                    } catch {
                        print("Failed to submit agreement: \(error)")
                    }
                }
            },
            message: authManager.agreementIsOutdated
                ? "We have updated our Terms of Service. Please review and accept to continue."
                : nil
        )
    }

    // MARK: - Loading View

    /// Loading view with app logo shown while checking auth state
    private var loadingView: some View {
        ZStack {
            Theme.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // App Logo
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(Theme.accent)

                Text("Booki")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.textPrimary)

                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: Theme.accent))
                    .scaleEffect(1.2)
                    .padding(.top, 16)
            }
        }
    }

    // MARK: - Auth Flow View

    /// Container for auth views with navigation between them
    private var authFlowView: some View {
        Group {
            switch currentAuthView {
            case .login:
                LoginView(
                    onNavigateToSignUp: { currentAuthView = .signUp },
                    onNavigateToForgotPassword: { currentAuthView = .forgotPassword },
                    onNavigateToPlayerClaim: { currentAuthView = .playerClaim }
                )
            case .signUp:
                SignUpView(
                    onNavigateToLogin: { currentAuthView = .login }
                )
            case .forgotPassword:
                ForgotPasswordView(
                    onNavigateToLogin: { currentAuthView = .login }
                )
            case .playerClaim:
                PlayerClaimView(
                    onNavigateToLogin: { currentAuthView = .login }
                )
            }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: currentAuthView)
    }
}

// MARK: - Auth View Type

/// Enum representing the different auth views
private enum AuthViewType {
    case login
    case signUp
    case forgotPassword
    case playerClaim
}

// MARK: - Preview

#Preview("Loading") {
    AuthGateView()
        .environmentObject(AuthManager())
        .environmentObject(SyncService())
        .environmentObject(RealtimeService())
        .environmentObject(NetworkMonitor())
}

#Preview("Login") {
    AuthGateView()
        .environmentObject(AuthManager())
        .environmentObject(SyncService())
        .environmentObject(RealtimeService())
        .environmentObject(NetworkMonitor())
}
