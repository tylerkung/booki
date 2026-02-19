import SwiftUI

/// Welcome screen for the onboarding flow (Step 1)
/// Introduces the app and its value proposition
struct OnboardingWelcomeView: View {

    // MARK: - Properties

    /// Closure called when user taps "Set up your book"
    let onContinue: () -> Void

    /// Closure called when user taps "Skip for now"
    let onSkip: () -> Void

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // App Logo
            Image("BookiLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 160)
                .padding(.bottom, 32)

            // Headline
            Text("Run your group like a pro.")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            // Body
            Text("Booki helps you track picks, manage members, and run weekly reconciliations.")
                .font(.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.top, 16)

            Spacer()

            // Primary CTA
            Button(action: onContinue) {
                Text("Set Up Your Group")
                    .font(Theme.headline)
                    .textCase(.uppercase)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 24)

            // Secondary CTA
            Button(action: onSkip) {
                Text("Skip for now")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .background(Theme.backgroundGradient)
    }
}

// MARK: - Preview

#Preview {
    OnboardingWelcomeView(
        onContinue: { print("Continue tapped") },
        onSkip: { print("Skip tapped") }
    )
}
