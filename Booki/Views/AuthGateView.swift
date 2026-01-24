import SwiftUI

/// Auth gate view that controls access to the main app
/// Shows login/signup when unauthenticated and main app when authenticated
struct AuthGateView: View {

    // MARK: - Environment

    @EnvironmentObject private var authManager: AuthManager

    // MARK: - State

    /// Tracks which auth view is currently displayed
    @State private var currentAuthView: AuthViewType = .login

    // MARK: - Body

    var body: some View {
        Group {
            if authManager.isLoading {
                loadingView
            } else if authManager.isAuthenticated {
                ContentView()
            } else {
                authFlowView
            }
        }
        .animation(.easeInOut(duration: 0.3), value: authManager.isAuthenticated)
        .animation(.easeInOut(duration: 0.2), value: authManager.isLoading)
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
}

#Preview("Login") {
    AuthGateView()
        .environmentObject(AuthManager())
}
