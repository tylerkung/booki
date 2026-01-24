import SwiftUI
import Supabase

/// Forgot password view for users to reset their password via email
struct ForgotPasswordView: View {

    // MARK: - Environment

    @EnvironmentObject private var authManager: AuthManager

    // MARK: - State

    @State private var email: String = ""
    @State private var isLoading: Bool = false
    @State private var showSuccessAlert: Bool = false
    @State private var errorMessage: String?

    // MARK: - Validation

    private var emailError: String? {
        guard !email.isEmpty else { return nil }
        return email.contains("@") ? nil : "Please enter a valid email address"
    }

    private var isFormValid: Bool {
        !email.isEmpty && email.contains("@")
    }

    // MARK: - Actions

    var onNavigateToLogin: () -> Void = {}

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "lock.rotation")
                        .font(.system(size: 60))
                        .foregroundStyle(Theme.accent)

                    Text("Reset Password")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.textPrimary)

                    Text("Enter your email to receive a reset link")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)
                .padding(.bottom, 20)

                // Form Fields
                VStack(spacing: 16) {
                    // Email Field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Email")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.textSecondary)

                        TextField("", text: $email)
                            .textFieldStyle(AuthTextFieldStyle())
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .placeholder(when: email.isEmpty) {
                                Text("Enter your email")
                                    .foregroundStyle(Theme.textMuted)
                            }

                        if let error = emailError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(Theme.danger)
                        }
                    }
                }
                .padding(.horizontal, 24)

                // Error Message
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(Theme.danger)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                // Send Reset Link Button
                Button(action: sendResetLink) {
                    Group {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: Theme.background))
                        } else {
                            Text("Send Reset Link")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!isFormValid || isLoading)
                .padding(.horizontal, 24)
                .padding(.top, 8)

                Spacer(minLength: 40)

                // Navigate back to Login
                Button(action: onNavigateToLogin) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back to Login")
                    }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.accent)
                }
                .padding(.bottom, 24)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.backgroundGradient)
        .alert("Check Your Email", isPresented: $showSuccessAlert) {
            Button("OK", role: .cancel) {
                onNavigateToLogin()
            }
        } message: {
            Text("Check your email for a reset link")
        }
    }

    // MARK: - Send Reset Link

    private func sendResetLink() {
        guard isFormValid else { return }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                try await SupabaseClientManager.shared.client.auth.resetPasswordForEmail(email)
                await MainActor.run {
                    isLoading = false
                    showSuccessAlert = true
                }
            } catch let error as AuthError {
                await MainActor.run {
                    isLoading = false
                    errorMessage = mapAuthError(error)
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = "An unexpected error occurred. Please try again."
                }
            }
        }
    }

    /// Maps Supabase auth errors to user-friendly messages
    private func mapAuthError(_ error: AuthError) -> String {
        switch error {
        case .api(let apiError):
            // Check for common error codes
            if let message = apiError.message?.lowercased() {
                if message.contains("not found") || message.contains("no user") {
                    return "No account found with this email address."
                }
                if message.contains("too many requests") || message.contains("rate limit") {
                    return "Too many requests. Please try again later."
                }
            }
            return apiError.message ?? "Unable to send reset link. Please try again."
        default:
            return "Network error. Please check your connection and try again."
        }
    }
}

// MARK: - Preview

#Preview {
    ForgotPasswordView()
        .environmentObject(AuthManager())
}
