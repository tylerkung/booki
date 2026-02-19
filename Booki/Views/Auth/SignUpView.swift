import SwiftUI
import Supabase

/// Sign up view for new bookies to create an account
struct SignUpView: View {

    // MARK: - Environment

    @EnvironmentObject private var authManager: AuthManager

    // MARK: - State

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var isLoading: Bool = false
    @State private var showSuccessAlert: Bool = false
    @State private var errorMessage: String?

    // MARK: - Validation

    private var emailError: String? {
        guard !email.isEmpty else { return nil }
        return email.contains("@") ? nil : "Please enter a valid email address"
    }

    private var passwordError: String? {
        guard !password.isEmpty else { return nil }
        return password.count >= 8 ? nil : "Password must be at least 8 characters"
    }

    private var confirmPasswordError: String? {
        guard !confirmPassword.isEmpty else { return nil }
        return password == confirmPassword ? nil : "Passwords do not match"
    }

    private var isFormValid: Bool {
        !email.isEmpty &&
        !password.isEmpty &&
        !confirmPassword.isEmpty &&
        email.contains("@") &&
        password.count >= 8 &&
        password == confirmPassword
    }

    // MARK: - Actions

    var onNavigateToLogin: () -> Void = {}

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "person.badge.plus")
                        .font(Theme.font(size: 60))
                        .foregroundStyle(Theme.accent)

                    Text("Create Account")
                        .font(Theme.title1)
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.textPrimary)

                    Text("Sign up to start managing your book")
                        .font(Theme.subheadline)
                        .foregroundStyle(Theme.textSecondary)
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
                                .font(Theme.caption)
                                .foregroundStyle(Theme.danger)
                        }
                    }

                    // Password Field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Password")
                            .font(Theme.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.textSecondary)

                        SecureField("", text: $password)
                            .textFieldStyle(AuthTextFieldStyle())
                            .textContentType(.newPassword)
                            .placeholder(when: password.isEmpty) {
                                Text("Enter your password")
                                    .foregroundStyle(Theme.textMuted)
                            }

                        if let error = passwordError {
                            Text(error)
                                .font(Theme.caption)
                                .foregroundStyle(Theme.danger)
                        }
                    }

                    // Confirm Password Field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Confirm Password")
                            .font(Theme.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.textSecondary)

                        SecureField("", text: $confirmPassword)
                            .textFieldStyle(AuthTextFieldStyle())
                            .textContentType(.newPassword)
                            .placeholder(when: confirmPassword.isEmpty) {
                                Text("Confirm your password")
                                    .foregroundStyle(Theme.textMuted)
                            }

                        if let error = confirmPasswordError {
                            Text(error)
                                .font(Theme.caption)
                                .foregroundStyle(Theme.danger)
                        }
                    }
                }
                .padding(.horizontal, 24)

                // Error Message
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(Theme.subheadline)
                        .foregroundStyle(Theme.danger)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                // Create Account Button
                Button(action: signUp) {
                    Group {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: Theme.background))
                        } else {
                            Text("Create Account")
                                .font(Theme.headline)
                                .fontWeight(.bold)
                                .textCase(.uppercase)
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

                // Back button
                Button(action: onNavigateToLogin) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(Theme.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.textSecondary)
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
            Text("Check your email to verify your account")
        }
    }

    // MARK: - Sign Up

    private func signUp() {
        guard isFormValid else { return }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                let _ = try await SupabaseClientManager.shared.client.auth.signUp(
                    email: email,
                    password: password
                )
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
        let message = error.localizedDescription.lowercased()

        if message.contains("already registered") || message.contains("already exists") {
            return "This email is already registered. Please log in instead."
        }
        if message.contains("weak password") || message.contains("password") && message.contains("invalid") {
            return "Please choose a stronger password."
        }
        if message.contains("invalid email") {
            return "Please enter a valid email address."
        }
        if message.contains("network") || message.contains("connection") {
            return "Network error. Please check your connection and try again."
        }

        return "Sign up failed. Please try again."
    }
}

// MARK: - Text Field Style

struct AuthTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Theme.cardBackground)
            .foregroundStyle(Theme.textPrimary)
            .cornerRadius(Theme.cornerRadiusSmall)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall)
                    .stroke(Theme.border, lineWidth: 1)
            )
    }
}

// MARK: - Primary Button Style

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? Theme.background : Theme.textMuted)
            .background(
                Group {
                    if isEnabled {
                        Theme.buttonGradient
                    } else {
                        Theme.elevatedBackground
                    }
                }
            )
            .cornerRadius(Theme.cornerRadiusSmall)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Destructive Button Style

struct DestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? .white : Theme.textMuted)
            .background(isEnabled ? Theme.danger : Theme.elevatedBackground)
            .cornerRadius(Theme.cornerRadiusSmall)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview {
    SignUpView()
        .environmentObject(AuthManager())
}
