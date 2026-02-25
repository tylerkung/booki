import SwiftUI
import SwiftData

/// Payment direction enum
enum PaymentDirection: String, CaseIterable, Identifiable {
    case playerPaidBookie = "Member Paid Me"
    case bookiePaidPlayer = "I Paid Member"

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
            ZStack {
                Theme.background.ignoresSafeArea()

                VStack(spacing: 16) {
                    // Amount display
                    Text("$\(amount.isEmpty ? "0" : amount)")
                        .font(Theme.font(size: 36, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)

                    // Direction picker
                    Picker("Direction", selection: $direction) {
                        ForEach(PaymentDirection.allCases) { dir in
                            Text(dir.rawValue).tag(dir)
                        }
                    }
                    .pickerStyle(.segmented)

                    // Payment method + note
                    VStack(spacing: 0) {
                        HStack {
                            Text("Method")
                                .font(Theme.bodyFont(size: 15))
                                .foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Picker("Method", selection: $paymentMethod) {
                                ForEach(PaymentMethod.allCases) { method in
                                    Text(method.rawValue).tag(method)
                                }
                            }
                            .tint(Theme.textPrimary)
                        }
                        .padding(12)

                        Divider().overlay(Theme.elevatedBackground)

                        TextField("Note (optional)", text: $note)
                            .font(Theme.bodyFont(size: 15))
                            .foregroundStyle(Theme.textPrimary)
                            .padding(12)
                    }
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))

                    Text(direction == .playerPaidBookie
                        ? "\(player.name) is paying you"
                        : "You are paying \(player.name)")
                        .font(Theme.bodyFont(size: 12))
                        .foregroundStyle(Theme.textSecondary)

                    Spacer()

                    // Keypad + CTA
                    NumericKeypadView(text: $amount)

                    Button {
                        savePayment()
                    } label: {
                        Text("RECORD PAYMENT")
                            .font(Theme.font(size: 16, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .background(isValidInput ? Theme.accent : Theme.accent.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
                    .disabled(!isValidInput)
                }
                .padding()
            }
            .navigationTitle("Record Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(Theme.accent)
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
