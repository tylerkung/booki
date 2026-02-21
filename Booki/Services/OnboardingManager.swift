import Foundation
import SwiftUI

/// Service to track onboarding state
/// Persists completion status using @AppStorage
@MainActor
@Observable
final class OnboardingManager {

    // MARK: - Completion State

    @ObservationIgnored
    @AppStorage("onboarding_welcome_complete") private var welcomeCompleteStorage: Bool = false

    /// Current step in the onboarding flow
    var currentStep: OnboardingStep = .welcome

    enum OnboardingStep {
        case welcome
        case profile
    }

    // MARK: - Computed Properties

    /// Whether onboarding is complete
    var isOnboardingComplete: Bool {
        get { welcomeCompleteStorage }
        set { welcomeCompleteStorage = newValue }
    }

    // MARK: - Methods

    /// Advances to the next onboarding step
    func advance() {
        switch currentStep {
        case .welcome:
            currentStep = .profile
        case .profile:
            markAllComplete()
        }
    }

    /// Marks onboarding as complete
    func markAllComplete() {
        isOnboardingComplete = true
    }

    /// Resets onboarding state (for testing)
    func reset() {
        isOnboardingComplete = false
    }
}
