import SwiftUI
import SwiftData

/// Record type for validating invite codes from Supabase
private struct PlayerClaimRecord: Codable {
    let id: UUID
    let name: String
    let inviteCode: String?
    let inviteCodeExpiresAt: String?  // Use String to avoid date parsing issues
    let claimedAt: String?  // Use String to avoid date parsing issues

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case inviteCode = "invite_code"
        case inviteCodeExpiresAt = "invite_code_expires_at"
        case claimedAt = "claimed_at"
    }

    /// Parse expiration date from string
    var expiresAtDate: Date? {
        guard let dateString = inviteCodeExpiresAt else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateString) {
            return date
        }
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: dateString)
    }

    /// Check if already claimed
    var isClaimed: Bool {
        claimedAt != nil
    }
}

/// View for players to claim their account using an invite code
struct PlayerClaimView: View {

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var authManager: AuthManager

    // MARK: - State

    @State private var inviteCode: String = ""
    @State private var isValidating: Bool = false
    @State private var validatedPlayer: Player?
    @State private var errorMessage: String?
    @State private var showingConfirmation: Bool = false
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isCreatingAccount: Bool = false
    @State private var accountCreationError: String?
    @State private var accountCreated: Bool = false
    @State private var showAgreement: Bool = false
    @State private var createdAuthUserId: UUID?
    @State private var isSubmittingAgreement: Bool = false

    // MARK: - Callbacks

    var onNavigateToLogin: () -> Void

    // MARK: - Computed Properties

    private var normalizedCode: String {
        inviteCode
            .uppercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private var isValidCodeLength: Bool {
        normalizedCode.count == 8
    }

    private var isValidCredentials: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty &&
        password.count >= 6
    }

    // MARK: - Body

    var body: some View {
        if showAgreement {
            // Show full-screen UserAgreementView after account creation
            UserAgreementView(
                onAccept: {
                    submitPlayerAgreement()
                }
            )
        } else {
            claimFlowView
        }
    }

    /// The main claim flow view (code entry, confirmation, success states)
    private var claimFlowView: some View {
        ZStack {
            Theme.backgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    // Header
                    headerView

                    if accountCreated {
                        // Show success state
                        accountCreatedView
                    } else if let player = validatedPlayer {
                        // Show confirmation and account creation form
                        confirmationView(player: player)
                    } else {
                        // Show code entry form
                        codeEntryForm
                    }

                    // Back to login link
                    backToLoginLink
                }
                .padding(.horizontal, 32)
                .padding(.top, 60)
            }
        }
    }

    // MARK: - Subviews

    private var headerView: some View {
        VStack(spacing: 16) {
            Image(systemName: "ticket.fill")
                .font(Theme.font(size: 60))
                .foregroundStyle(Theme.accent)

            Text("Claim Your Account")
                .font(Theme.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(Theme.textPrimary)

            Text("Enter the invite code from your organizer to access your account")
                .font(Theme.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private var codeEntryForm: some View {
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
                    .cornerRadius(12)
                    .onChange(of: inviteCode) { _, newValue in
                        // Auto-format: uppercase and remove non-alphanumeric
                        let filtered = newValue
                            .uppercased()
                            .filter { $0.isLetter || $0.isNumber }
                        if filtered != newValue {
                            inviteCode = filtered
                        }
                        // Limit to 8 characters
                        if filtered.count > 8 {
                            inviteCode = String(filtered.prefix(8))
                        }
                        // Clear error when typing
                        errorMessage = nil
                    }

                // Character count indicator
                HStack {
                    Spacer()
                    Text("\(normalizedCode.count)/8")
                        .font(Theme.caption)
                        .foregroundStyle(normalizedCode.count == 8 ? .green : Theme.textSecondary)
                }
            }

            // Error message
            if let error = errorMessage {
                Text(error)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.danger)
                    .multilineTextAlignment(.center)
            }

            // Validate button
            Button {
                validateCode()
            } label: {
                HStack {
                    if isValidating {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text("Validate Code")
                            .font(Theme.headline)
                            .fontWeight(.bold)
                            .textCase(.uppercase)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(isValidCodeLength && !isValidating ? Theme.accent : Theme.accent.opacity(0.5))
                .foregroundStyle(Theme.background)
                .cornerRadius(12)
            }
            .disabled(!isValidCodeLength || isValidating)
        }
    }

    private func confirmationView(player: Player) -> some View {
        VStack(spacing: 24) {
            // Success checkmark
            Image(systemName: "checkmark.circle.fill")
                .font(Theme.font(size: 50))
                .foregroundStyle(Theme.accent)

            Text("Welcome, \(player.name)!")
                .font(Theme.title2)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.textPrimary)

            Text("This is your account. Create a login to access it anytime.")
                .font(Theme.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)

            // Account creation form
            VStack(spacing: 16) {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .padding()
                    .background(Theme.cardBackground)
                    .cornerRadius(12)

                SecureField("Password (min 6 characters)", text: $password)
                    .textContentType(.newPassword)
                    .padding()
                    .background(Theme.cardBackground)
                    .cornerRadius(12)
            }

            // Error message
            if let error = accountCreationError {
                Text(error)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.danger)
                    .multilineTextAlignment(.center)
            }

            // Create account button
            Button {
                createAccount(for: player)
            } label: {
                HStack {
                    if isCreatingAccount {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text("Create Account")
                            .font(Theme.headline)
                            .fontWeight(.bold)
                            .textCase(.uppercase)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(isValidCredentials && !isCreatingAccount ? Theme.accent : Theme.accent.opacity(0.5))
                .foregroundStyle(Theme.background)
                .cornerRadius(12)
            }
            .disabled(!isValidCredentials || isCreatingAccount)

            // Cancel button
            Button {
                validatedPlayer = nil
                inviteCode = ""
            } label: {
                Text("Use Different Code")
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var accountCreatedView: some View {
        VStack(spacing: 24) {
            // Success checkmark
            Image(systemName: "checkmark.circle.fill")
                .font(Theme.font(size: 60))
                .foregroundStyle(Theme.accent)

            Text("Account Created!")
                .font(Theme.title2)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.textPrimary)

            Text("Your account has been created. You can now log in with your email and password.")
                .font(Theme.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)

            // Go to login button
            Button {
                onNavigateToLogin()
            } label: {
                Text("Go to Login")
                    .font(Theme.headline)
                    .fontWeight(.bold)
                    .textCase(.uppercase)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Theme.accent)
                    .foregroundStyle(Theme.background)
                    .cornerRadius(12)
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

    // MARK: - Actions

    private func validateCode() {
        isValidating = true
        errorMessage = nil

        Task {
            do {
                // Query Supabase directly for the invite code
                // This allows players without local data to validate their code
                let supabase = SupabaseClientManager.shared.client

                print("DEBUG: Validating invite code, normalized: '\(normalizedCode)'")

                let response: [PlayerClaimRecord] = try await supabase
                    .from("players")
                    .select("id, name, invite_code, invite_code_expires_at, claimed_at")
                    .eq("invite_code", value: normalizedCode)
                    .execute()
                    .value

                print("DEBUG: Query returned \(response.count) records")

                await MainActor.run {
                    isValidating = false

                    guard let record = response.first else {
                        print("DEBUG: No matching record found for code '\(normalizedCode)'")
                        errorMessage = "Invalid invite code. Please check the code and try again."
                        return
                    }

                    print("DEBUG: Found player '\(record.name)' with code '\(record.inviteCode ?? "nil")'")

                    // Check if already claimed
                    if record.isClaimed {
                        errorMessage = "This invite code has already been used."
                        return
                    }

                    // Check expiration
                    if let expiresAt = record.expiresAtDate, Date() > expiresAt {
                        errorMessage = "This invite code has expired. Please contact your organizer for a new one."
                        return
                    }

                    // Create a local Player object for display purposes
                    // This is just for showing the name in the UI
                    let player = Player(
                        id: record.id,
                        name: record.name,
                        inviteCode: record.inviteCode
                    )
                    validatedPlayer = player
                }
            } catch {
                await MainActor.run {
                    isValidating = false
                    errorMessage = "Failed to validate code. Please try again."
                    print("DEBUG: Error validating invite code: \(error)")
                }
            }
        }
    }

    private func createAccount(for player: Player) {
        print("DEBUG: createAccount called for player: \(player.name)")
        print("DEBUG: email: \(email), password length: \(password.count)")

        isCreatingAccount = true
        accountCreationError = nil

        Task {
            do {
                print("DEBUG: Starting Supabase signUp...")
                // Create Supabase auth account for the player
                let supabase = SupabaseClientManager.shared.client
                let response = try await supabase.auth.signUp(
                    email: email.trimmingCharacters(in: .whitespaces),
                    password: password
                )
                print("DEBUG: Supabase signUp succeeded, user ID: \(response.user.id)")

                // Update the player's auth_user_id directly in Supabase
                // This links the auth credentials to the existing player record
                print("DEBUG: Updating player record in Supabase with auth_user_id...")
                try await supabase
                    .from("players")
                    .update([
                        "auth_user_id": response.user.id.uuidString,
                        "claimed_at": ISO8601DateFormatter().string(from: Date()),
                        "updated_at": ISO8601DateFormatter().string(from: Date())
                    ])
                    .eq("invite_code", value: normalizedCode)
                    .execute()
                print("DEBUG: Supabase player record updated successfully")

                // Also update the local SwiftData model
                let inviteCodeService = InviteCodeService(modelContext: modelContext)
                inviteCodeService.claimAccount(for: player, authUserId: response.user.id)
                print("DEBUG: Local player account claimed")

                // Store the auth user ID and show agreement view
                await MainActor.run {
                    isCreatingAccount = false
                    createdAuthUserId = response.user.id
                    showAgreement = true
                }
            } catch {
                print("DEBUG: Error creating account: \(error)")
                await MainActor.run {
                    isCreatingAccount = false
                    accountCreationError = "Failed to create account: \(error.localizedDescription)"
                }
            }
        }
    }

    private func submitPlayerAgreement() {
        guard let userId = createdAuthUserId else {
            print("DEBUG: No user ID available for agreement submission")
            // Fall back to showing success screen anyway
            showAgreement = false
            accountCreated = true
            return
        }

        isSubmittingAgreement = true

        Task {
            do {
                let agreementService = AgreementService()
                try await agreementService.submitAgreement(
                    userId: userId,
                    role: "player",
                    version: AgreementService.currentAgreementVersion
                )
                print("DEBUG: Player agreement submitted successfully")

                await MainActor.run {
                    isSubmittingAgreement = false
                    showAgreement = false
                    accountCreated = true
                }
            } catch {
                print("DEBUG: Failed to submit agreement: \(error)")
                // Even on failure, proceed to success screen
                // Agreement will be required on next login
                await MainActor.run {
                    isSubmittingAgreement = false
                    showAgreement = false
                    accountCreated = true
                }
            }
        }
    }
}

#Preview {
    PlayerClaimView(onNavigateToLogin: {})
        .modelContainer(for: Player.self, inMemory: true)
        .environmentObject(AuthManager())
}
