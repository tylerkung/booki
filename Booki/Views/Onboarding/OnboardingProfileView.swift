import SwiftUI

/// Onboarding step for setting up the organizer profile (name + email)
struct OnboardingProfileView: View {

    @EnvironmentObject private var authManager: AuthManager

    @State private var name: String = ""
    @State private var email: String = ""
    @State private var isSaving: Bool = false

    let onComplete: () -> Void
    let onSkip: () -> Void

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !email.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon
            Image(systemName: "person.crop.circle.badge.plus")
                .font(Theme.font(size: 56))
                .foregroundStyle(Theme.accent)
                .padding(.bottom, 24)

            // Headline
            Text("Set Up Your Profile")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Text("This is how your members will see you.")
                .font(.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.top, 8)

            // Form fields
            VStack(spacing: 16) {
                TextField("", text: $name)
                    .textContentType(.name)
                    .autocorrectionDisabled()
                    .padding()
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .placeholder(when: name.isEmpty) {
                        Text("Your name")
                            .foregroundStyle(Theme.textMuted)
                            .padding(.leading)
                    }

                TextField("", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .padding()
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .placeholder(when: email.isEmpty) {
                        Text("Email address")
                            .foregroundStyle(Theme.textMuted)
                            .padding(.leading)
                    }
            }
            .padding(.horizontal, 24)
            .padding(.top, 32)

            Spacer()

            // Save button
            Button {
                saveProfile()
            } label: {
                HStack {
                    if isSaving {
                        ProgressView()
                            .tint(Theme.background)
                    } else {
                        Text("Continue")
                            .font(Theme.headline)
                            .textCase(.uppercase)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!isValid || isSaving)
            .padding(.horizontal, 24)

            // Skip
            Button(action: onSkip) {
                Text("Skip for now")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .onAppear {
            // Pre-fill email from auth if available
            Task {
                if let session = try? await SupabaseClientManager.shared.client.auth.session {
                    if let authEmail = session.user.email, email.isEmpty {
                        email = authEmail
                    }
                }
            }
        }
    }

    private func saveProfile() {
        guard let bookieId = authManager.currentBookieId else { return }
        isSaving = true

        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)

        Task {
            do {
                try await BookieService.updateProfile(
                    bookieId: bookieId,
                    name: trimmedName,
                    email: trimmedEmail
                )
            } catch {
                print("Failed to save profile during onboarding: \(error)")
            }
            isSaving = false
            onComplete()
        }
    }
}

#Preview {
    OnboardingProfileView(
        onComplete: { print("Complete") },
        onSkip: { print("Skip") }
    )
    .background(Theme.backgroundGradient)
    .environmentObject(AuthManager())
}
