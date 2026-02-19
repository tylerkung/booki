import SwiftUI
import Supabase

/// Welcome landing screen — the first thing users see
struct LoginView: View {

    // MARK: - Environment

    @EnvironmentObject private var authManager: AuthManager

    // MARK: - State

    @State private var showSignIn: Bool = false
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
        if showSignIn {
            signInView
        } else {
            welcomeView
        }
    }

    // MARK: - Welcome Screen

    private var welcomeView: some View {
        VStack(spacing: 0) {
            Spacer()

            // Hero section
            VStack(spacing: 20) {
                Image("BookiLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 300)

                Text("Your edge starts here.")
                    .font(Theme.title1)
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.background)

                Text("Run your group. Track the action. Stay organized.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.background.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()

            // CTAs
            VStack(spacing: 20) {
                // GET STARTED button
                Button {
                    onNavigateToSignUp()
                } label: {
                    Text("Get Started")
                        .font(Theme.headline)
                        .fontWeight(.bold)
                        .textCase(.uppercase)
                        .tracking(1)
                        .foregroundStyle(Color(hex: 0x00F5D4))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Theme.background)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 24)

                // I have an invite (player claim)
                Button(action: onNavigateToPlayerClaim) {
                    HStack(spacing: 6) {
                        Image(systemName: "ticket.fill")
                        Text("I have an invite code")
                            .fontWeight(.medium)
                    }
                    .font(Theme.subheadline)
                    .foregroundStyle(Theme.background.opacity(0.8))
                }

                // Already have an account
                HStack(spacing: 4) {
                    Text("I already have an account.")
                        .foregroundStyle(Theme.background.opacity(0.6))

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showSignIn = true
                        }
                    } label: {
                        Text("Sign in")
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.background)
                            .underline()
                    }
                }
                .font(Theme.subheadline)
                .padding(.bottom, 16)

                Text("This app is designed for tracking and organizing private group activity. Booki does not process payments or facilitate gambling.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)
            }
        }
        .background(Color(hex: 0x00F5D4).ignoresSafeArea())
    }

    // MARK: - Sign In View

    private var signInView: some View {
        VStack(spacing: 0) {
            // Back button at top-left
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showSignIn = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(Theme.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.background.opacity(0.7))
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            Spacer()

            // Header with logo
            VStack(spacing: 12) {
                Image("BookiLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200)

                Text("Welcome Back")
                    .font(Theme.title1)
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.background)
            }
            .padding(.bottom, 24)

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
                    .padding(.top, 12)
            }

            // Log In Button
            Button(action: logIn) {
                Group {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text("Log In")
                            .font(Theme.headline)
                            .fontWeight(.bold)
                            .textCase(.uppercase)
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
            .padding(.top, 20)

            Spacer()
        }
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
