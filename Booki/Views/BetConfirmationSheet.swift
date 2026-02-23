import SwiftUI
import SwiftData

/// Bet confirmation sheet showing all selections with review and submit functionality
/// US-043: Bet Confirmation Flow
struct BetConfirmationSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var bets: [Bet]
    @Query private var ledgerEntries: [LedgerEntry]

    private var betSlipManager = BetSlipManager.shared

    let player: Player

    init(player: Player) {
        self.player = player
    }

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
            .navigationTitle("Confirm Pick")
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
                         ? "\(betSlipManager.count)-Leg Multi-Pick"
                         : "\(betSlipManager.count) Single\(betSlipManager.count == 1 ? "" : "s")")
                        .font(Theme.headline)

                    if betSlipManager.betMode == .parlay, let parlayOdds = betSlipManager.formattedParlayOdds {
                        Text("Combined Odds: \(parlayOdds)")
                            .font(Theme.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                Spacer()

                // Bet mode badge
                Text(betSlipManager.betMode.rawValue)
                    .font(Theme.caption)
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
                    Text("Stake per Pick")
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text(formatCurrency(betSlipManager.stake))
                }
            }

            // Total stake
            HStack {
                Text("Total Stake")
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(formatCurrency(betSlipManager.currentTotalStake))
                    .fontWeight(.medium)
            }

            Divider()

            // Potential payout
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total Return")
                        .font(Theme.headline)
                    Text("If all picks win")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Text(formatCurrency(betSlipManager.currentTotalPayout))
                    .font(Theme.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.accent)
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
                        .foregroundStyle(Theme.accent)
                    Text("This submission records pick requests with your group. No money is processed or transferred in this app. All picks are subject to organizer approval.")
                        .font(Theme.footnote)
                        .foregroundStyle(Theme.textSecondary)
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
                        .font(Theme.headline)
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
                        .foregroundStyle(Theme.warning)
                    Text("Total stake exceeds available credit (\(formatCurrency(balanceSummary.availableCredit)))")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.warning)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    // MARK: - Success View (US-053: Enhanced celebration animation)

    /// US-053: Outer ring pulse state
    @State private var outerRingScale: CGFloat = 0.8
    @State private var outerRingOpacity: Double = 0

    @ViewBuilder
    private var successView: some View {
        VStack(spacing: 24) {
            Spacer()

            // Success animation (US-053: Enhanced with pulsing rings)
            ZStack {
                // Outer expanding ring
                Circle()
                    .stroke(Color.green.opacity(outerRingOpacity), lineWidth: 3)
                    .frame(width: 140, height: 140)
                    .scaleEffect(outerRingScale)

                Circle()
                    .fill(Color.green.opacity(0.1))
                    .frame(width: 120, height: 120)

                Circle()
                    .fill(Color.green.opacity(0.2))
                    .frame(width: 100, height: 100)
                    .scaleEffect(showCheckmark ? 1 : 0.5)

                Image(systemName: "checkmark.circle.fill")
                    .font(Theme.font(size: 70))
                    .foregroundStyle(Theme.accent)
                    .scaleEffect(checkmarkScale)
            }
            .onAppear {
                // US-053: Staggered celebration animation
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                    showCheckmark = true
                    checkmarkScale = 1.0
                }
                // Outer ring pulse
                withAnimation(.easeOut(duration: 0.6)) {
                    outerRingScale = 1.5
                    outerRingOpacity = 0.5
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.easeOut(duration: 0.4)) {
                        outerRingOpacity = 0
                    }
                }
            }

            VStack(spacing: 8) {
                Text("Request Submitted!")
                    .font(Theme.title2)
                    .fontWeight(.bold)

                Text("\(submittedCount) pick\(submittedCount == 1 ? "" : "s") recorded and pending review")
                    .font(Theme.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            // Done button
            Button(action: {
                dismiss()
            }) {
                Text("Done")
                    .font(Theme.headline)
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

    // MARK: - Submission Logic (US-016: Edge Function)

    private func submitBets() {
        guard canSubmit else { return }

        // Get bookieId from player
        guard let bookieId = player.bookieId else {
            submissionError = "Member is not associated with an organizer"
            return
        }

        isSubmitting = true

        // Capture items to submit before async call
        let itemsToSubmit = betSlipManager.items
        let betMode = betSlipManager.betMode
        let sharedStake = betSlipManager.stake

        // Submit bets via Edge Function
        Task {
            var successCount = 0
            var errors: [String] = []

            for item in itemsToSubmit {
                // Calculate stake for this bet
                let betStake: Decimal
                switch betMode {
                case .singles:
                    betStake = sharedStake
                case .parlay:
                    // For parlay, we create a single combined bet
                    // Note: This simplified version creates individual bets
                    betStake = sharedStake / Decimal(itemsToSubmit.count)
                }

                // Call submit_bet Edge Function
                // Use sideIndicator ('a' or 'b') for the server, not the display name
                let result = await BetService.submitBetToServer(
                    eventId: item.eventId,
                    marketId: item.marketId,
                    side: item.sideIndicator,
                    odds: item.odds,
                    stake: betStake,
                    playerId: player.id,
                    bookieId: bookieId
                )

                switch result {
                case .success(let response):
                    // Create local Bet from server response
                    if let bet = BetService.createLocalBetFromResponse(
                        response,
                        player: player,
                        localSide: item.side,
                        localMarket: item.marketType.rawValue,
                        eventDescription: item.eventDescription,
                        sideIndicator: item.sideIndicator,
                        marketId: item.marketId
                    ) {
                        await MainActor.run {
                            modelContext.insert(bet)
                        }
                        successCount += 1
                    } else {
                        errors.append("Failed to process server response for \(item.side)")
                    }

                case .failure(let error):
                    // Handle different error types
                    if let edgeFunctionError = error as? EdgeFunctionError {
                        switch edgeFunctionError {
                        case .notAuthenticated:
                            errors.append("Not authenticated - please sign in again")
                        case .serverError(_, let message):
                            errors.append(message ?? "Server error for \(item.side)")
                        default:
                            errors.append(edgeFunctionError.localizedDescription)
                        }
                    } else if let betError = error as? BetServiceError {
                        switch betError {
                        case .edgeFunctionError(let message):
                            errors.append(message)
                        default:
                            errors.append("Failed to submit \(item.side)")
                        }
                    } else {
                        errors.append("Failed to submit \(item.side): \(error.localizedDescription)")
                    }
                }
            }

            // Update UI on main thread
            await MainActor.run {
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
                    submissionError = "\(successCount) picks submitted. Some failed:\n" + errors.joined(separator: "\n")
                }
            }
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
        case .alternateSpread: return "Alt Spread"
        case .alternateTotal: return "Alt Total"
        case .teamTotal: return "Team Total"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Event description
            Text(item.eventDescription)
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)

            // Selection with odds
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.side)
                        .font(Theme.subheadline)
                        .fontWeight(.semibold)

                    Text(marketTypeLabel)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer()

                // Odds badge
                Text(formattedOdds)
                    .font(Theme.headline)
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
