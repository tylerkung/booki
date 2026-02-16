import SwiftUI

/// Container view that manages the onboarding step flow
/// Provides progress indicator and navigation between steps
struct OnboardingContainerView: View {

    // MARK: - Environment

    @Bindable var onboardingManager: OnboardingManager

    // MARK: - Properties

    /// Called when onboarding is completed (tapping "Go to Dashboard" on success)
    let onComplete: () -> Void

    /// Called when user skips onboarding
    let onSkip: () -> Void

    // MARK: - State

    @State private var currentStep: OnboardingStep

    // MARK: - Initialization

    init(
        onboardingManager: OnboardingManager,
        startAt step: OnboardingStep? = nil,
        onComplete: @escaping () -> Void,
        onSkip: @escaping () -> Void
    ) {
        self.onboardingManager = onboardingManager
        self.onComplete = onComplete
        self.onSkip = onSkip
        self._currentStep = State(initialValue: step ?? onboardingManager.nextIncompleteStep)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Progress Header (only for numbered steps)
            if let stepNumber = currentStep.stepNumber {
                progressHeader(step: stepNumber)
            }

            // Step Content
            Group {
                switch currentStep {
                case .welcome:
                    OnboardingWelcomeView(
                        onContinue: { advanceToStep(.configure) },
                        onSkip: onSkip
                    )

                case .configure:
                    OnboardingConfigureView(
                        onContinue: {
                            onboardingManager.markStepComplete(.configure)
                            advanceToStep(.players)
                        }
                    )

                case .players:
                    OnboardingAddPlayersView(
                        onContinue: {
                            onboardingManager.markStepComplete(.players)
                            advanceToStep(.games)
                        }
                    )

                case .games:
                    OnboardingImportGamesView(
                        onContinue: {
                            onboardingManager.markStepComplete(.games)
                            advanceToStep(.success)
                        }
                    )

                case .success:
                    OnboardingSuccessView(
                        onComplete: {
                            onboardingManager.markAllComplete()
                            onComplete()
                        }
                    )
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
        }
        .background(Theme.backgroundGradient)
        .animation(.easeInOut(duration: 0.3), value: currentStep)
    }

    // MARK: - Progress Header

    @ViewBuilder
    private func progressHeader(step: Int) -> some View {
        VStack(spacing: 12) {
            // Step indicator
            Text("Step \(step) of \(OnboardingStep.totalNumberedSteps)")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Theme.textSecondary)

            // Progress dots
            HStack(spacing: 8) {
                ForEach(1...OnboardingStep.totalNumberedSteps, id: \.self) { index in
                    Circle()
                        .fill(index <= step ? Theme.accent : Theme.elevatedBackground)
                        .frame(width: 8, height: 8)
                }
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Navigation

    private func advanceToStep(_ step: OnboardingStep) {
        withAnimation {
            // Mark welcome as complete when leaving it
            if currentStep == .welcome {
                onboardingManager.markStepComplete(.welcome)
            }
            currentStep = step
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
