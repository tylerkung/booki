import SwiftUI
import SwiftData

/// Full bet slip sheet showing all selections
/// US-040: Build Persistent Bet Slip
/// US-041: Support Multi-Bet (Parlay) Selections
/// US-042: Improved Stake Entry
/// US-043: Bet Confirmation Flow
/// US-051: Style Bet Slip with Premium Feel
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
            ZStack(alignment: .top) {
                // Dark background
                Theme.background.ignoresSafeArea()

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
            .navigationTitle("Bet Slip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.cardBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundStyle(Theme.textSecondary)
                }

                if !betSlipManager.isEmpty {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Clear All", role: .destructive) {
                            withAnimation {
                                betSlipManager.clearAll()
                            }
                        }
                        .foregroundStyle(Theme.danger)
                    }
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

    // MARK: - Selections List

    @ViewBuilder
    private var selectionsList: some View {
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

                // Selections (US-053: animated item transitions)
                VStack(spacing: 12) {
                    ForEach(Array(betSlipManager.items.enumerated()), id: \.element.marketId) { index, item in
                        PremiumBetSlipItemCard(item: item, onRemove: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                betSlipManager.remove(at: index)
                            }
                        })
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

                // Stake Entry Section (US-042)
                stakeEntrySection
                    .padding(.horizontal)

                // Payout Summary Section (US-042)
                if betSlipManager.stake > 0 {
                    payoutSummarySection
                        .padding(.horizontal)
                }

                // Review & Confirm Button (US-043)
                if canSubmit {
                    reviewConfirmSection
                        .padding(.horizontal)
                        .padding(.bottom, 16)
                }
            }
        }
        .background(Theme.background)
        .sheet(isPresented: $showingConfirmation) {
            if let player = player {
                BetConfirmationSheet(player: player)
            }
        }
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
        Button(action: {
            showingConfirmation = true
        }) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                Text("Review & Confirm")
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
                // Quick-pick stake buttons
                HStack(spacing: 8) {
                    ForEach(BetSlipManager.quickPickAmounts, id: \.self) { amount in
                        PremiumQuickPickButton(
                            amount: amount,
                            isSelected: betSlipManager.stake == amount,
                            action: {
                                betSlipManager.setQuickPickStake(amount)
                                stakeText = "\(NSDecimalNumber(decimal: amount).intValue)"
                            }
                        )
                    }
                }

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

    // MARK: - Helpers

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }
}

// MARK: - Premium Bet Slip Item Card (US-051)

/// Premium styled card for a single bet slip selection
struct PremiumBetSlipItemCard: View {
    let item: BetSlipItem
    let onRemove: () -> Void

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

// MARK: - Premium Quick Pick Button (US-051)

/// Premium styled quick-pick stake button
struct PremiumQuickPickButton: View {
    let amount: Decimal
    let isSelected: Bool
    let action: () -> Void

    @State private var isPressed: Bool = false

    private var formattedAmount: String {
        "$\(NSDecimalNumber(decimal: amount).intValue)"
    }

    var body: some View {
        Button(action: action) {
            Text(formattedAmount)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(isSelected ? Theme.background : Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    isSelected
                        ? AnyView(Theme.gold)
                        : AnyView(Theme.elevatedBackground)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isSelected ? Theme.gold : Theme.border,
                            lineWidth: isSelected ? 0 : 1
                        )
                )
                .scaleEffect(isPressed ? 0.95 : 1.0)
                .shadow(
                    color: isSelected ? Theme.gold.opacity(0.3) : Color.clear,
                    radius: 4,
                    x: 0,
                    y: 2
                )
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.easeInOut(duration: 0.1)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.easeInOut(duration: 0.1)) {
                        isPressed = false
                    }
                }
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
