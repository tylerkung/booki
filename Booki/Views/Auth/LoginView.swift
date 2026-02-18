import SwiftUI
import Supabase

/// Login view for returning bookies to access their account
struct LoginView: View {

    // MARK: - Environment

    @EnvironmentObject private var authManager: AuthManager

    // MARK: - State

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    // MARK: - Validation

    private var isFormValid: Bool {
        !email.isEmpty && !password.isEmpty && email.contains("@")
    }

    // MARK: - Actions

    var onNavigateToSignUp: () -> Void = {}
    var onNavigateToForgotPassword: () -> Void = {}
    var onNavigateToPlayerClaim: () -> Void = {}

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header with Booki Logo
                VStack(spacing: 12) {
                    Image("BookiLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 200)

                    Text("Welcome Back")
                        .font(Theme.title1)
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.background)

                    Text("Log in to manage your book")
                        .font(Theme.subheadline)
                        .foregroundStyle(Theme.background.opacity(0.7))
                }
                .padding(.top, 40)
                .padding(.bottom, 20)

                // Form Fields
                VStack(spacing: 16) {
                    // Email Field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Email")
                            .font(Theme.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.background.opacity(0.8))

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
                    }

                    // Password Field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Password")
                            .font(Theme.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.background.opacity(0.8))

                        SecureField("", text: $password)
                            .textFieldStyle(AuthTextFieldStyle())
                            .textContentType(.password)
                            .placeholder(when: password.isEmpty) {
                                Text("Enter your password")
                                    .foregroundStyle(Theme.textMuted)
                            }
                    }

                    // Forgot Password Link
                    HStack {
                        Spacer()
                        Button(action: onNavigateToForgotPassword) {
                            Text("Forgot Password?")
                                .font(Theme.subheadline)
                                .foregroundStyle(Theme.background)
                        }
                    }
                }
                .padding(.horizontal, 24)

                // Error Message
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(Theme.subheadline)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Theme.danger.cornerRadius(Theme.cornerRadiusSmall))
                        .padding(.horizontal, 24)
                }

                // Log In Button
                Button(action: logIn) {
                    Group {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("Log In")
                                .fontWeight(.semibold)
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        (!isFormValid || isLoading) ? Theme.elevatedBackground : Theme.background
                    )
                    .cornerRadius(Theme.cornerRadiusSmall)
                }
                .disabled(!isFormValid || isLoading)
                .padding(.horizontal, 24)
                .padding(.top, 8)

                // Divider
                DividerWithText(text: "or")
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)

                // Sign in with Apple
                AppleSignInButton { error in
                    errorMessage = error
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 40)

                // Navigate to Sign Up
                HStack(spacing: 4) {
                    Text("Don't have an account?")
                        .foregroundStyle(Theme.background.opacity(0.7))

                    Button(action: onNavigateToSignUp) {
                        Text("Sign up")
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.background)
                    }
                }
                .font(Theme.subheadline)

                // Player Claim Link
                Button(action: onNavigateToPlayerClaim) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.badge.key")
                        Text("I'm a Player")
                            .fontWeight(.medium)
                    }
                    .font(Theme.subheadline)
                    .foregroundStyle(Theme.background.opacity(0.7))
                }
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(hex: 0x00F5D4).ignoresSafeArea())
    }

    // MARK: - Log In

    private func logIn() {
        guard isFormValid else { return }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                let _ = try await SupabaseClientManager.shared.client.auth.signIn(
                    email: email,
                    password: password
                )
                // AuthManager will update automatically via auth state listener
                await MainActor.run {
                    isLoading = false
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
        let message = error.localizedDescription.lowercased()

        if message.contains("invalid login credentials") || message.contains("invalid credentials") {
            return "Invalid email or password. Please try again."
        }
        if message.contains("email not confirmed") || message.contains("not confirmed") {
            return "Please verify your email address before logging in."
        }
        if message.contains("too many requests") || message.contains("rate limit") {
            return "Too many login attempts. Please try again later."
        }
        if message.contains("network") || message.contains("connection") {
            return "Network error. Please check your connection and try again."
        }

        return "Login failed. Please try again."
    }
}

// MARK: - Preview

#Preview {
    LoginView()
        .environmentObject(AuthManager())
}
