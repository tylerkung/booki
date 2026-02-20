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

    // MARK: - Computed Properties

    /// Whether onboarding is complete
    var isOnboardingComplete: Bool {
        get { welcomeCompleteStorage }
        set { welcomeCompleteStorage = newValue }
    }

    // MARK: - Methods

    /// Marks onboarding as complete
    func markAllComplete() {
        isOnboardingComplete = true
    }

    /// Resets onboarding state (for testing)
    func reset() {
        isOnboardingComplete = false
    }
}
