import Foundation
import SwiftUI

/// Steps in the onboarding flow
enum OnboardingStep: Int, CaseIterable, Comparable {
    case welcome = 0
    case configure = 1
    case players = 2
    case games = 3
    case success = 4

    static func < (lhs: OnboardingStep, rhs: OnboardingStep) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Human-readable step number (1-4, not counting welcome/success)
    var stepNumber: Int? {
        switch self {
        case .welcome, .success: return nil
        case .configure: return 1
        case .players: return 2
        case .games: return 3
        }
    }

    /// Total numbered steps (for "Step X of Y")
    static var totalNumberedSteps: Int { 3 }
}

/// Service to track onboarding state and progress
/// Persists completion status using @AppStorage for resumability
@MainActor
@Observable
final class OnboardingManager {

    // MARK: - Completion State

    /// Whether the welcome step has been viewed
    @ObservationIgnored
    @AppStorage("onboarding_welcome_complete") private var welcomeCompleteStorage: Bool = false

    /// Whether the configure book step has been completed
    @ObservationIgnored
    @AppStorage("onboarding_configure_complete") private var configureCompleteStorage: Bool = false

    /// Whether the add players step has been completed
    @ObservationIgnored
    @AppStorage("onboarding_players_complete") private var playersCompleteStorage: Bool = false

    /// Whether the import games step has been completed
    @ObservationIgnored
    @AppStorage("onboarding_games_complete") private var gamesCompleteStorage: Bool = false

    // MARK: - Computed Properties

    /// Whether welcome step is complete
    var welcomeComplete: Bool {
        get { welcomeCompleteStorage }
        set { welcomeCompleteStorage = newValue }
    }

    /// Whether configure step is complete
    var configureComplete: Bool {
        get { configureCompleteStorage }
        set { configureCompleteStorage = newValue }
    }

    /// Whether players step is complete
    var playersComplete: Bool {
        get { playersCompleteStorage }
        set { playersCompleteStorage = newValue }
    }

    /// Whether games step is complete
    var gamesComplete: Bool {
        get { gamesCompleteStorage }
        set { gamesCompleteStorage = newValue }
    }

    /// Whether all onboarding steps are complete
    var isOnboardingComplete: Bool {
        welcomeComplete && configureComplete && playersComplete && gamesComplete
    }

    /// Number of completed steps (out of 4)
    var completedStepCount: Int {
        var count = 0
        if configureComplete { count += 1 }
        if playersComplete { count += 1 }
        if gamesComplete { count += 1 }
        return count
    }

    /// The next step that needs to be completed
    var nextIncompleteStep: OnboardingStep {
        if !welcomeComplete { return .welcome }
        if !configureComplete { return .configure }
        if !playersComplete { return .players }
        if !gamesComplete { return .games }
        return .success
    }

    // MARK: - Methods

    /// Marks a step as complete
    func markStepComplete(_ step: OnboardingStep) {
        switch step {
        case .welcome:
            welcomeComplete = true
        case .configure:
            configureComplete = true
        case .players:
            playersComplete = true
        case .games:
            gamesComplete = true
        case .success:
            // Success step completion marks all steps complete
            welcomeComplete = true
            configureComplete = true
            playersComplete = true
            gamesComplete = true
        }
    }

    /// Marks all onboarding as complete (for skip or success)
    func markAllComplete() {
        welcomeComplete = true
        configureComplete = true
        playersComplete = true
        gamesComplete = true
    }

    /// Resets onboarding state (for testing)
    func reset() {
        welcomeComplete = false
        configureComplete = false
        playersComplete = false
        gamesComplete = false
    }

    /// Checks if a specific step is complete
    func isStepComplete(_ step: OnboardingStep) -> Bool {
        switch step {
        case .welcome: return welcomeComplete
        case .configure: return configureComplete
        case .players: return playersComplete
        case .games: return gamesComplete
        case .success: return isOnboardingComplete
        }
    }
}
