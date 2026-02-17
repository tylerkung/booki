import SwiftUI
import AuthenticationServices
import Supabase

/// A Sign in with Apple button that integrates with Supabase authentication
/// Note: Requires "Sign in with Apple" capability to be added in Xcode project settings
/// and Apple provider to be configured in Supabase dashboard
struct AppleSignInButton: View {

    // MARK: - State

    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    // MARK: - Callbacks

    /// Called when an error occurs during sign in
    var onError: ((String) -> Void)?

    // MARK: - Body

    var body: some View {
        VStack(spacing: 8) {
            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: Theme.textPrimary))
                    .frame(height: 50)
                    .frame(maxWidth: .infinity)
                    .background(Color.black)
                    .cornerRadius(Theme.cornerRadiusSmall)
            } else {
                SignInWithAppleButton(.signIn) { request in
                    configureRequest(request)
                } onCompletion: { result in
                    handleCompletion(result)
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 50)
                .cornerRadius(Theme.cornerRadiusSmall)
            }

            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.danger)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Apple Sign-In Configuration

    /// Configures the Apple Sign-In request with required scopes
    private func configureRequest(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.email, .fullName]
    }

    // MARK: - Handle Completion

    /// Handles the Apple Sign-In completion result
    private func handleCompletion(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            handleAuthorization(authorization)
        case .failure(let error):
            handleError(error)
        }
    }

    /// Processes a successful Apple authorization
    private func handleAuthorization(_ authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            setError("Invalid credential type received")
            return
        }

        guard let identityToken = credential.identityToken,
              let idTokenString = String(data: identityToken, encoding: .utf8) else {
            setError("Unable to retrieve identity token")
            return
        }

        // Sign in with Supabase using the Apple ID token
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let _ = try await SupabaseClientManager.shared.client.auth.signInWithIdToken(
                    credentials: .init(
                        provider: .apple,
                        idToken: idTokenString
                    )
                )
                // AuthManager will update automatically via auth state listener
                await MainActor.run {
                    isLoading = false
                }
            } catch let error as AuthError {
                await MainActor.run {
                    isLoading = false
                    setError(mapAuthError(error))
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    setError("An unexpected error occurred. Please try again.")
                }
            }
        }
    }

    /// Handles errors from Apple Sign-In
    private func handleError(_ error: Error) {
        // Check if user cancelled the sign-in
        if let authError = error as? ASAuthorizationError {
            switch authError.code {
            case .canceled:
                // User cancelled - don't show error
                return
            case .failed:
                setError("Sign in with Apple failed. Please try again.")
            case .invalidResponse:
                setError("Invalid response from Apple. Please try again.")
            case .notHandled:
                setError("Sign in request was not handled. Please try again.")
            case .notInteractive:
                setError("Sign in requires user interaction.")
            case .unknown:
                setError("An unknown error occurred. Please try again.")
            case .matchedExcludedCredential, .credentialImport, .credentialExport:
                setError("Credential operation failed. Please try again.")
            @unknown default:
                setError("An unexpected error occurred. Please try again.")
            }
        } else {
            setError("Sign in with Apple failed. Please try again.")
        }
    }

    // MARK: - Error Handling

    /// Sets the error message and calls the error callback
    private func setError(_ message: String) {
        errorMessage = message
        onError?(message)
    }

    /// Maps Supabase auth errors to user-friendly messages
    private func mapAuthError(_ error: AuthError) -> String {
        let message = error.localizedDescription.lowercased()

        if message.contains("provider") || message.contains("apple") {
            return "Apple Sign-In is not configured. Please contact support."
        }
        if message.contains("token") {
            return "Authentication token is invalid. Please try again."
        }
        if message.contains("network") || message.contains("connection") {
            return "Network error. Please check your connection and try again."
        }

        return "Sign in failed. Please try again."
    }
}

// MARK: - Divider with Text

/// A horizontal divider with centered text, commonly used as "or" separator
struct DividerWithText: View {
    let text: String

    var body: some View {
        HStack(spacing: 16) {
            Rectangle()
                .fill(Theme.divider)
                .frame(height: 1)

            Text(text)
                .font(Theme.subheadline)
                .foregroundStyle(Theme.textMuted)

            Rectangle()
                .fill(Theme.divider)
                .frame(height: 1)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 24) {
        AppleSignInButton()

        DividerWithText(text: "or")

        Text("Other sign-in options")
            .foregroundStyle(Theme.textSecondary)
    }
    .padding(24)
    .background(Theme.backgroundGradient)
}
