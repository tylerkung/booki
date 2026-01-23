import SwiftUI
import SwiftData

/// Full bet slip sheet showing all selections
/// US-040: Build Persistent Bet Slip
/// US-041: Support Multi-Bet (Parlay) Selections
/// US-042: Improved Stake Entry
/// US-043: Bet Confirmation Flow
/// US-051: Style Bet Slip with Premium Feel
struct BetSlipSheet: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var betSlipManager = BetSlipManager.shared
    @Environment(\.dismiss) private var dismiss
    @Query private var bets: [Bet]
    @Query private var ledgerEntries: [LedgerEntry]

    /// Available credit for stake validation (US-042)
    let availableCredit: Decimal

    /// Player for confirmation sheet (US-043)
    let player: Player?

    /// Custom stake text for input field (US-042)
    @State private var stakeText: String = ""

    /// Per-item stake texts for singles mode (US-004)
    @State private var itemStakeTexts: [UUID: String] = [:]

    /// State for submission process (US-006: Direct submission from bet slip)
    @State private var isSubmitting: Bool = false
    @State private var submissionComplete: Bool = false
    @State private var submissionError: String?
    @State private var submittedCount: Int = 0

    /// Animation state for success (US-006)
    @State private var showCheckmark: Bool = false
    @State private var checkmarkScale: CGFloat = 0
    @State private var outerRingScale: CGFloat = 0.8
    @State private var outerRingOpacity: Double = 0

    /// Initialize with available credit for validation and optional player
    init(availableCredit: Decimal = Decimal.greatestFiniteMagnitude, player: Player? = nil) {
        self.availableCredit = availableCredit
        self.player = player
        // Initialize stake text from manager's current stake
        let currentStake = BetSlipManager.shared.stake
        _stakeText = State(initialValue: currentStake > 0 ? "\(NSDecimalNumber(decimal: currentStake).intValue)" : "")
        // Initialize per-item stake texts from manager's existing itemStakes (US-004)
        var initialItemStakeTexts: [UUID: String] = [:]
        for (marketId, stake) in BetSlipManager.shared.itemStakes {
            if stake > 0 {
                initialItemStakeTexts[marketId] = "\(NSDecimalNumber(decimal: stake).intValue)"
            }
        }
        _itemStakeTexts = State(initialValue: initialItemStakeTexts)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // Dark background
                Theme.background.ignoresSafeArea()

                // US-006: Show success view after submission completes
                if submissionComplete {
                    successView
                } else {
                    VStack(spacing: 0) {
                        // Accent border at top
                        Theme.accent
                            .frame(height: 3)

                        if betSlipManager.isEmpty {
                            emptyState
                        } else {
                            selectionsList
                        }
                    }
                }
            }
            .navigationTitle(submissionComplete ? "Success" : "Bet Slip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.cardBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !submissionComplete {
                        Button("Close") {
                            dismiss()
                        }
                        .foregroundStyle(Theme.textSecondary)
                    }
                }

                if !betSlipManager.isEmpty && !submissionComplete {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Clear All", role: .destructive) {
                            withAnimation {
                                betSlipManager.clearAll()
                            }
                        }
                        .foregroundStyle(Theme.danger)
                        .disabled(isSubmitting)
                    }
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

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "ticket")
                .font(.system(size: 48))
                .foregroundStyle(Theme.textMuted)
            Text("No Selections")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.textPrimary)
            Text("Tap odds buttons on game cards to add selections to your bet slip.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }

    // MARK: - Selections List (US-005: Restructured with sticky bottom)

    @ViewBuilder
    private var selectionsList: some View {
        VStack(spacing: 0) {
            // Scrollable content area
            ScrollView {
                VStack(spacing: 16) {
                    // Header with count and mode toggle (US-041)
                    VStack(spacing: 12) {
                        HStack {
                            Text("\(betSlipManager.count) Selection\(betSlipManager.count == 1 ? "" : "s")")
                                .font(.headline)
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text("Max \(betSlipManager.maxSelections)")
                                .font(.caption)
                                .foregroundStyle(Theme.textMuted)
                        }

                        // Singles/Parlay Toggle (US-041) - Styled
                        // US-005: Added .contentShape(Rectangle()) to expand tap area to full button
                        HStack(spacing: 0) {
                            ForEach(BetMode.allCases, id: \.self) { mode in
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        betSlipManager.betMode = mode
                                    }
                                }) {
                                    Text(mode.rawValue)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(betSlipManager.betMode == mode ? Theme.background : Theme.textSecondary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(betSlipManager.betMode == mode ? Theme.accent : Color.clear)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .background(Theme.elevatedBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Theme.border, lineWidth: 1)
                        )
                    }
                    .padding(.horizontal)
                    .padding(.top, 16)

                    // Selections (US-053: animated item transitions, US-004: per-item stakes)
                    VStack(spacing: 12) {
                        ForEach(Array(betSlipManager.items.enumerated()), id: \.element.marketId) { index, item in
                            PremiumBetSlipItemCard(
                                item: item,
                                onRemove: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        betSlipManager.remove(at: index)
                                        // Also remove the stake text for this item
                                        itemStakeTexts.removeValue(forKey: item.marketId)
                                    }
                                },
                                betMode: betSlipManager.betMode,
                                stakeText: itemStakeTextBinding(for: item.marketId),
                                betSlipManager: betSlipManager
                            )
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.9).combined(with: .opacity),
                                removal: .scale(scale: 0.9).combined(with: .opacity).combined(with: .move(edge: .trailing))
                            ))
                        }
                    }
                    .padding(.horizontal)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: betSlipManager.count)

                    // Combined Parlay Odds (US-041)
                    if betSlipManager.betMode == .parlay && betSlipManager.count > 1 {
                        parlayOddsCard
                            .padding(.horizontal)
                    }
                }
                .padding(.bottom, 16)
            }
            .background(Theme.background)

            // US-005: Sticky bottom section with divider
            stickyBottomSection
        }
    }

    // MARK: - Sticky Bottom Section (US-005, US-006)

    @ViewBuilder
    private var stickyBottomSection: some View {
        VStack(spacing: 0) {
            // Subtle divider/shadow at top of sticky section
            Rectangle()
                .fill(Theme.divider)
                .frame(height: 1)
                .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: -2)

            VStack(spacing: 16) {
                // US-006: Different content based on bet mode
                switch betSlipManager.betMode {
                case .parlay:
                    // Parlay mode: stake input, potential payout, Place Bet button
                    stakeEntrySection

                    if betSlipManager.stake > 0 {
                        payoutSummarySection
                    }

                case .singles:
                    // Singles mode: total stake summary (from per-bet stakes), total payout, Place Bet button
                    // No stake entry here since stakes are entered per-card
                    if betSlipManager.individualTotalStake > 0 {
                        singlesSummarySection
                    }

                    // Stake validation warning for singles mode
                    if betSlipManager.individualTotalStake > 0 && !betSlipManager.isIndividualStakeValid(availableCredit: availableCredit) {
                        stakeValidationWarning
                    }
                }

                // Submit Button (US-006: Direct submission without review screen)
                if canSubmit {
                    submitSection
                }
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 16)
            .background(Theme.cardBackground)
        }
    }

    // MARK: - Singles Summary Section (US-006)

    @ViewBuilder
    private var singlesSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SUMMARY")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.textMuted)
                .tracking(1)

            VStack(spacing: 0) {
                // Total stake row (sum of individual bet stakes)
                HStack {
                    Text("Total Stake")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text(formatCurrency(betSlipManager.individualTotalStake))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.textPrimary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                // Bet count
                HStack {
                    Text("\(betSlipManager.count) Bet\(betSlipManager.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                // Divider
                Rectangle()
                    .fill(Theme.divider)
                    .frame(height: 1)

                // Potential payout row - Premium styled with green accent
                HStack {
                    Text("Potential Payout")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text(formatCurrency(betSlipManager.individualTotalPayout))
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.accent)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [Theme.accent.opacity(0.1), Color.clear],
                        startPoint: .trailing,
                        endPoint: .leading
                    )
                )
            }
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.border, lineWidth: 0.5)
            )
        }
    }

    // MARK: - Stake Validation Warning (US-006)

    @ViewBuilder
    private var stakeValidationWarning: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.warning)
            Text("Total stake exceeds available credit (\(formatCurrency(availableCredit)))")
                .font(.caption)
                .foregroundStyle(Theme.warning)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.warning.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Parlay Odds Card

    @ViewBuilder
    private var parlayOddsCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(betSlipManager.count)-Leg Parlay")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text("Combined odds")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            if let parlayOdds = betSlipManager.formattedParlayOdds {
                Text(parlayOdds)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding()
        .background(
            LinearGradient(
                colors: [Theme.accent.opacity(0.15), Theme.cardBackground],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.accent.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Can Submit Check (US-043, US-006)

    /// Whether the bet slip is ready to submit
    private var canSubmit: Bool {
        guard !betSlipManager.isEmpty else { return false }
        guard player != nil else { return false }

        // US-006: Different validation based on bet mode
        switch betSlipManager.betMode {
        case .parlay:
            guard betSlipManager.stake > 0 else { return false }
            return betSlipManager.isStakeValid(availableCredit: availableCredit)
        case .singles:
            guard betSlipManager.individualTotalStake > 0 else { return false }
            return betSlipManager.isIndividualStakeValid(availableCredit: availableCredit)
        }
    }

    // MARK: - Submit Section (US-006: Direct submission without review screen)

    @ViewBuilder
    private var submitSection: some View {
        Button(action: submitBets) {
            HStack(spacing: 8) {
                if isSubmitting {
                    ProgressView()
                        .tint(Theme.background)
                        .padding(.trailing, 4)
                }
                Image(systemName: isSubmitting ? "hourglass" : "checkmark.circle.fill")
                    .font(.title3)
                Text(isSubmitting ? "Submitting..." : "Place Bet")
                    .font(.headline)
                    .fontWeight(.bold)
            }
            .foregroundStyle(Theme.background)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                ZStack {
                    // Gradient background
                    LinearGradient(
                        colors: [Theme.accent, Theme.accent.opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    // Glow effect
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Theme.accent.opacity(0.3))
                        .blur(radius: 8)
                        .offset(y: 4)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: Theme.accent.opacity(0.4), radius: 12, x: 0, y: 4)
        }
        .buttonStyle(PremiumButtonStyle())
        .disabled(isSubmitting)
    }

    // MARK: - Stake Entry Section (US-042)

    @ViewBuilder
    private var stakeEntrySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("STAKE")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.textMuted)
                .tracking(1)

            VStack(spacing: 16) {
                // Custom amount input - Styled
                HStack(spacing: 12) {
                    Text("$")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.gold)

                    TextField("0", text: $stakeText)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
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
                                .font(.title2)
                                .foregroundStyle(Theme.textMuted)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Theme.elevatedBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            stakeText.isEmpty ? Theme.border : Theme.gold.opacity(0.5),
                            lineWidth: stakeText.isEmpty ? 1 : 2
                        )
                )

                // Stake validation warning (US-042)
                if betSlipManager.stake > 0 && !betSlipManager.isStakeValid(availableCredit: availableCredit) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.warning)
                        Text("Stake exceeds available credit (\(formatCurrency(availableCredit)))")
                            .font(.caption)
                            .foregroundStyle(Theme.warning)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.warning.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // Footer note for singles
                if betSlipManager.betMode == .singles && betSlipManager.count > 1 {
                    Text("Stake applies to each of your \(betSlipManager.count) singles bets. Total stake: \(formatCurrency(betSlipManager.totalSinglesStake))")
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                }
            }
            .padding()
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.border, lineWidth: 0.5)
            )
        }
    }

    // MARK: - Payout Summary Section (US-042)

    @ViewBuilder
    private var payoutSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SUMMARY")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.textMuted)
                .tracking(1)

            VStack(spacing: 0) {
                // Total stake row
                HStack {
                    Text("Total Stake")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text(formatCurrency(betSlipManager.currentTotalStake))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.textPrimary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                // Divider
                Rectangle()
                    .fill(Theme.divider)
                    .frame(height: 1)

                // Potential payout row - Premium styled with green accent
                HStack {
                    Text("Potential Payout")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text(formatCurrency(betSlipManager.currentTotalPayout))
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.accent)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [Theme.accent.opacity(0.1), Color.clear],
                        startPoint: .trailing,
                        endPoint: .leading
                    )
                )
            }
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.border, lineWidth: 0.5)
            )
        }
    }

    // MARK: - Success View (US-006: Direct submission with celebration animation)

    @ViewBuilder
    private var successView: some View {
        VStack(spacing: 24) {
            Spacer()

            // Success animation with pulsing rings
            ZStack {
                // Outer expanding ring
                Circle()
                    .stroke(Theme.accent.opacity(outerRingOpacity), lineWidth: 3)
                    .frame(width: 140, height: 140)
                    .scaleEffect(outerRingScale)

                Circle()
                    .fill(Theme.accent.opacity(0.1))
                    .frame(width: 120, height: 120)

                Circle()
                    .fill(Theme.accent.opacity(0.2))
                    .frame(width: 100, height: 100)
                    .scaleEffect(showCheckmark ? 1 : 0.5)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 70))
                    .foregroundStyle(Theme.accent)
                    .scaleEffect(checkmarkScale)
            }
            .onAppear {
                // Staggered celebration animation
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
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.textPrimary)

                Text("\(submittedCount) bet\(submittedCount == 1 ? "" : "s") recorded and pending review")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
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
                    .background(Theme.accent)
                    .foregroundStyle(Theme.background)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding()
        }
        .padding()
        .background(Theme.background)
    }

    // MARK: - Submission Logic (US-006: Direct submission from bet slip)

    private func submitBets() {
        guard canSubmit, let player = player else { return }

        isSubmitting = true

        // Get player's existing bets and ledger entries
        let playerBets = bets.filter { $0.player?.id == player.id }
        let playerLedgerEntries = ledgerEntries.filter { $0.player?.id == player.id }

        var successCount = 0
        var errors: [String] = []

        // For parlay mode, all bets share one ticketId
        // For singles mode, each bet gets its own ticketId
        let parlayTicketId = UUID()

        // Submit each bet from the slip
        for item in betSlipManager.items {
            // Calculate stake for this bet based on mode (US-007)
            let betStake: Decimal
            let ticketId: UUID

            switch betSlipManager.betMode {
            case .singles:
                // US-007: For singles, use individual per-bet stake from itemStakes
                betStake = betSlipManager.getItemStake(marketId: item.marketId)
                // Each single bet gets its own ticket
                ticketId = UUID()
            case .parlay:
                // For parlay, use shared stake and shared ticketId
                betStake = betSlipManager.stake
                ticketId = parlayTicketId
            }

            let result = BetService.submitBet(
                player: player,
                eventId: item.eventId.uuidString,
                market: item.marketType.rawValue,
                side: item.side,
                odds: item.odds,
                stake: betStake,
                existingBets: playerBets,
                ledgerEntries: playerLedgerEntries,
                ticketId: ticketId
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
            // Clear bet slip, stake, and local stake texts
            betSlipManager.clearAll()
            betSlipManager.stake = 0
            itemStakeTexts.removeAll()  // US-007: Clear local stake text state

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

    /// Create a binding for per-item stake text (US-004)
    private func itemStakeTextBinding(for marketId: UUID) -> Binding<String> {
        Binding(
            get: { itemStakeTexts[marketId] ?? "" },
            set: { itemStakeTexts[marketId] = $0 }
        )
    }
}

// MARK: - Premium Bet Slip Item Card (US-051, US-004)

/// Premium styled card for a single bet slip selection
/// US-004: Add stake input to bet cards in singles mode
struct PremiumBetSlipItemCard: View {
    let item: BetSlipItem
    let onRemove: () -> Void

    /// Bet mode to determine if per-bet stake entry is shown (US-004)
    var betMode: BetMode = .singles

    /// Binding to per-item stake text (US-004)
    @Binding var stakeText: String

    /// BetSlipManager for stake calculations (US-004)
    @ObservedObject var betSlipManager: BetSlipManager

    /// Track if stake field is focused (US-004)
    @FocusState private var isStakeFocused: Bool

    private var formattedOdds: String {
        item.odds >= 0 ? "+\(item.odds)" : "\(item.odds)"
    }

    private var marketTypeLabel: String {
        switch item.marketType {
        case .spread: return "SPREAD"
        case .total: return "TOTAL"
        case .moneyline: return "MONEYLINE"
        }
    }

    /// Calculate potential payout for this bet based on its individual stake (US-004)
    private var individualPayout: Decimal {
        let stake = betSlipManager.getItemStake(marketId: item.marketId)
        guard stake > 0 else { return 0 }
        return betSlipManager.calculatePayout(odds: item.odds, stake: stake)
    }

    /// Format currency for display
    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }

    /// Generate a consistent color for a team based on its name
    private func teamColor(for teamName: String) -> Color {
        let colors: [Color] = [
            Color(hex: 0x4A90D9), // Blue
            Color(hex: 0xE74C3C), // Red
            Color(hex: 0x27AE60), // Green
            Color(hex: 0xF39C12), // Orange
            Color(hex: 0x9B59B6), // Purple
            Color(hex: 0x1ABC9C), // Teal
        ]
        let hash = teamName.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return colors[hash % colors.count]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Team logo placeholder (colored circle)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [teamColor(for: item.side), teamColor(for: item.side).opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                    .overlay(
                        Text(String(item.side.prefix(2)).uppercased())
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    )
                    .shadow(color: teamColor(for: item.side).opacity(0.4), radius: 4, x: 0, y: 2)

                VStack(alignment: .leading, spacing: 4) {
                    // Selection/Side
                    Text(item.side)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.textPrimary)

                    // Event description
                    Text(item.eventDescription)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                // Odds badge - Prominent with color
                Text(formattedOdds)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(item.odds >= 0 ? Theme.accent : Theme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        item.odds >= 0
                            ? Theme.accent.opacity(0.15)
                            : Theme.elevatedBackground
                    )
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(
                                item.odds >= 0 ? Theme.accent.opacity(0.3) : Theme.border,
                                lineWidth: 1
                            )
                    )

                // X button to remove
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            // US-004: Per-bet stake input in singles mode
            if betMode == .singles {
                VStack(spacing: 8) {
                    // Divider
                    Rectangle()
                        .fill(Theme.divider)
                        .frame(height: 1)

                    HStack(spacing: 12) {
                        // Stake input
                        HStack(spacing: 6) {
                            Text("$")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Theme.gold)

                            TextField("0", text: $stakeText)
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.textPrimary)
                                .keyboardType(.numberPad)
                                .focused($isStakeFocused)
                                .frame(width: 60)
                                .onChange(of: stakeText) { _, newValue in
                                    // Parse and update per-item stake
                                    if let value = Decimal(string: newValue.filter { $0.isNumber }) {
                                        betSlipManager.setItemStake(marketId: item.marketId, stake: value)
                                    } else if newValue.isEmpty {
                                        betSlipManager.setItemStake(marketId: item.marketId, stake: 0)
                                    }
                                }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Theme.elevatedBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    isStakeFocused ? Theme.gold.opacity(0.5) : Theme.border,
                                    lineWidth: isStakeFocused ? 2 : 1
                                )
                        )

                        Spacer()

                        // Potential payout for this bet
                        if individualPayout > 0 {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("To Win")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textMuted)
                                Text(formatCurrency(individualPayout))
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }

            // Market type footer
            HStack {
                Text(marketTypeLabel)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.textMuted)
                    .tracking(0.5)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Theme.elevatedBackground.opacity(0.5))
        }
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.border, lineWidth: 0.5)
        )
    }
}

// MARK: - Premium Button Style

/// Button style with scale animation for premium feel
struct PremiumButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

#Preview {
    BetSlipSheet(
        availableCredit: 500,
        player: Player(name: "Test Player", email: "test@example.com", creditLimit: 1000)
    )
    .modelContainer(for: [Player.self, Event.self, Bet.self, LedgerEntry.self], inMemory: true)
}
