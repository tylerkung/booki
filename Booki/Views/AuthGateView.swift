import SwiftUI

/// Auth gate view that controls access to the main app
/// Shows login/signup when unauthenticated and main app when authenticated
struct AuthGateView: View {

    // MARK: - Environment

    @Environment(AuthManager.self) private var authManager
    @Environment(SyncService.self) private var syncService
    @Environment(RealtimeService.self) private var realtimeService
    @Environment(NetworkMonitor.self) private var networkMonitor

    // MARK: - State

    /// Tracks which auth view is currently displayed
    @State private var currentAuthView: AuthViewType = .login

    /// Whether to show the bookie error alert
    @State private var showBookieErrorAlert: Bool = false

    /// Tracks if initial sync has been triggered for this session
    @State private var hasTriggeredInitialSync: Bool = false

    /// Whether to show the onboarding flow
    @State private var showOnboarding: Bool = false

    /// Onboarding manager for tracking setup progress
    @State private var onboardingManager = OnboardingManager()

    /// Scene phase for detecting app foreground/background
    @Environment(\.scenePhase) private var scenePhase

    // MARK: - Splash Animation State

    @State private var splashLogoScale: CGFloat = 0.7
    @State private var splashLogoOpacity: Double = 0
    @State private var splashSpinnerOpacity: Double = 0

    // MARK: - Body

    var body: some View {
        ZStack {
            if authManager.isLoading || (authManager.isAuthenticated && authManager.isLoadingBookie) {
                loadingView
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
            } else if authManager.isAuthenticated {
                // Check if agreement is required for any authenticated user (bookie or player)
                if authManager.agreementRequired {
                    agreementView
                        .transition(.opacity)
                } else {
                    // Route based on user role
                    switch authManager.userRole {
                    case .player:
                        PlayerMainView()
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    case .bookie, nil:
                        ContentView()
                            .environment(onboardingManager)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
            } else {
                authFlowView
                    .transition(.opacity)
            }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingContainerView(
                onboardingManager: onboardingManager,
                onComplete: { showOnboarding = false },
                onSkip: { showOnboarding = false }
            )
        }
        .onChange(of: authManager.userRole) { _, newRole in
            // Show onboarding for new bookies who haven't completed it
            if newRole == .bookie && !onboardingManager.isOnboardingComplete {
                showOnboarding = true
            }
        }
        .onAppear {
            // Check if we should show onboarding on initial load
            if authManager.userRole == .bookie && !onboardingManager.isOnboardingComplete {
                showOnboarding = true
            }
        }
        .animation(.easeInOut(duration: 0.5), value: authManager.isAuthenticated)
        .animation(.easeInOut(duration: 0.4), value: authManager.isLoading)
        .animation(.easeInOut(duration: 0.4), value: authManager.isLoadingBookie)
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
        .onChange(of: authManager.currentPlayerId) { _, newPlayerId in
            // Sync data when a player logs in (uses their bookie's ID for sync)
            if newPlayerId != nil, authManager.userRole == .player && !hasTriggeredInitialSync {
                hasTriggeredInitialSync = true
                Task {
                    // Players use the regular sync flow - their bookie_id is set in currentBookieId
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
        // MARK: - Foreground Sync Handler
        .onChange(of: scenePhase) { oldPhase, newPhase in
            // Sync when app comes to foreground (active)
            if newPhase == .active && oldPhase != .active {
                // Only sync if authenticated and has bookie ID
                if authManager.currentBookieId != nil {
                    Task {
                        print("DEBUG: App became active - triggering sync")
                        await syncService.sync()
                    }
                }
            }
        }
    }

    // MARK: - Agreement View

    /// Agreement view for users who need to accept terms (bookies or players)
    private var agreementView: some View {
        UserAgreementView(
            onAccept: {
                Task {
                    // Use auth user ID for agreements (not record IDs)
                    guard let userIdString = authManager.currentUserId,
                          let userId = UUID(uuidString: userIdString) else {
                        print("Failed to submit agreement: No auth user ID")
                        return
                    }

                    let role: String
                    switch authManager.userRole {
                    case .bookie:
                        role = "bookie"
                    case .player:
                        role = "player"
                    case nil:
                        return
                    }

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
                // App Logo with accent glow
                Image("BookiLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180)
                    .shadow(color: Theme.accent.opacity(0.3), radius: 40, x: 0, y: 0)
                    .scaleEffect(splashLogoScale)
                    .opacity(splashLogoOpacity)

                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: Theme.accent))
                    .scaleEffect(1.2)
                    .padding(.top, 16)
                    .opacity(splashSpinnerOpacity)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                splashLogoScale = 1.0
                splashLogoOpacity = 1.0
            }
            withAnimation(.easeInOut(duration: 0.3).delay(0.4)) {
                splashSpinnerOpacity = 1.0
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
        .environment(AuthManager())
        .environment(SyncService())
        .environment(RealtimeService())
        .environment(NetworkMonitor())
}

#Preview("Login") {
    AuthGateView()
        .environment(AuthManager())
        .environment(SyncService())
        .environment(RealtimeService())
        .environment(NetworkMonitor())
}
