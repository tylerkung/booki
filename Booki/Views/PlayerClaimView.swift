import SwiftUI
import SwiftData

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
                .font(.system(size: 60))
                .foregroundStyle(Theme.accent)

            Text("Claim Your Account")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(Theme.textPrimary)

            Text("Enter the invite code from your bookie to access your account")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private var codeEntryForm: some View {
        VStack(spacing: 24) {
            // Code input field
            VStack(alignment: .leading, spacing: 8) {
                Text("Invite Code")
                    .font(.caption)
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
                        .font(.caption)
                        .foregroundStyle(normalizedCode.count == 8 ? .green : Theme.textSecondary)
                }
            }

            // Error message
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
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
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(isValidCodeLength && !isValidating ? Theme.accent : Theme.accent.opacity(0.5))
                .foregroundStyle(.white)
                .cornerRadius(12)
            }
            .disabled(!isValidCodeLength || isValidating)
        }
    }

    private func confirmationView(player: Player) -> some View {
        VStack(spacing: 24) {
            // Success checkmark
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 50))
                .foregroundStyle(.green)

            Text("Welcome, \(player.name)!")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.textPrimary)

            Text("This is your account. Create a login to access it anytime.")
                .font(.subheadline)
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
                    .font(.caption)
                    .foregroundStyle(.red)
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
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(isValidCredentials && !isCreatingAccount ? Theme.accent : Theme.accent.opacity(0.5))
                .foregroundStyle(.white)
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
                .font(.system(size: 60))
                .foregroundStyle(.green)

            Text("Account Created!")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.textPrimary)

            Text("Your account has been created. You can now log in with your email and password.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)

            // Go to login button
            Button {
                onNavigateToLogin()
            } label: {
                Text("Go to Login")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Theme.accent)
                    .foregroundStyle(.white)
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
                Text("Back to Bookie Login")
            }
            .font(.subheadline)
            .foregroundStyle(Theme.accent)
        }
        .padding(.top, 16)
    }

    // MARK: - Actions

    private func validateCode() {
        isValidating = true
        errorMessage = nil

        let inviteCodeService = InviteCodeService(modelContext: modelContext)
        let player = inviteCodeService.validateCode(normalizedCode)

        isValidating = false

        if let player = player {
            validatedPlayer = player
        } else {
            errorMessage = "Invalid or expired invite code. Please check the code and try again."
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

                // Mark the player account as claimed
                let inviteCodeService = InviteCodeService(modelContext: modelContext)
                inviteCodeService.claimAccount(for: player, authUserId: response.user.id)
                print("DEBUG: Player account claimed")

                // Show success state
                await MainActor.run {
                    isCreatingAccount = false
                    accountCreated = true
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
}

#Preview {
    PlayerClaimView(onNavigateToLogin: {})
        .modelContainer(for: Player.self, inMemory: true)
        .environmentObject(AuthManager())
}
