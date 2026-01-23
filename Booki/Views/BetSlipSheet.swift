import SwiftUI
import SwiftData

/// Full bet slip sheet showing all selections
/// US-040: Build Persistent Bet Slip
/// US-041: Support Multi-Bet (Parlay) Selections
/// US-042: Improved Stake Entry
/// US-043: Bet Confirmation Flow
struct BetSlipSheet: View {
    @ObservedObject private var betSlipManager = BetSlipManager.shared
    @Environment(\.dismiss) private var dismiss

    /// Available credit for stake validation (US-042)
    let availableCredit: Decimal

    /// Player for confirmation sheet (US-043)
    let player: Player?

    /// Custom stake text for input field (US-042)
    @State private var stakeText: String = ""

    /// Show confirmation sheet (US-043)
    @State private var showingConfirmation: Bool = false

    /// Initialize with available credit for validation and optional player
    init(availableCredit: Decimal = Decimal.greatestFiniteMagnitude, player: Player? = nil) {
        self.availableCredit = availableCredit
        self.player = player
        // Initialize stake text from manager's current stake
        let currentStake = BetSlipManager.shared.stake
        _stakeText = State(initialValue: currentStake > 0 ? "\(NSDecimalNumber(decimal: currentStake).intValue)" : "")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if betSlipManager.isEmpty {
                    emptyState
                } else {
                    selectionsList
                }
            }
            .navigationTitle("Bet Slip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }

                if !betSlipManager.isEmpty {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Clear All", role: .destructive) {
                            withAnimation {
                                betSlipManager.clearAll()
                            }
                        }
                        .foregroundStyle(.red)
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        ContentUnavailableView(
            "No Selections",
            systemImage: "ticket",
            description: Text("Tap odds buttons on game cards to add selections to your bet slip.")
        )
    }

    // MARK: - Selections List

    @ViewBuilder
    private var selectionsList: some View {
        List {
            // Header with count and mode toggle (US-041)
            Section {
                VStack(spacing: 12) {
                    HStack {
                        Text("\(betSlipManager.count) Selection\(betSlipManager.count == 1 ? "" : "s")")
                            .font(.headline)
                        Spacer()
                        Text("Max \(betSlipManager.maxSelections)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Singles/Parlay Toggle (US-041)
                    Picker("Bet Mode", selection: $betSlipManager.betMode) {
                        ForEach(BetMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            // Selections
            Section {
                ForEach(Array(betSlipManager.items.enumerated()), id: \.element.marketId) { index, item in
                    BetSlipItemRow(item: item, onRemove: {
                        withAnimation {
                            betSlipManager.remove(at: index)
                        }
                    })
                }
                .onDelete(perform: deleteItems)
            }

            // Combined Parlay Odds (US-041)
            if betSlipManager.betMode == .parlay && betSlipManager.count > 1 {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(betSlipManager.count)-Leg Parlay")
                                .font(.headline)
                            Text("Combined odds")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if let parlayOdds = betSlipManager.formattedParlayOdds {
                            Text(parlayOdds)
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            // Stake Entry Section (US-042)
            stakeEntrySection

            // Payout Summary Section (US-042)
            if betSlipManager.stake > 0 {
                payoutSummarySection
            }

            // Review & Confirm Button (US-043)
            if canSubmit {
                reviewConfirmSection
            }
        }
        .listStyle(.insetGrouped)
        .sheet(isPresented: $showingConfirmation) {
            if let player = player {
                BetConfirmationSheet(player: player)
            }
        }
    }

    // MARK: - Can Submit Check (US-043)

    /// Whether the bet slip is ready to submit
    private var canSubmit: Bool {
        guard !betSlipManager.isEmpty else { return false }
        guard betSlipManager.stake > 0 else { return false }
        guard player != nil else { return false }
        return betSlipManager.isStakeValid(availableCredit: availableCredit)
    }

    // MARK: - Review & Confirm Section (US-043)

    @ViewBuilder
    private var reviewConfirmSection: some View {
        Section {
            Button(action: {
                showingConfirmation = true
            }) {
                HStack {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                    Text("Review & Confirm")
                        .fontWeight(.semibold)
                    Spacer()
                }
                .foregroundStyle(.white)
                .padding(.vertical, 12)
                .background(Color.green)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Stake Entry Section (US-042)

    @ViewBuilder
    private var stakeEntrySection: some View {
        Section {
            VStack(spacing: 16) {
                // Quick-pick stake buttons
                HStack(spacing: 8) {
                    ForEach(BetSlipManager.quickPickAmounts, id: \.self) { amount in
                        QuickPickButton(
                            amount: amount,
                            isSelected: betSlipManager.stake == amount,
                            action: {
                                betSlipManager.setQuickPickStake(amount)
                                stakeText = "\(NSDecimalNumber(decimal: amount).intValue)"
                            }
                        )
                    }
                }

                // Custom amount input
                HStack {
                    Text("$")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    TextField("Custom amount", text: $stakeText)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .keyboardType(.numberPad)
                        .onChange(of: stakeText) { _, newValue in
                            // Parse and update stake
                            if let value = Decimal(string: newValue.filter { $0.isNumber }) {
                                betSlipManager.stake = value
                            } else if newValue.isEmpty {
                                betSlipManager.stake = 0
                            }
                        }

                    Spacer()

                    if !stakeText.isEmpty {
                        Button(action: {
                            stakeText = ""
                            betSlipManager.stake = 0
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // Stake validation warning (US-042)
                if betSlipManager.stake > 0 && !betSlipManager.isStakeValid(availableCredit: availableCredit) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Stake exceeds available credit (\(formatCurrency(availableCredit)))")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Stake")
        } footer: {
            if betSlipManager.betMode == .singles && betSlipManager.count > 1 {
                Text("Stake applies to each of your \(betSlipManager.count) singles bets. Total stake: \(formatCurrency(betSlipManager.totalSinglesStake))")
            }
        }
    }

    // MARK: - Payout Summary Section (US-042)

    @ViewBuilder
    private var payoutSummarySection: some View {
        Section {
            VStack(spacing: 12) {
                // Total stake row
                HStack {
                    Text("Total Stake")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatCurrency(betSlipManager.currentTotalStake))
                        .fontWeight(.medium)
                }

                Divider()

                // Potential payout row
                HStack {
                    Text("Potential Payout")
                        .font(.headline)
                    Spacer()
                    Text(formatCurrency(betSlipManager.currentTotalPayout))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.green)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Summary")
        }
    }

    // MARK: - Helpers

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }

    // MARK: - Delete Handler

    private func deleteItems(at offsets: IndexSet) {
        for index in offsets {
            betSlipManager.remove(at: index)
        }
    }
}

// MARK: - Bet Slip Item Row

/// Row view for a single bet slip selection
/// US-041: Added onRemove callback for X button
struct BetSlipItemRow: View {
    let item: BetSlipItem
    let onRemove: () -> Void

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
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                // Event description
                Text(item.eventDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Selection details
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.side)
                            .font(.headline)

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

            // X button to remove (US-041)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Quick Pick Button (US-042)

/// Button for quick-pick stake amounts
struct QuickPickButton: View {
    let amount: Decimal
    let isSelected: Bool
    let action: () -> Void

    private var formattedAmount: String {
        "$\(NSDecimalNumber(decimal: amount).intValue)"
    }

    var body: some View {
        Button(action: action) {
            Text(formattedAmount)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(isSelected ? .white : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(isSelected ? Color.blue : Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    BetSlipSheet(
        availableCredit: 500,
        player: Player(name: "Test Player", email: "test@example.com", creditLimit: 1000)
    )
    .modelContainer(for: [Player.self, Event.self, Bet.self, LedgerEntry.self], inMemory: true)
}
