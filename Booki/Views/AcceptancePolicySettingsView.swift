import SwiftUI
import SwiftData

/// Settings view for configuring bookie's acceptance policy rules
/// Allows bookie to set thresholds for auto-accepting or queueing bets for review
struct AcceptancePolicySettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var policies: [AcceptancePolicy]

    /// The current policy, or nil if none exists yet
    private var policy: AcceptancePolicy? {
        policies.first
    }

    /// Event lock offset picker options in minutes
    private let lockOffsetOptions = [0, 1, 2, 5, 10, 15, 30]

    var body: some View {
        List {
            // MARK: - Stake Thresholds Section
            Section {
                HStack {
                    Text("Auto-Accept Max")
                    Spacer()
                    TextField("Amount", value: Binding(
                        get: { policy?.autoAcceptMaxStake ?? 100 },
                        set: { newValue in
                            getOrCreatePolicy().autoAcceptMaxStake = newValue
                        }
                    ), format: .currency(code: "USD"))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                }

                HStack {
                    Text("Review Above")
                    Spacer()
                    TextField("Amount", value: Binding(
                        get: { policy?.requireReviewAboveStake ?? 500 },
                        set: { newValue in
                            getOrCreatePolicy().requireReviewAboveStake = newValue
                        }
                    ), format: .currency(code: "USD"))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                }
            } header: {
                Text("Stake Thresholds")
            } footer: {
                Text("Picks up to Auto-Accept Max are automatically accepted. Picks above Review Above require manual review.")
            }
            .listRowBackground(Theme.cardBackground)

            // MARK: - Player Rules Section
            Section {
                Toggle("Auto-Accept New Members", isOn: Binding(
                    get: { policy?.autoAcceptNewPlayers ?? false },
                    set: { newValue in
                        getOrCreatePolicy().autoAcceptNewPlayers = newValue
                    }
                ))

                Stepper("Pick Threshold: \(policy?.newPlayerBetThreshold ?? 5)", value: Binding(
                    get: { policy?.newPlayerBetThreshold ?? 5 },
                    set: { newValue in
                        getOrCreatePolicy().newPlayerBetThreshold = newValue
                    }
                ), in: 1...20)
            } header: {
                Text("Member Rules")
            } footer: {
                Text("New members with fewer than the pick threshold will have picks queued for review unless auto-accept is enabled.")
            }
            .listRowBackground(Theme.cardBackground)

            // MARK: - Parlay Rules Section
            Section {
                Toggle("Auto-Accept Multi-Picks", isOn: Binding(
                    get: { policy?.autoAcceptParlays ?? false },
                    set: { newValue in
                        getOrCreatePolicy().autoAcceptParlays = newValue
                    }
                ))

                Stepper("Max Legs: \(policy?.parlayMaxLegs ?? 4)", value: Binding(
                    get: { policy?.parlayMaxLegs ?? 4 },
                    set: { newValue in
                        getOrCreatePolicy().parlayMaxLegs = newValue
                    }
                ), in: 2...10)
            } header: {
                Text("Multi-Pick Rules")
            } footer: {
                Text("Multi-picks with more legs than the maximum will be queued for review regardless of the toggle.")
            }
            .listRowBackground(Theme.cardBackground)

            // MARK: - Parlay Settlement Section
            Section {
                Picker("Push/Void Handling", selection: Binding(
                    get: { policy?.parlayPushVoidPolicyEnum ?? .reduceLegReprice },
                    set: { newValue in
                        getOrCreatePolicy().parlayPushVoidPolicyEnum = newValue
                    }
                )) {
                    ForEach(ParlayPushVoidPolicy.allCases, id: \.self) { policyOption in
                        Text(policyOption.displayLabel).tag(policyOption)
                    }
                }
            } header: {
                Text("Multi-Pick Settlement")
            } footer: {
                Text(policy?.parlayPushVoidPolicyEnum.explanation ?? ParlayPushVoidPolicy.reduceLegReprice.explanation)
            }
            .listRowBackground(Theme.cardBackground)

            // MARK: - Event Lock Section
            Section {
                Picker("Lock Before Start", selection: Binding(
                    get: { policy?.eventLockOffsetMinutes ?? 0 },
                    set: { newValue in
                        getOrCreatePolicy().eventLockOffsetMinutes = newValue
                    }
                )) {
                    ForEach(lockOffsetOptions, id: \.self) { minutes in
                        Text(lockOffsetLabel(minutes)).tag(minutes)
                    }
                }
            } header: {
                Text("Event Lock")
            } footer: {
                Text("Picks will be blocked this many minutes before the event starts.")
            }
            .listRowBackground(Theme.cardBackground)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Acceptance Rules")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            ensurePolicyExists()
        }
    }

    /// Returns the existing policy or creates a new one with defaults
    @discardableResult
    private func getOrCreatePolicy() -> AcceptancePolicy {
        if let existingPolicy = policy {
            existingPolicy.updatedAt = Date()
            return existingPolicy
        }

        let newPolicy = AcceptancePolicy()
        modelContext.insert(newPolicy)
        return newPolicy
    }

    /// Ensures a policy exists when the view appears
    private func ensurePolicyExists() {
        if policy == nil {
            let newPolicy = AcceptancePolicy()
            modelContext.insert(newPolicy)
        }
    }

    /// Returns a human-readable label for lock offset minutes
    private func lockOffsetLabel(_ minutes: Int) -> String {
        switch minutes {
        case 0:
            return "At start time"
        case 1:
            return "1 minute"
        default:
            return "\(minutes) minutes"
        }
    }
}

#Preview {
    NavigationStack {
        AcceptancePolicySettingsView()
    }
    .modelContainer(for: [AcceptancePolicy.self], inMemory: true)
}
