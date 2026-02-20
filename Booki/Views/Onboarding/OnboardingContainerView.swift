import SwiftUI

/// Container view that manages the onboarding flow
/// Shows a single welcome screen, then dismisses to dashboard
struct OnboardingContainerView: View {

    // MARK: - Environment

    @Bindable var onboardingManager: OnboardingManager

    // MARK: - Properties

    /// Called when onboarding is completed
    let onComplete: () -> Void

    /// Called when user skips onboarding
    let onSkip: () -> Void

    // MARK: - Initialization

    init(
        onboardingManager: OnboardingManager,
        onComplete: @escaping () -> Void,
        onSkip: @escaping () -> Void
    ) {
        self.onboardingManager = onboardingManager
        self.onComplete = onComplete
        self.onSkip = onSkip
    }

    // MARK: - Body

    var body: some View {
        OnboardingWelcomeView(
            onContinue: {
                onboardingManager.markAllComplete()
                onComplete()
            },
            onSkip: {
                onboardingManager.markAllComplete()
                onSkip()
            }
        )
        .background(Theme.backgroundGradient)
        .navigationBarHidden(true)
    }
}

// MARK: - Preview

#Preview {
    OnboardingContainerView(
        onboardingManager: OnboardingManager(),
        onComplete: { print("Complete") },
        onSkip: { print("Skip") }
    )
}
