import SwiftUI

/// Dashboard card that prompts bookie to complete onboarding
/// Only shown when onboarding is incomplete
struct FinishSetupCard: View {

    // MARK: - Properties

    @Bindable var onboardingManager: OnboardingManager

    /// Closure called when card is tapped to resume onboarding
    let onResume: () -> Void

    // MARK: - Body

    var body: some View {
        Button(action: onResume) {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Theme.accent.opacity(0.15))
                        .frame(width: 48, height: 48)

                    Image(systemName: "checklist")
                        .font(.title2)
                        .foregroundStyle(Theme.accent)
                }

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text("Finish setting up your book")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)

                    Text("\(onboardingManager.completedStepCount) of 3 steps complete")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.body)
                    .foregroundStyle(Theme.textMuted)
            }
            .padding(16)
            .background(Theme.cardBackground)
            .cornerRadius(Theme.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .stroke(Theme.accent.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    VStack {
        FinishSetupCard(
            onboardingManager: OnboardingManager(),
            onResume: { print("Resume") }
        )
    }
    .padding()
    .background(Theme.background)
}
