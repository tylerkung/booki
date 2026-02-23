import SwiftUI
@preconcurrency import Supabase

/// Record type for validating invite codes from Supabase invites table
private struct InviteValidationRecord: Codable {
    let id: String
    let inviteCode: String
    let expiresAt: String
    let claimedAt: String?
    let bookieId: String
    let bookies: BookieNameRecord?

    enum CodingKeys: String, CodingKey {
        case id
        case inviteCode = "invite_code"
        case expiresAt = "expires_at"
        case claimedAt = "claimed_at"
        case bookieId = "bookie_id"
        case bookies
    }

    /// Parse expiration date from string
    var expiresAtDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: expiresAt) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: expiresAt)
    }

    var isClaimed: Bool {
        claimedAt != nil
    }

    var bookieName: String {
        bookies?.name ?? "an organizer"
    }
}

/// Nested record for bookie name join
private struct BookieNameRecord: Codable {
    let name: String
}

/// View for claiming an invite via deep link or manual code entry.
/// Handles both new user signup and existing user login paths.
struct InviteClaimView: View {

    // MARK: - View State

    enum ViewStep {
        case codeEntry
        case validating
        case landing(bookieName: String, inviteCode: String)
        case error(message: String)
        case newUserSignup(bookieName: String, inviteCode: String)
        case existingUserLogin(bookieName: String, inviteCode: String)
        case confirmJoin(bookieName: String, inviteCode: String)
    }

    // MARK: - Environment

    @Environment(AuthManager.self) private var authManager

    // MARK: - Properties

    /// Pre-filled invite code from deep link (booki://invite/{code})
    let initialCode: String?

    /// Navigate back to login screen
    let onNavigateToLogin: () -> Void

    /// Called when invite claim is fully complete (player joined)
    let onClaimComplete: () -> Void

    // MARK: - State

    @State private var step: ViewStep = .codeEntry
    @State private var inviteCode: String = ""

    // Signup form state
    @State private var signupEmail: String = ""
    @State private var signupPassword: String = ""
    @State private var signupConfirmPassword: String = ""
    @State private var isSigningUp: Bool = false
    @State private var signupError: String?

    // Login form state (existing user path)
    @State private var loginEmail: String = ""
    @State private var loginPassword: String = ""
    @State private var isLoggingIn: Bool = false
    @State private var loginError: String?
    @State private var showAlreadyInGroupError: Bool = false
    @State private var loginSessionAccessToken: String = ""
    @State private var loginSessionUserId: String = ""
    @State private var isClaimingInvite: Bool = false

    // Agreement state
    @State private var showAgreement: Bool = false
    @State private var createdAuthUserId: UUID?
    @State private var signupEmailForLogin: String = ""
    @State private var signupPasswordForLogin: String = ""

    // MARK: - Computed

    private var normalizedCode: String {
        inviteCode
            .uppercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private var isValidCodeLength: Bool {
        normalizedCode.count == 8
    }

    // MARK: - Body

    var body: some View {
        if showAgreement {
            UserAgreementView(
                onAccept: {
                    submitPlayerAgreement()
                }
            )
        } else {
            mainContent
        }
    }

    private var mainContent: some View {
        ZStack {
            Theme.backgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    switch step {
                    case .codeEntry:
                        codeEntryContent
                    case .validating:
                        validatingContent
                    case .landing(let bookieName, let code):
                        landingContent(bookieName: bookieName, inviteCode: code)
                    case .error(let message):
                        errorContent(message: message)
                    case .newUserSignup(let bookieName, let code):
                        newUserSignupContent(bookieName: bookieName, inviteCode: code)
                    case .existingUserLogin(let bookieName, let code):
                        existingUserLoginContent(bookieName: bookieName, inviteCode: code)
                    case .confirmJoin(let bookieName, let code):
                        confirmJoinContent(bookieName: bookieName, inviteCode: code)
                    }

                    // Back to login link (always visible)
                    backToLoginLink
                }
                .padding(.horizontal, 32)
                .padding(.top, 60)
            }
        }
        .onAppear {
            if let code = initialCode, !code.isEmpty {
                inviteCode = code
                validateCode(code)
            }
        }
    }

    // MARK: - Code Entry

    private var codeEntryContent: some View {
        VStack(spacing: 32) {
            headerView(
                title: "Join a Group",
                subtitle: "Enter the invite code from your organizer"
            )

            VStack(spacing: 24) {
                // Code input field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Invite Code")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)

                    TextField("XXXXXXXX", text: $inviteCode)
                        .font(.system(.title, design: .monospaced))
                        .textCase(.uppercase)
                        .multilineTextAlignment(.center)
                        .kerning(4)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                        .padding()
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .onChange(of: inviteCode) { _, newValue in
                            let filtered = newValue
                                .uppercased()
                                .filter { $0.isLetter || $0.isNumber }
                            if filtered != newValue {
                                inviteCode = filtered
                            }
                            if filtered.count > 8 {
                                inviteCode = String(filtered.prefix(8))
                            }
                        }

                    // Character count
                    HStack {
                        Spacer()
                        Text("\(normalizedCode.count)/8")
                            .font(Theme.caption)
                            .foregroundStyle(normalizedCode.count == 8 ? Theme.accent : Theme.textSecondary)
                    }
                }

                // Submit button
                Button {
                    validateCode(normalizedCode)
                } label: {
                    Text("Submit")
                        .font(Theme.headline)
                        .fontWeight(.bold)
                        .textCase(.uppercase)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            Group {
                                if isValidCodeLength {
                                    Theme.buttonGradient
                                } else {
                                    LinearGradient(colors: [Theme.elevatedBackground], startPoint: .leading, endPoint: .trailing)
                                }
                            }
                        )
                        .foregroundStyle(isValidCodeLength ? Theme.background : Theme.textMuted)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!isValidCodeLength)
            }
        }
    }

    // MARK: - Validating

    private var validatingContent: some View {
        VStack(spacing: 32) {
            headerView(
                title: "Join a Group",
                subtitle: "Checking your invite..."
            )

            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: Theme.accent))
                .scaleEffect(1.2)
        }
    }

    // MARK: - Landing (Valid Invite)

    private func landingContent(bookieName: String, inviteCode: String) -> some View {
        VStack(spacing: 32) {
            // Logo
            Image("BookiLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 180)
                .shadow(color: Theme.accent.opacity(0.3), radius: 40, x: 0, y: 0)

            // Invitation message
            VStack(spacing: 12) {
                Text("You've been invited to join")
                    .font(Theme.title3)
                    .foregroundStyle(Theme.textSecondary)

                Text("\(bookieName)'s group")
                    .font(Theme.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
            }

            // CTAs
            VStack(spacing: 16) {
                // Primary: Get Started
                Button {
                    step = .newUserSignup(bookieName: bookieName, inviteCode: inviteCode)
                } label: {
                    Text("Get Started")
                        .font(Theme.headline)
                        .fontWeight(.bold)
                        .textCase(.uppercase)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Theme.buttonGradient)
                        .foregroundStyle(Theme.background)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // Secondary: Already have an account?
                Button {
                    step = .existingUserLogin(bookieName: bookieName, inviteCode: inviteCode)
                } label: {
                    Text("Already have an account?")
                        .font(Theme.subheadline)
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Error

    private func errorContent(message: String) -> some View {
        VStack(spacing: 32) {
            headerView(
                title: "Join a Group",
                subtitle: nil
            )

            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(Theme.font(size: 40))
                    .foregroundStyle(Theme.danger)

                Text(message)
                    .font(Theme.body)
                    .foregroundStyle(Theme.danger)
                    .multilineTextAlignment(.center)
            }

            // Try again button
            Button {
                inviteCode = ""
                step = .codeEntry
            } label: {
                Text("Try Again")
                    .font(Theme.headline)
                    .fontWeight(.bold)
                    .textCase(.uppercase)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Theme.buttonGradient)
                    .foregroundStyle(Theme.background)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Shared Subviews

    private func headerView(title: String, subtitle: String?) -> some View {
        VStack(spacing: 16) {
            Image("BookiLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 180)
                .shadow(color: Theme.accent.opacity(0.3), radius: 40, x: 0, y: 0)

            Text(title)
                .font(Theme.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(Theme.textPrimary)

            if let subtitle {
                Text(subtitle)
                    .font(Theme.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var backToLoginLink: some View {
        Button {
            onNavigateToLogin()
        } label: {
            HStack {
                Image(systemName: "arrow.left")
                Text("Back to Organizer Login")
            }
            .font(Theme.subheadline)
            .foregroundStyle(Theme.accent)
        }
        .padding(.top, 16)
    }

    // MARK: - New User Signup

    private func newUserSignupContent(bookieName: String, inviteCode: String) -> some View {
        VStack(spacing: 32) {
            headerView(
                title: "Create Account",
                subtitle: "Sign up to join \(bookieName)'s group"
            )

            VStack(spacing: 16) {
                // Email field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Email")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)

                    TextField("", text: $signupEmail, prompt: Text("you@example.com").foregroundColor(Color(white: 0.45)))
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding()
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(Theme.textPrimary)
                }

                // Password field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Password")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)

                    SecureField("Min 6 characters", text: $signupPassword)
                        .textContentType(.oneTimeCode)
                        .padding()
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(Theme.textPrimary)
                }

                // Confirm password field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Confirm Password")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)

                    SecureField("Re-enter password", text: $signupConfirmPassword)
                        .textContentType(.oneTimeCode)
                        .padding()
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(Theme.textPrimary)
                }

                // Error message
                if let error = signupError {
                    Text(error)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.danger)
                        .multilineTextAlignment(.center)
                }
            }

            // Submit button
            Button {
                createAccount(bookieName: bookieName, inviteCode: inviteCode)
            } label: {
                HStack(spacing: 8) {
                    if isSigningUp {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Theme.background))
                            .scaleEffect(0.8)
                    }
                    Text(isSigningUp ? "Creating Account..." : "Create Account")
                        .font(Theme.headline)
                        .fontWeight(.bold)
                        .textCase(.uppercase)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    Group {
                        if isSignupFormValid && !isSigningUp {
                            Theme.buttonGradient
                        } else {
                            LinearGradient(colors: [Theme.elevatedBackground], startPoint: .leading, endPoint: .trailing)
                        }
                    }
                )
                .foregroundStyle(isSignupFormValid && !isSigningUp ? Theme.background : Theme.textMuted)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(!isSignupFormValid || isSigningUp)

            // Back to landing
            Button {
                signupError = nil
                step = .landing(bookieName: bookieName, inviteCode: inviteCode)
            } label: {
                HStack {
                    Image(systemName: "arrow.left")
                    Text("Back")
                }
                .font(Theme.subheadline)
                .foregroundStyle(Theme.accent)
            }
        }
    }

    // MARK: - Existing User Login

    private func existingUserLoginContent(bookieName: String, inviteCode: String) -> some View {
        VStack(spacing: 32) {
            if showAlreadyInGroupError {
                alreadyInGroupContent(bookieName: bookieName, inviteCode: inviteCode)
            } else {
                loginFormContent(bookieName: bookieName, inviteCode: inviteCode)
            }
        }
    }

    private func loginFormContent(bookieName: String, inviteCode: String) -> some View {
        VStack(spacing: 32) {
            headerView(
                title: "Sign In",
                subtitle: "Log in to join \(bookieName)'s group"
            )

            VStack(spacing: 16) {
                // Email field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Email")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)

                    TextField("", text: $loginEmail, prompt: Text("you@example.com").foregroundColor(Color(white: 0.45)))
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding()
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(Theme.textPrimary)
                }

                // Password field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Password")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)

                    SecureField("Enter password", text: $loginPassword)
                        .textContentType(.password)
                        .padding()
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(Theme.textPrimary)
                }

                // Error message
                if let error = loginError {
                    Text(error)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.danger)
                        .multilineTextAlignment(.center)
                }
            }

            // Submit button
            Button {
                loginAndClaimInvite(bookieName: bookieName, inviteCode: inviteCode)
            } label: {
                HStack(spacing: 8) {
                    if isLoggingIn {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Theme.background))
                            .scaleEffect(0.8)
                    }
                    Text(isLoggingIn ? "Signing In..." : "Sign In")
                        .font(Theme.headline)
                        .fontWeight(.bold)
                        .textCase(.uppercase)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    Group {
                        if isLoginFormValid && !isLoggingIn {
                            Theme.buttonGradient
                        } else {
                            LinearGradient(colors: [Theme.elevatedBackground], startPoint: .leading, endPoint: .trailing)
                        }
                    }
                )
                .foregroundStyle(isLoginFormValid && !isLoggingIn ? Theme.background : Theme.textMuted)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(!isLoginFormValid || isLoggingIn)

            // Back to landing
            Button {
                loginError = nil
                step = .landing(bookieName: bookieName, inviteCode: inviteCode)
            } label: {
                HStack {
                    Image(systemName: "arrow.left")
                    Text("Back")
                }
                .font(Theme.subheadline)
                .foregroundStyle(Theme.accent)
            }
        }
    }

    private func alreadyInGroupContent(bookieName: String, inviteCode: String) -> some View {
        VStack(spacing: 32) {
            headerView(
                title: "Unable to Join",
                subtitle: nil
            )

            VStack(spacing: 16) {
                Image(systemName: "person.2.slash")
                    .font(Theme.font(size: 40))
                    .foregroundStyle(Theme.danger)

                Text("You're already a member of another organizer's group. You cannot join multiple groups.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            // Back button
            Button {
                showAlreadyInGroupError = false
                loginError = nil
                loginEmail = ""
                loginPassword = ""
                step = .landing(bookieName: bookieName, inviteCode: inviteCode)
            } label: {
                Text("Back")
                    .font(Theme.headline)
                    .fontWeight(.bold)
                    .textCase(.uppercase)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Theme.buttonGradient)
                    .foregroundStyle(Theme.background)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func confirmJoinContent(bookieName: String, inviteCode: String) -> some View {
        VStack(spacing: 32) {
            // Logo
            Image("BookiLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 180)
                .shadow(color: Theme.accent.opacity(0.3), radius: 40, x: 0, y: 0)

            VStack(spacing: 12) {
                Text("Join \(bookieName)'s group?")
                    .font(Theme.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)

                Text("You'll be added as a member of this organizer's group.")
                    .font(Theme.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 16) {
                // Confirm button
                Button {
                    claimInviteAfterLogin(bookieName: bookieName, inviteCode: inviteCode)
                } label: {
                    HStack(spacing: 8) {
                        if isClaimingInvite {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: Theme.background))
                                .scaleEffect(0.8)
                        }
                        Text(isClaimingInvite ? "Joining..." : "Confirm")
                            .font(Theme.headline)
                            .fontWeight(.bold)
                            .textCase(.uppercase)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        Group {
                            if isClaimingInvite {
                                LinearGradient(colors: [Theme.elevatedBackground], startPoint: .leading, endPoint: .trailing)
                            } else {
                                Theme.buttonGradient
                            }
                        }
                    )
                    .foregroundStyle(isClaimingInvite ? Theme.textMuted : Theme.background)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isClaimingInvite)

                // Cancel button
                Button {
                    // Sign out and return to landing
                    Task {
                        let supabase = SupabaseClientManager.shared.client
                        try? await supabase.auth.signOut()
                        await MainActor.run {
                            authManager.isClaimingPlayerAccount = false
                            loginEmail = ""
                            loginPassword = ""
                            loginSessionAccessToken = ""
                            loginSessionUserId = ""
                            step = .landing(bookieName: bookieName, inviteCode: inviteCode)
                        }
                    }
                } label: {
                    Text("Cancel")
                        .font(Theme.subheadline)
                        .foregroundStyle(Theme.accent)
                }
                .disabled(isClaimingInvite)
            }
        }
    }

    private var isLoginFormValid: Bool {
        let trimmedEmail = loginEmail.trimmingCharacters(in: .whitespaces)
        return !trimmedEmail.isEmpty
            && trimmedEmail.contains("@")
            && !loginPassword.isEmpty
    }

    private func loginAndClaimInvite(bookieName: String, inviteCode: String) {
        loginError = nil
        isLoggingIn = true

        Task {
            do {
                // Prevent auth state listener from creating a bookie record
                await MainActor.run {
                    authManager.isClaimingPlayerAccount = true
                }

                let supabase = SupabaseClientManager.shared.client
                let session = try await supabase.auth.signIn(
                    email: loginEmail.trimmingCharacters(in: .whitespaces),
                    password: loginPassword
                )

                // Store session info for claim step
                await MainActor.run {
                    loginSessionAccessToken = session.accessToken
                    loginSessionUserId = session.user.id.uuidString.lowercased()
                    isLoggingIn = false
                    step = .confirmJoin(bookieName: bookieName, inviteCode: inviteCode)
                }
            } catch {
                print("DEBUG: Error logging in for invite claim: \(error)")
                await MainActor.run {
                    authManager.isClaimingPlayerAccount = false
                    isLoggingIn = false
                    let errorMessage = error.localizedDescription
                    if errorMessage.lowercased().contains("invalid login") || errorMessage.lowercased().contains("invalid credentials") {
                        loginError = "Invalid email or password. Please try again."
                    } else {
                        loginError = "Something went wrong. Please check your connection and try again."
                    }
                }
            }
        }
    }

    private func claimInviteAfterLogin(bookieName: String, inviteCode: String) {
        isClaimingInvite = true

        Task {
            do {
                let baseURL = SupabaseConfig.url
                guard let claimURL = URL(string: "\(baseURL.absoluteString)/functions/v1/claim_invite") else {
                    throw NSError(domain: "InviteClaimView", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
                }
                var claimRequest = URLRequest(url: claimURL)
                claimRequest.httpMethod = "POST"
                claimRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                claimRequest.setValue("Bearer \(loginSessionAccessToken)", forHTTPHeaderField: "Authorization")
                let claimBody: [String: String] = [
                    "invite_code": inviteCode,
                    "auth_user_id": loginSessionUserId,
                    "idempotency_key": UUID().uuidString.lowercased()
                ]
                claimRequest.httpBody = try JSONEncoder().encode(claimBody)
                let (claimData, claimResponse) = try await URLSession.shared.data(for: claimRequest)

                if let httpResp = claimResponse as? HTTPURLResponse {
                    if httpResp.statusCode == 409 {
                        // Already in another group — sign out and show error
                        let supabase = SupabaseClientManager.shared.client
                        try? await supabase.auth.signOut()
                        await MainActor.run {
                            authManager.isClaimingPlayerAccount = false
                            isClaimingInvite = false
                            showAlreadyInGroupError = true
                            step = .existingUserLogin(bookieName: bookieName, inviteCode: inviteCode)
                        }
                        return
                    } else if !(200...299).contains(httpResp.statusCode) {
                        let msg = String(data: claimData, encoding: .utf8) ?? "Unknown error"
                        throw NSError(domain: "InviteClaimView", code: httpResp.statusCode, userInfo: [NSLocalizedDescriptionKey: "Failed to claim invite: \(msg)"])
                    }
                }

                // Claim succeeded — use completePlayerClaimFlow to set up auth state
                await MainActor.run {
                    isClaimingInvite = false
                }
                await authManager.completePlayerClaimFlow(
                    email: loginEmail.trimmingCharacters(in: .whitespaces),
                    password: loginPassword
                )
            } catch {
                print("DEBUG: Error claiming invite after login: \(error)")
                let supabase = SupabaseClientManager.shared.client
                try? await supabase.auth.signOut()
                await MainActor.run {
                    authManager.isClaimingPlayerAccount = false
                    isClaimingInvite = false
                    loginError = "Something went wrong. Please check your connection and try again."
                    step = .existingUserLogin(bookieName: bookieName, inviteCode: inviteCode)
                }
            }
        }
    }

    private var isSignupFormValid: Bool {
        let trimmedEmail = signupEmail.trimmingCharacters(in: .whitespaces)
        return !trimmedEmail.isEmpty
            && trimmedEmail.contains("@")
            && signupPassword.count >= 6
            && signupPassword == signupConfirmPassword
    }

    // MARK: - Account Creation Flow

    private func createAccount(bookieName: String, inviteCode: String) {
        signupError = nil
        isSigningUp = true

        // Store credentials for later fresh sign-in
        signupEmailForLogin = signupEmail.trimmingCharacters(in: .whitespaces)
        signupPasswordForLogin = signupPassword

        // Validate passwords match
        guard signupPassword == signupConfirmPassword else {
            signupError = "Passwords do not match."
            isSigningUp = false
            return
        }

        guard signupPassword.count >= 6 else {
            signupError = "Password must be at least 6 characters."
            isSigningUp = false
            return
        }

        Task {
            do {
                // Prevent auth state listener from creating a bookie record
                // during the signUp → claim_invite sequence
                await MainActor.run {
                    authManager.isClaimingPlayerAccount = true
                }

                let supabase = SupabaseClientManager.shared.client
                let response = try await supabase.auth.signUp(
                    email: signupEmailForLogin,
                    password: signupPasswordForLogin
                )

                // Call claim_invite edge function with anon key
                // (signUp JWT is invalid — email unconfirmed)
                let baseURL = SupabaseConfig.url
                guard let claimURL = URL(string: "\(baseURL.absoluteString)/functions/v1/claim_invite") else {
                    throw NSError(domain: "InviteClaimView", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
                }
                var claimRequest = URLRequest(url: claimURL)
                claimRequest.httpMethod = "POST"
                claimRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                claimRequest.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
                let claimBody: [String: String] = [
                    "invite_code": inviteCode,
                    "auth_user_id": response.user.id.uuidString.lowercased(),
                    "idempotency_key": UUID().uuidString.lowercased()
                ]
                claimRequest.httpBody = try JSONEncoder().encode(claimBody)
                let (claimData, claimResponse) = try await URLSession.shared.data(for: claimRequest)

                if let httpResp = claimResponse as? HTTPURLResponse, !(200...299).contains(httpResp.statusCode) {
                    let msg = String(data: claimData, encoding: .utf8) ?? "Unknown error"
                    throw NSError(domain: "InviteClaimView", code: httpResp.statusCode, userInfo: [NSLocalizedDescriptionKey: "Failed to claim invite: \(msg)"])
                }

                // Show agreement view
                await MainActor.run {
                    isSigningUp = false
                    createdAuthUserId = response.user.id
                    showAgreement = true
                }
            } catch {
                print("DEBUG: Error creating account via invite: \(error)")
                await MainActor.run {
                    authManager.isClaimingPlayerAccount = false
                    isSigningUp = false
                    let errorMessage = error.localizedDescription
                    if errorMessage.lowercased().contains("already registered") || errorMessage.lowercased().contains("already been registered") {
                        signupError = "This email is already registered. Try signing in instead."
                    } else if errorMessage.lowercased().contains("password") {
                        signupError = "Password is too weak. Use at least 6 characters."
                    } else {
                        signupError = "Something went wrong. Please check your connection and try again."
                    }
                }
            }
        }
    }

    private func submitPlayerAgreement() {
        guard let userId = createdAuthUserId else {
            // Fallback: sign in fresh (will require agreement on next login)
            Task {
                await authManager.completePlayerClaimFlow(email: signupEmailForLogin, password: signupPasswordForLogin)
            }
            return
        }

        Task {
            do {
                let agreementService = AgreementService()
                try await agreementService.submitAgreement(
                    userId: userId,
                    role: "player",
                    version: AgreementService.currentAgreementVersion
                )
            } catch {
                print("DEBUG: Failed to submit agreement: \(error)")
                // Agreement will be required on next login
            }

            // Sign out invalid session and sign in fresh with confirmed credentials
            await authManager.completePlayerClaimFlow(email: signupEmailForLogin, password: signupPasswordForLogin)
        }
    }

    // MARK: - Validation

    private func validateCode(_ code: String) {
        let normalized = code.uppercased().filter { $0.isLetter || $0.isNumber }
        guard normalized.count == 8 else {
            step = .error(message: "Invalid invite code. Codes are 8 characters long.")
            return
        }

        step = .validating

        Task {
            do {
                let supabase = SupabaseClientManager.shared.client

                let response: [InviteValidationRecord] = try await supabase
                    .from("invites")
                    .select("id, invite_code, expires_at, claimed_at, bookie_id, bookies(name)")
                    .eq("invite_code", value: normalized)
                    .execute()
                    .value

                await MainActor.run {
                    guard let record = response.first else {
                        step = .error(message: "This invite has expired or is invalid.")
                        return
                    }

                    if record.isClaimed {
                        step = .error(message: "This invite has already been used.")
                        return
                    }

                    if let expiresAt = record.expiresAtDate, Date() > expiresAt {
                        step = .error(message: "This invite has expired. Please ask your organizer for a new one.")
                        return
                    }

                    step = .landing(bookieName: record.bookieName, inviteCode: normalized)
                }
            } catch {
                await MainActor.run {
                    step = .error(message: "Failed to validate invite code. Please check your connection and try again.")
                    print("DEBUG: Error validating invite code: \(error)")
                }
            }
        }
    }
}

#Preview {
    InviteClaimView(
        initialCode: "ABC12345",
        onNavigateToLogin: {},
        onClaimComplete: {}
    )
    .environment(AuthManager())
}
