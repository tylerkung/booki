import SwiftUI
@preconcurrency import Supabase

/// Welcome landing screen — the first thing users see
struct LoginView: View {

    // MARK: - Environment

    @Environment(AuthManager.self) private var authManager

    // MARK: - State

    @State private var showSignIn: Bool = false
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    // Welcome animation state
    @State private var logoOpacity: Double = 0
    @State private var logoScale: CGFloat = 0.85
    @State private var headlineOpacity: Double = 0
    @State private var headlineOffset: CGFloat = 12
    @State private var featuresOpacity: Double = 0
    @State private var ctaOpacity: Double = 0
    @State private var ctaOffset: CGFloat = 20

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
            VStack(spacing: 28) {
                // Logo with accent glow
                Image("BookiLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180)
                    .shadow(color: Theme.accent.opacity(0.3), radius: 40, x: 0, y: 0)
                    .opacity(logoOpacity)
                    .scaleEffect(logoScale)

                // Headline
                VStack(spacing: 8) {
                    Text("Your edge starts here.")
                        .font(Theme.font(size: 30, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)

                    Text("Run your group. Track the action.")
                        .font(Theme.bodyFont(size: 16))
                        .foregroundStyle(Theme.textSecondary)
                }
                .multilineTextAlignment(.center)
                .opacity(headlineOpacity)
                .offset(y: headlineOffset)
            }

            Spacer()
                .frame(height: 48)

            // Feature pills
            VStack(spacing: 12) {
                featurePill(icon: "person.3.fill", text: "Manage your group")
                featurePill(icon: "chart.bar.fill", text: "Track every pick")
                featurePill(icon: "arrow.triangle.2.circlepath", text: "Reconcile weekly")
            }
            .opacity(featuresOpacity)

            Spacer()

            // CTAs
            VStack(spacing: 16) {
                // GET STARTED button — primary CTA with gradient
                Button(action: onNavigateToSignUp) {
                    Text("Get Started")
                        .font(Theme.headline)
                        .fontWeight(.bold)
                        .textCase(.uppercase)
                        .tracking(1)
                        .foregroundStyle(Theme.background)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Theme.buttonGradient)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
                }
                .padding(.horizontal, 24)

                // Invite code link
                Button(action: onNavigateToPlayerClaim) {
                    HStack(spacing: 6) {
                        Image(systemName: "ticket.fill")
                        Text("I have an invite code")
                            .fontWeight(.medium)
                    }
                    .font(Theme.subheadline)
                    .foregroundStyle(Theme.accent)
                }

                // Sign in link
                HStack(spacing: 4) {
                    Text("Already have an account?")
                        .foregroundStyle(Theme.textMuted)
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showSignIn = true
                        }
                    } label: {
                        Text("Sign in")
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
                .font(Theme.subheadline)

                // Disclaimer
                Text("This app is designed for tracking and organizing private group activity. No real money is processed or transferred through Booki.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)
            }
            .opacity(ctaOpacity)
            .offset(y: ctaOffset)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .onAppear { runEntrance() }
    }

    // MARK: - Feature Pill

    private func featurePill(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(Theme.bodyFont(size: 14))
                .foregroundStyle(Theme.accent)
                .frame(width: 20)
            Text(text)
                .font(Theme.bodyFont(size: 14, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Theme.cardBackground)
                .overlay(Capsule().stroke(Theme.border, lineWidth: 0.5))
        )
    }

    // MARK: - Entrance Animation

    private func runEntrance() {
        withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) {
            logoOpacity = 1
            logoScale = 1
        }
        withAnimation(.easeOut(duration: 0.5).delay(0.2)) {
            headlineOpacity = 1
            headlineOffset = 0
        }
        withAnimation(.easeOut(duration: 0.4).delay(0.4)) {
            featuresOpacity = 1
        }
        withAnimation(.easeOut(duration: 0.5).delay(0.5)) {
            ctaOpacity = 1
            ctaOffset = 0
        }
    }

    // MARK: - Sign In View

    private var signInView: some View {
        VStack(spacing: 0) {
            // Back button
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showSignIn = false
                        errorMessage = nil
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(Theme.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            Spacer()

            // Header
            VStack(spacing: 12) {
                Image("BookiLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180)
                    .shadow(color: Theme.accent.opacity(0.3), radius: 40, x: 0, y: 0)

                Text("Welcome Back")
                    .font(Theme.title1)
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.bottom, 32)

            // Form
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Email")
                        .font(Theme.bodyFont(size: 13, weight: .medium))
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
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Password")
                        .font(Theme.bodyFont(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    SecureField("", text: $password)
                        .textFieldStyle(AuthTextFieldStyle())
                        .textContentType(.password)
                        .placeholder(when: password.isEmpty) {
                            Text("Enter your password")
                                .foregroundStyle(Theme.textMuted)
                        }
                }

                HStack {
                    Spacer()
                    Button(action: onNavigateToForgotPassword) {
                        Text("Forgot Password?")
                            .font(Theme.subheadline)
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
            .padding(.horizontal, 24)

            // Error
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(Theme.subheadline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Theme.danger.clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall)))
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
            }

            // Log In button
            Button(action: logIn) {
                Group {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Theme.background))
                    } else {
                        Text("Log In")
                            .font(Theme.headline)
                            .fontWeight(.bold)
                            .textCase(.uppercase)
                    }
                }
                .foregroundStyle(Theme.background)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    Group {
                        if isFormValid && !isLoading {
                            Theme.buttonGradient
                        } else {
                            LinearGradient(colors: [Theme.elevatedBackground], startPoint: .leading, endPoint: .trailing)
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
            }
            .disabled(!isFormValid || isLoading)
            .padding(.horizontal, 24)
            .padding(.top, 20)

            Spacer()
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
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
        .environment(AuthManager())
}
