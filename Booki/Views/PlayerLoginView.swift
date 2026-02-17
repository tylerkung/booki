import SwiftUI
import SwiftData

/// Player login view for testing purposes
/// Currently triggers test mode with matching player
struct PlayerLoginView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Player.name) private var players: [Player]

    @AppStorage("isPlayerMode") private var isPlayerMode: Bool = false
    @AppStorage("selectedPlayerID") private var selectedPlayerID: String = ""

    @State private var username: String = ""
    @State private var password: String = ""
    @State private var showingForgotPasswordAlert = false
    @State private var showingLoginError = false
    @State private var isLoggingIn = false
    @State private var loginSuccess = false

    /// Find a player by matching username
    private func findMatchingPlayer() -> Player? {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedUsername.isEmpty else { return nil }

        return players.first { player in
            // Match by username if set
            if let playerUsername = player.username?.lowercased(),
               playerUsername == trimmedUsername {
                return true
            }
            // Also match by player name for testing convenience
            if player.name.lowercased() == trimmedUsername {
                return true
            }
            return false
        }
    }

    private var isFormValid: Bool {
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Theme.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 32) {
                        // Logo/Header Section
                        VStack(spacing: 16) {
                            Image(systemName: "sportscourt.fill")
                                .font(Theme.font(size: 64))
                                .foregroundStyle(Theme.accent)

                            Text("Player Login")
                                .font(Theme.font(size: 28, weight: .bold))
                                .foregroundStyle(Theme.textPrimary)

                            Text("Sign in to view your bets and place wagers")
                                .font(Theme.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 40)

                        // Login Form
                        VStack(spacing: 20) {
                            // Username Field
                            VStack(alignment: .leading, spacing: 8) {
                                Text("USERNAME")
                                    .font(Theme.caption)
                                    .fontWeight(.semibold)
                                    .tracking(1)
                                    .foregroundStyle(Theme.textMuted)

                                HStack(spacing: 12) {
                                    Image(systemName: "person.fill")
                                        .foregroundStyle(Theme.textMuted)
                                        .frame(width: 20)

                                    TextField("", text: $username)
                                        .textContentType(.username)
                                        .autocapitalization(.none)
                                        .autocorrectionDisabled()
                                        .foregroundStyle(Theme.textPrimary)
                                        .placeholder(when: username.isEmpty) {
                                            Text("Enter username")
                                                .foregroundStyle(Theme.textMuted)
                                        }
                                }
                                .padding()
                                .background(Theme.cardBackground)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Theme.border, lineWidth: 1)
                                )
                            }

                            // Password Field
                            VStack(alignment: .leading, spacing: 8) {
                                Text("PASSWORD")
                                    .font(Theme.caption)
                                    .fontWeight(.semibold)
                                    .tracking(1)
                                    .foregroundStyle(Theme.textMuted)

                                HStack(spacing: 12) {
                                    Image(systemName: "lock.fill")
                                        .foregroundStyle(Theme.textMuted)
                                        .frame(width: 20)

                                    SecureField("", text: $password)
                                        .textContentType(.password)
                                        .foregroundStyle(Theme.textPrimary)
                                        .placeholder(when: password.isEmpty) {
                                            Text("Enter password")
                                                .foregroundStyle(Theme.textMuted)
                                        }
                                }
                                .padding()
                                .background(Theme.cardBackground)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Theme.border, lineWidth: 1)
                                )
                            }

                            // Forgot Password Link
                            HStack {
                                Spacer()
                                Button {
                                    showingForgotPasswordAlert = true
                                } label: {
                                    Text("Forgot Password?")
                                        .font(Theme.subheadline)
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                        }
                        .padding(.horizontal, 24)

                        // Login Button
                        Button {
                            attemptLogin()
                        } label: {
                            HStack(spacing: 8) {
                                if isLoggingIn {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: Theme.background))
                                } else if loginSuccess {
                                    Image(systemName: "checkmark")
                                        .font(Theme.headline)
                                } else {
                                    Text("Login")
                                        .font(Theme.headline)
                                }
                            }
                            .foregroundStyle(Theme.background)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                isFormValid
                                    ? Theme.buttonGradient
                                    : LinearGradient(colors: [Theme.textMuted, Theme.textMuted], startPoint: .top, endPoint: .bottom)
                            )
                            .cornerRadius(12)
                            .shadow(color: isFormValid ? Theme.accent.opacity(0.3) : .clear, radius: 8, y: 4)
                        }
                        .disabled(!isFormValid || isLoggingIn)
                        .padding(.horizontal, 24)
                        .animation(.easeInOut(duration: 0.2), value: isFormValid)
                        .animation(.easeInOut(duration: 0.3), value: loginSuccess)

                        // Test Mode Note
                        VStack(spacing: 8) {
                            Text("Test Mode")
                                .font(Theme.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.gold)

                            Text("Enter a player's username or name to login as that player. Password is not validated in test mode.")
                                .font(Theme.caption)
                                .foregroundStyle(Theme.textMuted)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 16)

                        Spacer()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(Theme.textSecondary)
                }
            }
            .toolbarBackground(Theme.cardBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .alert("Forgot Password", isPresented: $showingForgotPasswordAlert) {
                Button("OK") { }
            } message: {
                Text("Password reset is not available in this version. Contact your bookie to reset your credentials.")
            }
            .alert("Login Failed", isPresented: $showingLoginError) {
                Button("OK") { }
            } message: {
                Text("No player found with that username. Please check your credentials and try again.")
            }
        }
    }

    private func attemptLogin() {
        guard isFormValid else { return }

        isLoggingIn = true

        // Simulate brief delay for UX
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let matchingPlayer = findMatchingPlayer() {
                // Success - switch to player mode
                loginSuccess = true

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    selectedPlayerID = matchingPlayer.id.uuidString
                    isPlayerMode = true
                    dismiss()
                }
            } else {
                // No matching player found
                isLoggingIn = false
                showingLoginError = true
            }
        }
    }
}

// MARK: - Placeholder Extension

extension View {
    /// Adds a placeholder overlay when condition is true
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content
    ) -> some View {
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}

// MARK: - Preview

#Preview {
    PlayerLoginView()
        .modelContainer(for: [Player.self], inMemory: true)
}
