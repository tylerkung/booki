import SwiftUI
import SwiftData

/// Payment direction enum
enum PaymentDirection: String, CaseIterable, Identifiable {
    case playerPaidBookie = "Player Paid Me"
    case bookiePaidPlayer = "I Paid Player"

    var id: String { rawValue }
}

/// Payment method enum
enum PaymentMethod: String, CaseIterable, Identifiable {
    case cash = "Cash"
    case venmo = "Venmo"
    case zelle = "Zelle"
    case bank = "Bank Transfer"
    case other = "Other"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .cash: return "dollarsign.circle"
        case .venmo: return "v.circle"
        case .zelle: return "z.circle"
        case .bank: return "building.columns"
        case .other: return "ellipsis.circle"
        }
    }
}

struct PaymentSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let player: Player

    @State private var amount: String = ""
    @State private var direction: PaymentDirection = .playerPaidBookie
    @State private var paymentMethod: PaymentMethod = .cash
    @State private var note: String = ""

    private var amountDecimal: Decimal? {
        guard let doubleValue = Double(amount), doubleValue > 0 else { return nil }
        return Decimal(doubleValue)
    }

    private var ledgerAmount: Decimal? {
        guard let value = amountDecimal else { return nil }
        // Player paid bookie = negative (reduces what player owes)
        // Bookie paid player = positive (reduces what bookie owes / increases what player owes)
        return direction == .playerPaidBookie ? -value : value
    }

    private var isValidInput: Bool {
        amountDecimal != nil
    }

    private var paymentDescription: String {
        let methodText = paymentMethod.rawValue
        let directionText = direction == .playerPaidBookie ? "received from" : "paid to"
        var description = "Payment \(directionText) \(player.name) via \(methodText)"
        if !note.trimmingCharacters(in: .whitespaces).isEmpty {
            description += " - \(note.trimmingCharacters(in: .whitespaces))"
        }
        return description
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Amount Section
                Section {
                    HStack {
                        Text("$")
                            .font(Theme.title2)
                            .foregroundStyle(Theme.textMuted)
                        TextField("0.00", text: $amount)
                            .keyboardType(.decimalPad)
                            .font(Theme.title2)
                    }
                } header: {
                    Text("Amount")
                } footer: {
                    Text("Enter the payment amount")
                }
                .listRowBackground(Theme.cardBackground)

                // MARK: - Direction Section
                Section {
                    Picker("Direction", selection: $direction) {
                        ForEach(PaymentDirection.allCases) { dir in
                            Text(dir.rawValue).tag(dir)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Payment Direction")
                } footer: {
                    if direction == .playerPaidBookie {
                        Text("\(player.name) is paying you. This reduces their balance (what they owe).")
                    } else {
                        Text("You are paying \(player.name). This increases their balance (what you owe them becomes what they have in credit).")
                    }
                }
                .listRowBackground(Theme.cardBackground)

                // MARK: - Payment Method Section
                Section {
                    Picker("Method", selection: $paymentMethod) {
                        ForEach(PaymentMethod.allCases) { method in
                            Label(method.rawValue, systemImage: method.icon)
                                .tag(method)
                        }
                    }
                } header: {
                    Text("Payment Method")
                }
                .listRowBackground(Theme.cardBackground)

                // MARK: - Note Section
                Section {
                    TextField("Add a note (optional)", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Note")
                }
                .listRowBackground(Theme.cardBackground)

                // MARK: - Preview Section
                Section {
                    if let displayAmount = amountDecimal, let ledgerAmt = ledgerAmount {
                        LabeledContent("Amount") {
                            Text(formatCurrency(displayAmount))
                                .fontWeight(.semibold)
                        }

                        LabeledContent("Direction") {
                            Text(direction.rawValue)
                        }

                        LabeledContent("Method") {
                            Label(paymentMethod.rawValue, systemImage: paymentMethod.icon)
                        }

                        LabeledContent("Balance Impact") {
                            Text(formatCurrency(ledgerAmt))
                                .foregroundStyle(ledgerAmt < 0 ? Theme.accent : Theme.danger)
                                .fontWeight(.semibold)
                        }

                        if !note.trimmingCharacters(in: .whitespaces).isEmpty {
                            LabeledContent("Note") {
                                Text(note.trimmingCharacters(in: .whitespaces))
                                    .foregroundStyle(Theme.textMuted)
                            }
                        }
                    } else {
                        Text("Enter an amount to see preview")
                            .foregroundStyle(Theme.textMuted)
                            .italic()
                    }
                } header: {
                    Text("Preview")
                }
                .listRowBackground(Theme.cardBackground)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Record Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        savePayment()
                    }
                    .disabled(!isValidInput)
                }
            }
        }
    }

    // MARK: - Actions

    private func savePayment() {
        guard let ledgerAmt = ledgerAmount else { return }

        let ledgerEntry = LedgerEntry(
            amount: ledgerAmt,
            type: .paymentLogged,
            entryDescription: paymentDescription,
            player: player
        )

        modelContext.insert(ledgerEntry)
        dismiss()
    }

    // MARK: - Helpers

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }
}

#Preview {
    PaymentSheet(player: Player(name: "Test Player", creditLimit: 1000))
        .modelContainer(for: [Player.self, LedgerEntry.self], inMemory: true)
}
