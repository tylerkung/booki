import SwiftUI
import SwiftData

/// Bet confirmation sheet showing all selections with review and submit functionality
/// US-043: Bet Confirmation Flow
struct BetConfirmationSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var bets: [Bet]
    @Query private var ledgerEntries: [LedgerEntry]

    @ObservedObject private var betSlipManager = BetSlipManager.shared

    let player: Player

    /// State for submission process
    @State private var isSubmitting: Bool = false
    @State private var submissionComplete: Bool = false
    @State private var submissionError: String?
    @State private var submittedCount: Int = 0

    /// Animation state for success
    @State private var showCheckmark: Bool = false
    @State private var checkmarkScale: CGFloat = 0

    // MARK: - Computed Properties

    /// Player balance summary
    private var balanceSummary: PlayerBalanceSummary {
        let playerBets = bets.filter { $0.player?.id == player.id }
        let playerLedgerEntries = ledgerEntries.filter { $0.player?.id == player.id }
        return BalanceService.playerSummary(
            for: player,
            bets: playerBets,
            ledgerEntries: playerLedgerEntries
        )
    }

    /// Whether stake is valid for submission
    private var canSubmit: Bool {
        guard !betSlipManager.isEmpty else { return false }
        guard betSlipManager.stake > 0 else { return false }
        return betSlipManager.isStakeValid(availableCredit: balanceSummary.availableCredit)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                if submissionComplete {
                    successView
                } else {
                    confirmationContent
                }
            }
            .navigationTitle("Confirm Bet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSubmitting)
                }
            }
            .alert("Submission Error", isPresented: .init(
                get: { submissionError != nil },
                set: { if !$0 { submissionError = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                if let error = submissionError {
                    Text(error)
                }
            }
        }
    }

    // MARK: - Confirmation Content

    @ViewBuilder
    private var confirmationContent: some View {
        VStack(spacing: 0) {
            List {
                // Bet mode header
                betModeSection

                // All selections
                selectionsSection

                // Total stake and payout summary
                summarySection

                // Compliance disclosure
                complianceSection
            }
            .listStyle(.insetGrouped)

            // Confirm button at bottom
            confirmButton
        }
    }

    // MARK: - Bet Mode Section

    @ViewBuilder
    private var betModeSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(betSlipManager.betMode == .parlay
                         ? "\(betSlipManager.count)-Leg Parlay"
                         : "\(betSlipManager.count) Single\(betSlipManager.count == 1 ? "" : "s")")
                        .font(.headline)

                    if betSlipManager.betMode == .parlay, let parlayOdds = betSlipManager.formattedParlayOdds {
                        Text("Combined Odds: \(parlayOdds)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Bet mode badge
                Text(betSlipManager.betMode.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.blue)
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Selections Section

    @ViewBuilder
    private var selectionsSection: some View {
        Section {
            ForEach(betSlipManager.items, id: \.marketId) { item in
                ConfirmationItemRow(item: item)
            }
        } header: {
            Text("Your Selections")
        }
    }

    // MARK: - Summary Section

    @ViewBuilder
    private var summarySection: some View {
        Section {
            // Stake per bet (for singles)
            if betSlipManager.betMode == .singles && betSlipManager.count > 1 {
                HStack {
                    Text("Stake per Bet")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatCurrency(betSlipManager.stake))
                }
            }

            // Total stake
            HStack {
                Text("Total Stake")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatCurrency(betSlipManager.currentTotalStake))
                    .fontWeight(.medium)
            }

            Divider()

            // Potential payout
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Potential Payout")
                        .font(.headline)
                    Text("If all bets win")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(formatCurrency(betSlipManager.currentTotalPayout))
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.green)
            }
        } header: {
            Text("Summary")
        }
    }

    // MARK: - Compliance Section

    @ViewBuilder
    private var complianceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                    Text("This submission records bet requests with your book. No money is wagered or transferred in this app. All bets are subject to bookie approval.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Disclosure")
        }
    }

    // MARK: - Confirm Button

    @ViewBuilder
    private var confirmButton: some View {
        VStack(spacing: 8) {
            Button(action: submitBets) {
                HStack {
                    if isSubmitting {
                        ProgressView()
                            .tint(.white)
                            .padding(.trailing, 4)
                    }
                    Text(isSubmitting ? "Submitting..." : "Confirm & Submit")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(canSubmit && !isSubmitting ? Color.blue : Color.gray)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(!canSubmit || isSubmitting)

            // Credit warning if applicable
            if !betSlipManager.isStakeValid(availableCredit: balanceSummary.availableCredit) && betSlipManager.stake > 0 {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Total stake exceeds available credit (\(formatCurrency(balanceSummary.availableCredit)))")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    // MARK: - Success View

    @ViewBuilder
    private var successView: some View {
        VStack(spacing: 24) {
            Spacer()

            // Success animation
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.1))
                    .frame(width: 120, height: 120)

                Circle()
                    .fill(Color.green.opacity(0.2))
                    .frame(width: 100, height: 100)
                    .scaleEffect(showCheckmark ? 1 : 0.5)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 70))
                    .foregroundStyle(.green)
                    .scaleEffect(checkmarkScale)
            }
            .onAppear {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                    showCheckmark = true
                    checkmarkScale = 1.0
                }
            }

            VStack(spacing: 8) {
                Text("Request Submitted!")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("\(submittedCount) bet\(submittedCount == 1 ? "" : "s") recorded and pending review")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            // Done button
            Button(action: {
                dismiss()
            }) {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding()
        }
        .padding()
    }

    // MARK: - Submission Logic

    private func submitBets() {
        guard canSubmit else { return }

        isSubmitting = true

        // Get player's existing bets and ledger entries
        let playerBets = bets.filter { $0.player?.id == player.id }
        let playerLedgerEntries = ledgerEntries.filter { $0.player?.id == player.id }

        var successCount = 0
        var errors: [String] = []

        // Submit each bet from the slip
        for item in betSlipManager.items {
            // Calculate stake for this bet
            let betStake: Decimal
            switch betSlipManager.betMode {
            case .singles:
                betStake = betSlipManager.stake
            case .parlay:
                // For parlay, we create a single combined bet
                // Note: This simplified version creates individual bets
                // A full parlay implementation would need a ParlayBet model
                betStake = betSlipManager.stake / Decimal(betSlipManager.count)
            }

            let result = BetService.submitBet(
                player: player,
                eventId: item.eventId.uuidString,
                market: item.marketType.rawValue,
                side: item.side,
                odds: item.odds,
                stake: betStake,
                existingBets: playerBets,
                ledgerEntries: playerLedgerEntries
            )

            switch result {
            case .success(let bet):
                modelContext.insert(bet)
                successCount += 1
            case .failure(let error):
                switch error {
                case .insufficientCredit(let available, let required):
                    errors.append("Insufficient credit for \(item.side): Need \(formatCurrency(required)), have \(formatCurrency(available))")
                case .playerNotActive(let status):
                    errors.append("Account is \(status.rawValue)")
                default:
                    errors.append("Failed to submit \(item.side)")
                }
            }
        }

        isSubmitting = false

        if successCount > 0 {
            submittedCount = successCount
            // Clear bet slip and stake
            betSlipManager.clearAll()
            betSlipManager.stake = 0

            // Show success animation
            withAnimation(.easeInOut(duration: 0.3)) {
                submissionComplete = true
            }
        }

        if !errors.isEmpty && successCount == 0 {
            submissionError = errors.joined(separator: "\n")
        } else if !errors.isEmpty {
            // Partial success - some bets failed
            submissionError = "\(successCount) bets submitted. Some failed:\n" + errors.joined(separator: "\n")
        }
    }

    // MARK: - Helpers

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }
}

// MARK: - Confirmation Item Row

/// Row view for a single item in the confirmation list
struct ConfirmationItemRow: View {
    let item: BetSlipItem

    private var formattedOdds: String {
        item.odds >= 0 ? "+\(item.odds)" : "\(item.odds)"
    }

    private var marketTypeLabel: String {
        switch item.marketType {
        case .spread: return "Spread"
        case .total: return "Total"
        case .moneyline: return "Moneyline"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Event description
            Text(item.eventDescription)
                .font(.caption)
                .foregroundStyle(.secondary)

            // Selection with odds
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.side)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text(marketTypeLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Odds badge
                Text(formattedOdds)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    BetConfirmationSheet(player: Player(
        name: "Test Player",
        email: "test@example.com",
        creditLimit: 1000
    ))
    .modelContainer(for: [Player.self, Event.self, Bet.self, LedgerEntry.self], inMemory: true)
}
