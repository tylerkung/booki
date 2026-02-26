import SwiftUI
@preconcurrency import Supabase

/// Sign up view for new bookies to create an account
struct SignUpView: View {

    // MARK: - Environment

    @Environment(AuthManager.self) private var authManager

    // MARK: - State

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var isLoading: Bool = false
    @State private var showVerificationPending: Bool = false
    @State private var errorMessage: String?
    @State private var ageConfirmed: Bool = false
    @State private var isResending: Bool = false
    @State private var resendMessage: String?

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
        password == confirmPassword &&
        ageConfirmed
    }

    // MARK: - Actions

    var onNavigateToLogin: () -> Void = {}

    // MARK: - Body

    var body: some View {
        if showVerificationPending {
            verificationPendingView
        } else {
            signUpFormView
        }
    }

    // MARK: - Verification Pending View

    private var verificationPendingView: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "envelope.badge")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.accent)

                Text("Check Your Inbox")
                    .font(Theme.title1)
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.textPrimary)

                Text("We sent a verification link to")
                    .font(Theme.subheadline)
                    .foregroundStyle(Theme.textSecondary)

                Text(email)
                    .font(Theme.bodyFont(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Text("Tap the link in the email to verify your account, then come back here to log in.")
                    .font(Theme.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 4)
            }

            Spacer()

            VStack(spacing: 12) {
                // Resend button
                Button {
                    resendVerification()
                } label: {
                    Group {
                        if isResending {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: Theme.accent))
                        } else {
                            Text("Resend Email")
                                .font(Theme.bodyFont(size: 15, weight: .medium))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }
                .disabled(isResending)

                if let resendMessage {
                    Text(resendMessage)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                }

                // Back to Login button
                Button(action: onNavigateToLogin) {
                    Text("Back to Login")
                        .font(Theme.headline)
                        .fontWeight(.bold)
                        .textCase(.uppercase)
                        .tracking(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 32)
        }
        .background(Theme.backgroundGradient)
    }

    // MARK: - Sign Up Form View

    private var signUpFormView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Image("BookiLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 180)
                        .shadow(color: Theme.accent.opacity(0.3), radius: 40, x: 0, y: 0)

                    Text("Create Account")
                        .font(Theme.title1)
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.textPrimary)

                    Text("Sign up to start managing your group")
                        .font(Theme.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.top, 56)
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
                            .textContentType(.oneTimeCode)
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
                            .textContentType(.oneTimeCode)
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

                // Age Confirmation
                Button {
                    ageConfirmed.toggle()
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: ageConfirmed ? "checkmark.square.fill" : "square")
                            .foregroundStyle(ageConfirmed ? Theme.accent : Theme.textMuted)
                            .font(.system(size: 20))

                        Text("I confirm that I am at least 18 years of age")
                            .font(Theme.bodyFont(size: 14))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.leading)
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
                                .tracking(1)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!isFormValid || isLoading)
                .padding(.horizontal, 24)
                .padding(.top, 8)

                Text("This app is designed for tracking and organizing private group activity. No real money is processed or transferred through Booki.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 12)

            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.backgroundGradient)
        .overlay(alignment: .topLeading) {
            Button(action: onNavigateToLogin) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .font(Theme.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
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
                    withAnimation { showVerificationPending = true }
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

    private func resendVerification() {
        isResending = true
        resendMessage = nil

        Task {
            do {
                try await SupabaseClientManager.shared.client.auth.resend(
                    email: email,
                    type: .signup
                )
                await MainActor.run {
                    isResending = false
                    resendMessage = "Verification email sent"
                }
            } catch {
                await MainActor.run {
                    isResending = false
                    resendMessage = "Failed to resend. Try again later."
                }
            }
        }
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
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
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
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
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
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview {
    SignUpView()
        .environment(AuthManager())
}
