import SwiftUI

/// Auth gate view that controls access to the main app
/// Shows login/signup when unauthenticated and main app when authenticated
struct AuthGateView: View {

    // MARK: - Environment

    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var syncService: SyncService

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
                ContentView()
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
            // Trigger initial sync when bookie ID becomes available
            if newBookieId != nil && !hasTriggeredInitialSync {
                hasTriggeredInitialSync = true
                Task {
                    await syncService.sync()
                }
            }
        }
        .onChange(of: authManager.isAuthenticated) { _, isAuthenticated in
            // Reset sync flag when user logs out
            if !isAuthenticated {
                hasTriggeredInitialSync = false
            }
        }
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
                    onNavigateToForgotPassword: { currentAuthView = .forgotPassword }
                )
            case .signUp:
                SignUpView(
                    onNavigateToLogin: { currentAuthView = .login }
                )
            case .forgotPassword:
                ForgotPasswordView(
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
}

// MARK: - Preview

#Preview("Loading") {
    AuthGateView()
        .environmentObject(AuthManager())
        .environmentObject(SyncService())
}

#Preview("Login") {
    AuthGateView()
        .environmentObject(AuthManager())
        .environmentObject(SyncService())
}
