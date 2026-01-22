import SwiftUI
import SwiftData

struct AddMarketSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let event: Event

    @State private var marketType: MarketType = .spread
    @State private var spreadValue: String = ""
    @State private var totalValue: String = ""
    @State private var oddsAString: String = "-110"
    @State private var oddsBString: String = "-110"

    // MARK: - Computed Properties

    private var isFormValid: Bool {
        switch marketType {
        case .spread:
            guard let spread = Double(spreadValue), spread != 0 else { return false }
            return validateOdds()
        case .total:
            guard let total = Double(totalValue), total > 0 else { return false }
            return validateOdds()
        case .moneyline:
            return validateOdds()
        }
    }

    private func validateOdds() -> Bool {
        guard let oddsA = Int(oddsAString), let oddsB = Int(oddsBString) else { return false }
        // American odds must be at least +100 or -100 (not between -99 and +99)
        let validA = oddsA >= 100 || oddsA <= -100
        let validB = oddsB >= 100 || oddsB <= -100
        return validA && validB
    }

    private var sideALabel: String {
        switch marketType {
        case .spread:
            let spread = Double(spreadValue) ?? 0
            let sign = spread > 0 ? "+" : ""
            return "\(event.homeTeam) \(sign)\(spreadValue)"
        case .total:
            return "Over \(totalValue)"
        case .moneyline:
            return event.homeTeam
        }
    }

    private var sideBLabel: String {
        switch marketType {
        case .spread:
            let spread = Double(spreadValue) ?? 0
            let oppositeSpread = -spread
            let sign = oppositeSpread > 0 ? "+" : ""
            return "\(event.awayTeam) \(sign)\(String(format: "%.1f", oppositeSpread).replacingOccurrences(of: ".0", with: ""))"
        case .total:
            return "Under \(totalValue)"
        case .moneyline:
            return event.awayTeam
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Market Type Section
                Section("Market Type") {
                    Picker("Type", selection: $marketType) {
                        Text("Spread").tag(MarketType.spread)
                        Text("Total").tag(MarketType.total)
                        Text("Moneyline").tag(MarketType.moneyline)
                    }
                    .pickerStyle(.segmented)
                }

                // MARK: - Market Details Section
                Section("Market Details") {
                    switch marketType {
                    case .spread:
                        spreadFormFields
                    case .total:
                        totalFormFields
                    case .moneyline:
                        moneylineFormFields
                    }
                }

                // MARK: - Preview Section
                if isFormValid {
                    Section("Preview") {
                        HStack {
                            Text(sideALabel)
                            Spacer()
                            Text(formatOdds(Int(oddsAString) ?? -110))
                                .fontWeight(.semibold)
                        }
                        HStack {
                            Text(sideBLabel)
                            Spacer()
                            Text(formatOdds(Int(oddsBString) ?? -110))
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
            .navigationTitle("Add Market")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveMarket()
                    }
                    .disabled(!isFormValid)
                }
            }
        }
    }

    // MARK: - Form Fields

    @ViewBuilder
    private var spreadFormFields: some View {
        HStack {
            Text(event.homeTeam)
            Spacer()
            TextField("Spread", text: $spreadValue)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
        }

        HStack {
            Text("\(event.homeTeam) Odds")
            Spacer()
            TextField("-110", text: $oddsAString)
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
        }

        HStack {
            Text("\(event.awayTeam) Odds")
            Spacer()
            TextField("-110", text: $oddsBString)
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
        }

        Text("Enter the spread for the home team. Away team spread will be the opposite.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var totalFormFields: some View {
        HStack {
            Text("Total Points")
            Spacer()
            TextField("e.g. 45.5", text: $totalValue)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
        }

        HStack {
            Text("Over Odds")
            Spacer()
            TextField("-110", text: $oddsAString)
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
        }

        HStack {
            Text("Under Odds")
            Spacer()
            TextField("-110", text: $oddsBString)
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
        }
    }

    @ViewBuilder
    private var moneylineFormFields: some View {
        HStack {
            Text("\(event.homeTeam) Odds")
            Spacer()
            TextField("-150", text: $oddsAString)
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
        }

        HStack {
            Text("\(event.awayTeam) Odds")
            Spacer()
            TextField("+130", text: $oddsBString)
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
        }

        Text("Enter American odds (e.g., -110, +150)")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    // MARK: - Helpers

    private func formatOdds(_ odds: Int) -> String {
        odds > 0 ? "+\(odds)" : "\(odds)"
    }

    private func saveMarket() {
        guard let oddsA = Int(oddsAString), let oddsB = Int(oddsBString) else { return }

        let market = Market(
            type: marketType,
            sideA: sideALabel,
            sideB: sideBLabel,
            oddsA: oddsA,
            oddsB: oddsB,
            event: event
        )

        modelContext.insert(market)

        // Add to event's markets array
        if event.markets == nil {
            event.markets = [market]
        } else {
            event.markets?.append(market)
        }

        dismiss()
    }
}

#Preview {
    AddMarketSheet(
        event: Event(
            sport: "NFL",
            league: "Football",
            homeTeam: "Patriots",
            awayTeam: "Jets",
            startTime: Date(),
            status: .scheduled
        )
    )
    .modelContainer(for: [Event.self, Market.self], inMemory: true)
}
