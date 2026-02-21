import SwiftUI

/// Container view that manages the onboarding flow
/// Welcome → Profile Setup → Dashboard
struct OnboardingContainerView: View {

    // MARK: - Environment

    @Bindable var onboardingManager: OnboardingManager
    @EnvironmentObject private var authManager: AuthManager

    // MARK: - Properties

    let onComplete: () -> Void
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

    @ViewBuilder
    var body: some View {
        switch onboardingManager.currentStep {
        case .welcome:
            OnboardingWelcomeView(
                onContinue: {
                    withAnimation {
                        onboardingManager.advance()
                    }
                },
                onSkip: {
                    onboardingManager.markAllComplete()
                    onSkip()
                }
            )
            .background(Theme.backgroundGradient)
            .navigationBarHidden(true)
        case .profile:
            OnboardingProfileView(
                onComplete: {
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
}

// MARK: - Preview

#Preview {
    OnboardingContainerView(
        onboardingManager: OnboardingManager(),
        onComplete: { print("Complete") },
        onSkip: { print("Skip") }
    )
}
