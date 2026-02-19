import SwiftUI
import SwiftData

/// Add players screen (Step 3)
/// Allows bookie to add their first players via invite code or manual entry
struct OnboardingAddPlayersView: View {

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var authManager: AuthManager
    @Query private var players: [Player]

    // MARK: - Properties

    let onContinue: () -> Void

    // MARK: - State

    @State private var showInviteOption: Bool = false
    @State private var showManualOption: Bool = false
    @State private var generatedCode: String = ""
    @State private var playerName: String = ""
    @State private var showSuccessAnimation: Bool = false
    @State private var recentlyAddedName: String = ""

    /// Default credit limit from UserDefaults
    @AppStorage("default_credit_limit") private var defaultCreditLimit: Double = 500

    // MARK: - Computed

    /// Active players for this bookie
    private var activePlayers: [Player] {
        players.filter { $0.status == .active }
    }

    /// Whether the continue button should be enabled
    private var canContinue: Bool {
        activePlayers.count >= 1
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text("Your group needs members.")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.textPrimary)

                Text("Add at least one member to continue")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.top, 24)
            .padding(.bottom, 32)

            ScrollView {
                VStack(spacing: 20) {
                    // Option Cards
                    if !showInviteOption && !showManualOption {
                        optionCardsView
                    }

                    // Invite Code View
                    if showInviteOption {
                        inviteCodeView
                    }

                    // Manual Add View
                    if showManualOption {
                        manualAddView
                    }

                    // Success Animation
                    if showSuccessAnimation {
                        successAnimationView
                    }

                    // Added Players List
                    if !activePlayers.isEmpty {
                        addedPlayersView
                    }
                }
                .padding(.horizontal, 24)
            }

            Spacer()

            // Continue Button
            if canContinue {
                Button(action: onContinue) {
                    Text("Continue")
                        .font(Theme.headline)
                        .textCase(.uppercase)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Theme.backgroundGradient)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showInviteOption)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showManualOption)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showSuccessAnimation)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: canContinue)
    }

    // MARK: - Option Cards

    private var optionCardsView: some View {
        VStack(spacing: 16) {
            // Invite Players Card
            Button(action: { showInviteOption = true }) {
                HStack(spacing: 16) {
                    Image(systemName: "envelope.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.accent)
                        .frame(width: 44, height: 44)
                        .background(Theme.accent.opacity(0.15))
                        .cornerRadius(Theme.cornerRadiusSmall)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Invite Members")
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                        Text("Generate a code to share")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundStyle(Theme.textMuted)
                }
                .padding(16)
                .background(Theme.cardBackground)
                .cornerRadius(Theme.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerRadius)
                        .stroke(Theme.border, lineWidth: 1)
                )
            }

            // Add Manually Card
            Button(action: { showManualOption = true }) {
                HStack(spacing: 16) {
                    Image(systemName: "person.badge.plus")
                        .font(.title2)
                        .foregroundStyle(Theme.accentSecondary)
                        .frame(width: 44, height: 44)
                        .background(Theme.accentSecondary.opacity(0.15))
                        .cornerRadius(Theme.cornerRadiusSmall)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Add Manually")
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                        Text("Create a member yourself")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundStyle(Theme.textMuted)
                }
                .padding(16)
                .background(Theme.cardBackground)
                .cornerRadius(Theme.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerRadius)
                        .stroke(Theme.border, lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Invite Code View

    private var inviteCodeView: some View {
        VStack(spacing: 20) {
            // Back button
            HStack {
                Button(action: {
                    showInviteOption = false
                    generatedCode = ""
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .foregroundStyle(Theme.accent)
                }
                Spacer()
            }

            // Code display
            VStack(spacing: 16) {
                Text("Share this code with your member")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)

                if generatedCode.isEmpty {
                    Button(action: generateInviteCode) {
                        Text("Generate Code")
                            .font(Theme.headline)
                            .textCase(.uppercase)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                } else {
                    Text(generatedCode)
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.accent)
                        .padding(.vertical, 20)

                    HStack(spacing: 16) {
                        Button(action: copyCode) {
                            Label("Copy", systemImage: "doc.on.doc")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textPrimary)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(Theme.elevatedBackground)
                                .cornerRadius(Theme.cornerRadiusSmall)
                        }

                        ShareLink(item: "Join my group on Booki! Use code: \(generatedCode)") {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textPrimary)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(Theme.elevatedBackground)
                                .cornerRadius(Theme.cornerRadiusSmall)
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(Theme.cardBackground)
            .cornerRadius(Theme.cornerRadius)
        }
    }

    // MARK: - Manual Add View

    private var manualAddView: some View {
        VStack(spacing: 20) {
            // Back button
            HStack {
                Button(action: {
                    showManualOption = false
                    playerName = ""
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .foregroundStyle(Theme.accent)
                }
                Spacer()
            }

            // Form
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Member Name")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)

                    TextField("Enter name", text: $playerName)
                        .font(.body)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Theme.elevatedBackground)
                        .cornerRadius(Theme.cornerRadiusSmall)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Credit Limit")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)

                    HStack {
                        Text("$\(Int(defaultCreditLimit))")
                            .font(.body)
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text("(from settings)")
                            .font(.caption)
                            .foregroundStyle(Theme.textMuted)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Theme.elevatedBackground)
                    .cornerRadius(Theme.cornerRadiusSmall)
                }

                Button(action: addPlayer) {
                    Text("Add Member")
                        .font(Theme.headline)
                        .textCase(.uppercase)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(playerName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(20)
            .background(Theme.cardBackground)
            .cornerRadius(Theme.cornerRadius)
        }
    }

    // MARK: - Success Animation

    private var successAnimationView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.accent)

            Text("\(recentlyAddedName) added!")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(24)
        .background(Theme.cardBackground)
        .cornerRadius(Theme.cornerRadius)
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Added Players List

    private var addedPlayersView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Members")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)

                Spacer()

                Text("\(activePlayers.count)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.background)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Theme.accent)
                    .cornerRadius(12)
            }

            ForEach(activePlayers, id: \.id) { player in
                HStack {
                    Image(systemName: "person.fill")
                        .foregroundStyle(Theme.textMuted)
                    Text(player.name)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text("$\(player.creditLimit as NSDecimalNumber)")
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.vertical, 8)
            }
        }
        .padding(16)
        .background(Theme.cardBackground)
        .cornerRadius(Theme.cornerRadius)
    }

    // MARK: - Actions

    private func generateInviteCode() {
        // Create a placeholder player for the invite code
        guard let bookieId = authManager.currentBookieId else { return }

        let player = Player(
            name: "Pending Player",
            creditLimit: Decimal(defaultCreditLimit),
            bookieId: bookieId
        )
        modelContext.insert(player)

        let inviteService = InviteCodeService(modelContext: modelContext)
        inviteService.generateInviteForPlayer(player)
        generatedCode = player.inviteCode ?? ""
    }

    private func copyCode() {
        UIPasteboard.general.string = generatedCode
    }

    private func addPlayer() {
        guard let bookieId = authManager.currentBookieId else { return }
        let trimmedName = playerName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        let player = Player(
            name: trimmedName,
            creditLimit: Decimal(defaultCreditLimit),
            bookieId: bookieId
        )
        modelContext.insert(player)

        // Show success animation
        recentlyAddedName = trimmedName
        showSuccessAnimation = true
        playerName = ""

        // Hide success after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showSuccessAnimation = false
            showManualOption = false
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingAddPlayersView(onContinue: { print("Continue") })
        .environmentObject(AuthManager())
        .modelContainer(for: [Player.self])
}
