import SwiftUI
import SwiftData

struct EditMarketSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let market: Market

    @State private var oddsAString: String = ""
    @State private var oddsBString: String = ""

    // MARK: - Computed Properties

    private var isFormValid: Bool {
        validateOdds()
    }

    private func validateOdds() -> Bool {
        guard let oddsA = Int(oddsAString), let oddsB = Int(oddsBString) else { return false }
        // American odds must be at least +100 or -100 (not between -99 and +99)
        let validA = oddsA >= 100 || oddsA <= -100
        let validB = oddsB >= 100 || oddsB <= -100
        return validA && validB
    }

    private var hasChanges: Bool {
        let oddsA = Int(oddsAString) ?? 0
        let oddsB = Int(oddsBString) ?? 0
        return oddsA != market.oddsA || oddsB != market.oddsB
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Market Info Section (Read-only)
                Section("Market Info") {
                    LabeledContent("Type", value: market.type.rawValue.capitalized)
                    LabeledContent("Side A", value: market.sideA)
                    LabeledContent("Side B", value: market.sideB)
                }

                // MARK: - Odds Section
                Section("Odds") {
                    HStack {
                        Text(market.sideA)
                            .lineLimit(1)
                        Spacer()
                        TextField("Odds", text: $oddsAString)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }

                    HStack {
                        Text(market.sideB)
                            .lineLimit(1)
                        Spacer()
                        TextField("Odds", text: $oddsBString)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }

                    Text("Enter American odds (e.g., -110, +150)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // MARK: - Preview Section
                if isFormValid {
                    Section("Preview") {
                        HStack {
                            Text(market.sideA)
                            Spacer()
                            Text(formatOdds(Int(oddsAString) ?? market.oddsA))
                                .fontWeight(.semibold)
                        }
                        HStack {
                            Text(market.sideB)
                            Spacer()
                            Text(formatOdds(Int(oddsBString) ?? market.oddsB))
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
            .navigationTitle("Edit Market")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                    .disabled(!isFormValid || !hasChanges)
                }
            }
            .onAppear {
                oddsAString = "\(market.oddsA)"
                oddsBString = "\(market.oddsB)"
            }
        }
    }

    // MARK: - Helpers

    private func formatOdds(_ odds: Int) -> String {
        odds > 0 ? "+\(odds)" : "\(odds)"
    }

    private func saveChanges() {
        guard let oddsA = Int(oddsAString), let oddsB = Int(oddsBString) else { return }

        market.oddsA = oddsA
        market.oddsB = oddsB
        market.updatedAt = Date()

        dismiss()
    }
}

#Preview {
    let event = Event(
        sport: "NFL",
        league: "Football",
        homeTeam: "Patriots",
        awayTeam: "Jets",
        startTime: Date(),
        status: .scheduled
    )
    let market = Market(
        type: .spread,
        sideA: "Patriots -7",
        sideB: "Jets +7",
        oddsA: -110,
        oddsB: -110,
        event: event
    )

    return EditMarketSheet(market: market)
        .modelContainer(for: [Event.self, Market.self], inMemory: true)
}
