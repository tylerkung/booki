import SwiftUI
import SwiftData

/// Settlement frequency options
enum SettlementFrequency: String, CaseIterable, Identifiable {
    case weekly = "Weekly"
    case biweekly = "Bi-weekly"
    case monthly = "Monthly"

    var id: String { rawValue }
}

/// Configure book settings screen (Step 2)
/// Allows bookie to set up key operational settings during onboarding
struct OnboardingConfigureView: View {

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @Query private var bookies: [Bookie]

    // MARK: - Properties

    let onContinue: () -> Void

    // MARK: - State

    @State private var settlementFrequency: SettlementFrequency = .weekly
    @State private var autoAcceptBets: Bool = true
    @State private var autoGradeBets: Bool = true
    @State private var defaultCreditLimit: String = "500"

    /// Default credit limit stored in UserDefaults for new players
    @AppStorage("default_credit_limit") private var storedDefaultCreditLimit: Double = 500

    // MARK: - Computed

    private var currentBookie: Bookie? {
        bookies.first
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text("Configure your book")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.textPrimary)

                Text("Set up how your sportsbook operates")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.top, 24)
            .padding(.bottom, 32)

            // Settings Form
            ScrollView {
                VStack(spacing: 20) {
                    // Settlement Frequency
                    settingCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Settlement Frequency")
                                .font(.headline)
                                .foregroundStyle(Theme.textPrimary)

                            Picker("Frequency", selection: $settlementFrequency) {
                                ForEach(SettlementFrequency.allCases) { frequency in
                                    Text(frequency.rawValue).tag(frequency)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    // Bet Acceptance
                    settingCard {
                        Toggle(isOn: $autoAcceptBets) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text("Auto-accept bets")
                                        .font(.headline)
                                        .foregroundStyle(Theme.textPrimary)
                                    Text("(Recommended)")
                                        .font(.caption)
                                        .foregroundStyle(Theme.accent)
                                }
                                Text("Bets are accepted automatically without manual approval")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .tint(Theme.accent)
                    }

                    // Bet Grading
                    settingCard {
                        Toggle(isOn: $autoGradeBets) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text("Auto-grade bets")
                                        .font(.headline)
                                        .foregroundStyle(Theme.textPrimary)
                                    Text("(Recommended)")
                                        .font(.caption)
                                        .foregroundStyle(Theme.accent)
                                }
                                Text("Bets are graded automatically when games finish")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .tint(Theme.accent)
                    }

                    // Default Credit Limit
                    settingCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Default Credit Limit")
                                .font(.headline)
                                .foregroundStyle(Theme.textPrimary)

                            Text("New players will start with this credit limit")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)

                            HStack {
                                Text("$")
                                    .font(.title2)
                                    .foregroundStyle(Theme.textSecondary)

                                TextField("500", text: $defaultCreditLimit)
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Theme.textPrimary)
                                    .keyboardType(.numberPad)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Theme.elevatedBackground)
                            .cornerRadius(Theme.cornerRadiusSmall)
                        }
                    }
                }
                .padding(.horizontal, 24)
            }

            Spacer()

            // Continue Button
            Button(action: saveAndContinue) {
                Text("Continue")
                    .font(Theme.headline)
                    .textCase(.uppercase)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(Theme.backgroundGradient)
    }

    // MARK: - Helper Views

    @ViewBuilder
    private func settingCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardBackground)
            .cornerRadius(Theme.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .stroke(Theme.border, lineWidth: 1)
            )
    }

    // MARK: - Actions

    private func saveAndContinue() {
        // Save settings to Bookie model
        if let bookie = currentBookie {
            bookie.manualBetAcceptance = !autoAcceptBets
            bookie.manualBetGrading = !autoGradeBets
            bookie.updatedAt = Date()
        }

        // Save default credit limit
        if let limit = Double(defaultCreditLimit) {
            storedDefaultCreditLimit = limit
        }

        onContinue()
    }
}

// MARK: - Preview

#Preview {
    OnboardingConfigureView(onContinue: { print("Continue") })
        .modelContainer(for: [Bookie.self])
}
