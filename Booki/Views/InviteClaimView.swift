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
        // Placeholder steps for US-012 and US-013
        case newUserSignup(bookieName: String, inviteCode: String)
        case existingUserLogin(bookieName: String, inviteCode: String)
    }

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
                    case .newUserSignup:
                        // Placeholder — US-012 will implement
                        Text("New user signup")
                            .foregroundStyle(Theme.textPrimary)
                    case .existingUserLogin:
                        // Placeholder — US-013 will implement
                        Text("Existing user login")
                            .foregroundStyle(Theme.textPrimary)
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
}
