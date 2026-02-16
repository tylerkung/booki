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
    @EnvironmentObject private var authManager: AuthManager
    @ObservedObject private var betSlipManager = BetSlipManager.shared
    @Environment(\.dismiss) private var dismiss
    @Query private var bets: [Bet]
    @Query private var ledgerEntries: [LedgerEntry]
    @Query private var events: [Event]
    @Query private var acceptancePolicies: [AcceptancePolicy]

    /// Available credit for stake validation (US-042)
    let availableCredit: Decimal

    /// Player for confirmation sheet (US-043)
    let player: Player?

    /// Custom stake text for input field (US-042)
    @State private var stakeText: String = ""

    /// US-002: To Win text for parlay mode (bidirectional entry)
    @State private var toWinText: String = ""

    /// US-002: Track which field is actively being edited in parlay mode
    /// Prevents feedback loops when updating one field from the other
    enum ActiveField {
        case wager, toWin
    }
    @State private var parlayActiveField: ActiveField? = nil

    /// Per-item stake texts for singles mode (US-004)
    /// Key is "\(marketId)_\(sideIndicator)" to uniquely identify each selection
    @State private var itemStakeTexts: [String: String] = [:]

    /// US-002: Per-item to-win texts for singles mode (bidirectional entry)
    @State private var itemToWinTexts: [String: String] = [:]

    /// State for submission process (US-006: Direct submission from bet slip)
    @State private var isSubmitting: Bool = false
    @State private var submissionComplete: Bool = false
    @State private var submissionError: String?
    @State private var submittedCount: Int = 0

    /// US-014: Track singles submission progress (1 of N)
    @State private var singlesSubmissionIndex: Int = 0
    @State private var singlesSubmissionTotal: Int = 0

    /// Animation state for success (US-006)
    @State private var showCheckmark: Bool = false
    @State private var checkmarkScale: CGFloat = 0
    @State private var outerRingScale: CGFloat = 0.8
    @State private var outerRingOpacity: Double = 0

    /// US-001: Focus state for parlay wager field
    @FocusState private var isParlayWagerFocused: Bool

    /// US-002: Focus state for parlay to-win field
    @FocusState private var isParlayToWinFocused: Bool

    /// US-009: State for locked events error alert (client-side pre-check)
    @State private var showLockedEventsAlert: Bool = false
    @State private var lockedEventNames: [String] = []

    /// US-013: State for server-reported locked event IDs
    @State private var serverLockedEventIds: Set<String> = []

    /// Initialize with available credit for validation and optional player
    init(availableCredit: Decimal = Decimal.greatestFiniteMagnitude, player: Player? = nil) {
        self.availableCredit = availableCredit
        self.player = player
        let manager = BetSlipManager.shared
        // Initialize stake text from manager's current stake
        let currentStake = manager.stake
        _stakeText = State(initialValue: currentStake > 0 ? "\(NSDecimalNumber(decimal: currentStake).intValue)" : "")
        // US-002: Initialize parlay to-win text from current stake
        if currentStake > 0, let odds = manager.combinedParlayOdds {
            let toWin = manager.calculateToWin(odds: odds, stake: currentStake)
            _toWinText = State(initialValue: toWin > 0 ? Self.formatToWinStatic(toWin) : "")
        }
        // Initialize per-item stake texts from manager's existing itemStakes (US-004)
        var initialItemStakeTexts: [String: String] = [:]
        var initialItemToWinTexts: [String: String] = [:]
        for item in manager.items {
            let key = manager.itemStakeKey(marketId: item.marketId, sideIndicator: item.sideIndicator)
            let stake = manager.itemStakes[key] ?? 0
            if stake > 0 {
                initialItemStakeTexts[key] = "\(NSDecimalNumber(decimal: stake).intValue)"
                // US-002: Initialize per-item to-win texts
                let toWin = manager.calculateToWin(odds: item.odds, stake: stake)
                if toWin > 0 {
                    initialItemToWinTexts[key] = Self.formatToWinStatic(toWin)
                }
            }
        }
        _itemStakeTexts = State(initialValue: initialItemStakeTexts)
        _itemToWinTexts = State(initialValue: initialItemToWinTexts)
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
                        .foregroundStyle(isSubmitting ? Theme.textMuted : Theme.textSecondary)
                        .disabled(isSubmitting)
                    }
                }

                if !betSlipManager.isEmpty && !submissionComplete {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Clear All", role: .destructive) {
                            withAnimation {
                                betSlipManager.clearAll()
                            }
                            // US-002: Auto-dismiss sheet after clearing all selections
                            dismiss()
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
            // US-009/US-013: Alert for locked events (client-side or server-reported)
            .alert("Events Locked", isPresented: $showLockedEventsAlert) {
                // US-013: Offer to remove locked events
                Button("Remove Locked Events", role: .destructive) {
                    removeLockedEvents()
                }
                Button("OK", role: .cancel) { }
            } message: {
                Text("The following events are locked for betting:\n\n\(lockedEventNames.joined(separator: "\n"))\n\nRemove them from your bet slip to continue.")
            }
            // US-005: Sync itemStakeTexts and toWinTexts when mode switches
            .onChange(of: betSlipManager.betMode) { _, newMode in
                if newMode == .singles {
                    for item in betSlipManager.items {
                        let key = betSlipManager.itemStakeKey(marketId: item.marketId, sideIndicator: item.sideIndicator)
                        let stake = betSlipManager.getItemStake(marketId: item.marketId, sideIndicator: item.sideIndicator)
                        if stake > 0 && (itemStakeTexts[key] == nil || itemStakeTexts[key]?.isEmpty == true) {
                            itemStakeTexts[key] = "\(NSDecimalNumber(decimal: stake).intValue)"
                        }
                        // US-002: Also sync to-win texts
                        if stake > 0 && (itemToWinTexts[key] == nil || itemToWinTexts[key]?.isEmpty == true) {
                            let toWin = betSlipManager.calculateToWin(odds: item.odds, stake: stake)
                            itemToWinTexts[key] = toWin > 0 ? formatToWin(toWin) : ""
                        }
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
                        // US-003: Disable parlay when conflicting selections exist
                        HStack(spacing: 0) {
                            ForEach(BetMode.allCases, id: \.self) { mode in
                                let isDisabled = isSubmitting || (mode == .parlay && betSlipManager.hasConflictingSelections)
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        betSlipManager.betMode = mode
                                    }
                                }) {
                                    Text(mode.rawValue)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(
                                            isDisabled ? Theme.textMuted :
                                            (betSlipManager.betMode == mode ? Theme.background : Theme.textSecondary)
                                        )
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(
                                            isDisabled ? Color.clear :
                                            (betSlipManager.betMode == mode ? Theme.accent : Color.clear)
                                        )
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(isDisabled)
                            }
                        }
                        .background(Theme.elevatedBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Theme.border, lineWidth: 1)
                        )

                        // US-003: Show conflict message when parlay is unavailable
                        if let conflictMessage = betSlipManager.conflictDescription {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(Theme.warning)
                                Text(conflictMessage)
                                    .font(.caption)
                                    .foregroundStyle(Theme.warning)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.warning.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        // US-015: Show same-game parlay warning
                        if let sgpWarning = betSlipManager.sameGameParlayWarning {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(Theme.warning)
                                Text(sgpWarning)
                                    .font(.caption)
                                    .foregroundStyle(Theme.warning)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.warning.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        // US-005: Show mode switch message when auto-switched from parlay to singles
                        if let switchMessage = betSlipManager.modeSwitchMessage {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.triangle.swap")
                                    .font(.caption)
                                    .foregroundStyle(Theme.accent)
                                Text(switchMessage)
                                    .font(.caption)
                                    .foregroundStyle(Theme.accent)
                                Spacer()
                                Button {
                                    withAnimation {
                                        betSlipManager.modeSwitchMessage = nil
                                    }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.caption2)
                                        .foregroundStyle(Theme.textMuted)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.accent.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 16)

                    // US-007: Section header based on bet mode
                    HStack {
                        Text(betSlipManager.betMode == .parlay
                             ? "\(betSlipManager.count)-LEG PARLAY"
                             : "STRAIGHT BETS")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.textMuted)
                            .tracking(1.5)
                        Spacer()
                    }
                    .padding(.horizontal)

                    // Selections (US-053: animated item transitions, US-004: per-item stakes)
                    VStack(spacing: 12) {
                        // US-001: Use combination of marketId+side for unique ID to support both sides of same market
                        ForEach(Array(betSlipManager.items.enumerated()), id: \.element) { index, item in
                            PremiumBetSlipItemCard(
                                item: item,
                                onRemove: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        betSlipManager.remove(at: index)
                                        // Also remove the stake text and to-win text for this item
                                        let key = betSlipManager.itemStakeKey(marketId: item.marketId, sideIndicator: item.sideIndicator)
                                        itemStakeTexts.removeValue(forKey: key)
                                        itemToWinTexts.removeValue(forKey: key)
                                        // US-013: Clear locked state for removed item
                                        serverLockedEventIds.remove(item.eventId.uuidString.lowercased())
                                    }
                                },
                                betMode: betSlipManager.betMode,
                                stakeText: itemStakeTextBinding(for: item),
                                toWinText: itemToWinTextBinding(for: item),
                                betSlipManager: betSlipManager,
                                isLocked: serverLockedEventIds.contains(item.eventId.uuidString.lowercased()),
                                isSubmitting: isSubmitting,
                                startTime: events.first(where: { $0.id.uuidString.lowercased() == item.eventId.uuidString.lowercased() })?.startTime
                            )
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.9).combined(with: .opacity),
                                removal: .scale(scale: 0.9).combined(with: .opacity).combined(with: .move(edge: .trailing))
                            ))
                        }
                    }
                    .padding(.horizontal)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: betSlipManager.count)

                    // Combined Parlay Odds + Wager/To Win (US-041, US-008)
                    if betSlipManager.betMode == .parlay && betSlipManager.count > 1 {
                        parlayOddsCard
                            .padding(.horizontal)

                        // US-008: Parlay stake entry directly below odds card
                        parlayStakeEntrySection
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
                    // US-008: Stake entry moved above (below parlay odds card)
                    // Sticky bottom only shows summary + Place Bet
                    if betSlipManager.stake > 0 {
                        payoutSummarySection
                    }

                    // Stake validation warning for parlay mode (US-042)
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
                // Number of bets row
                HStack {
                    Text("Number of Bets")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text("\(singlesItemsWithStake)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.textPrimary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Rectangle()
                    .fill(Theme.divider)
                    .frame(height: 1)

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
                .padding(.vertical, 10)

                Rectangle()
                    .fill(Theme.divider)
                    .frame(height: 1)

                // Potential payout row - Premium styled with accent highlight
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

    /// US-009: Count of items that have a stake entered (for summary display)
    private var singlesItemsWithStake: Int {
        betSlipManager.items.filter { item in
            betSlipManager.getItemStake(marketId: item.marketId, sideIndicator: item.sideIndicator) > 0
        }.count
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

    // MARK: - Parlay Stake Entry Section (US-008)

    /// US-008: Side-by-side Wager/To Win fields with quick stake buttons
    /// Placed directly below the parlay odds card in the scrollable area
    @ViewBuilder
    private var parlayStakeEntrySection: some View {
        VStack(spacing: 12) {
            // Side-by-side WAGER and TO WIN fields
            HStack(spacing: 12) {
                // WAGER field
                VStack(alignment: .leading, spacing: 6) {
                    Text("WAGER")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(isParlayWagerFocused ? Theme.gold : Theme.textMuted)
                        .tracking(1)
                        .animation(.easeInOut(duration: 0.15), value: isParlayWagerFocused)

                    HStack(spacing: 4) {
                        Text("$")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Theme.gold)

                        TextField("0", text: $stakeText)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(isSubmitting ? Theme.textMuted : Theme.textPrimary)
                            .keyboardType(.numberPad)
                            .disabled(isSubmitting)
                            .focused($isParlayWagerFocused)
                            .onChange(of: stakeText) { _, newValue in
                                guard parlayActiveField == .wager else { return }
                                if let value = Decimal(string: newValue.filter { $0.isNumber }) {
                                    betSlipManager.stake = value
                                    if let odds = betSlipManager.combinedParlayOdds {
                                        let calculatedToWin = betSlipManager.calculateToWin(odds: odds, stake: value)
                                        toWinText = calculatedToWin > 0 ? formatToWin(calculatedToWin) : ""
                                    }
                                } else if newValue.isEmpty {
                                    betSlipManager.stake = 0
                                    toWinText = ""
                                }
                            }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Theme.elevatedBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                isParlayWagerFocused ? Theme.gold.opacity(0.6) : Theme.border,
                                lineWidth: isParlayWagerFocused ? 2 : 1
                            )
                    )
                    .animation(.easeInOut(duration: 0.15), value: isParlayWagerFocused)
                }

                // TO WIN field
                VStack(alignment: .leading, spacing: 6) {
                    Text("TO WIN")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(isParlayToWinFocused ? Theme.accent : Theme.textMuted)
                        .tracking(1)
                        .animation(.easeInOut(duration: 0.15), value: isParlayToWinFocused)

                    HStack(spacing: 4) {
                        Text("$")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(isParlayToWinFocused ? Theme.accent : (parlayToWin > 0 ? Theme.accent : Theme.textMuted))
                            .animation(.easeInOut(duration: 0.15), value: isParlayToWinFocused)

                        TextField("0", text: $toWinText)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(isSubmitting ? Theme.textMuted : (isParlayToWinFocused ? Theme.accent : (parlayToWin > 0 ? Theme.accent : Theme.textMuted)))
                            .keyboardType(.numberPad)
                            .disabled(isSubmitting)
                            .focused($isParlayToWinFocused)
                            .onChange(of: toWinText) { _, newValue in
                                guard parlayActiveField == .toWin else { return }
                                if let toWinValue = Decimal(string: newValue.filter { $0.isNumber }), toWinValue > 0 {
                                    if let odds = betSlipManager.combinedParlayOdds {
                                        let calculatedWager = betSlipManager.calculateWagerFromToWin(odds: odds, toWin: toWinValue)
                                        betSlipManager.stake = calculatedWager
                                        let wagerInt = NSDecimalNumber(decimal: calculatedWager).intValue
                                        stakeText = wagerInt > 0 ? "\(wagerInt)" : ""
                                    }
                                } else if newValue.isEmpty {
                                    betSlipManager.stake = 0
                                    stakeText = ""
                                }
                            }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Theme.elevatedBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                isParlayToWinFocused ? Theme.accent.opacity(0.6) : Theme.border,
                                lineWidth: isParlayToWinFocused ? 2 : 1
                            )
                    )
                    .animation(.easeInOut(duration: 0.15), value: isParlayToWinFocused)
                }
            }
            // Track active field based on focus changes
            .onChange(of: isParlayWagerFocused) { _, focused in
                if focused { parlayActiveField = .wager }
            }
            .onChange(of: isParlayToWinFocused) { _, focused in
                if focused { parlayActiveField = .toWin }
            }

            // Quick stake buttons below Wager/To Win
            QuickStakeRow { amount in
                let currentStake = betSlipManager.stake
                let newStake = currentStake + amount
                betSlipManager.stake = newStake
                stakeText = "\(NSDecimalNumber(decimal: newStake).intValue)"
                if let odds = betSlipManager.combinedParlayOdds {
                    let calculatedToWin = betSlipManager.calculateToWin(odds: odds, stake: newStake)
                    toWinText = calculatedToWin > 0 ? formatToWin(calculatedToWin) : ""
                }
            }
            .disabled(isSubmitting)
        }
        .padding()
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.border, lineWidth: 0.5)
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

    // MARK: - Submit Button Label (US-014)

    /// US-014: Mode-specific submit button label
    private var submitButtonLabel: String {
        guard isSubmitting else { return "Place Bet" }
        switch betSlipManager.betMode {
        case .parlay:
            return "Submitting parlay..."
        case .singles:
            if singlesSubmissionTotal > 1 {
                return "Submitting \(singlesSubmissionIndex) of \(singlesSubmissionTotal)..."
            }
            return "Submitting..."
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
                Text(submitButtonLabel)
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
                        colors: isSubmitting
                            ? [Theme.accent.opacity(0.6), Theme.accent.opacity(0.4)]
                            : [Theme.accent, Theme.accent.opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    // Glow effect (hidden during submission)
                    if !isSubmitting {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Theme.accent.opacity(0.3))
                            .blur(radius: 8)
                            .offset(y: 4)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: Theme.accent.opacity(isSubmitting ? 0.2 : 0.4), radius: 12, x: 0, y: 4)
        }
        .buttonStyle(PremiumButtonStyle())
        .disabled(isSubmitting)
    }

    /// US-001: Calculate "to win" for parlay mode display
    private var parlayToWin: Decimal {
        guard betSlipManager.stake > 0 else { return 0 }
        if let odds = betSlipManager.combinedParlayOdds {
            return betSlipManager.calculateToWin(odds: odds, stake: betSlipManager.stake)
        }
        return 0
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

    // MARK: - Locked Events Validation (US-009)

    /// Check if any events in the bet slip are locked and return their names
    private func getLockedEventNames() -> [String] {
        // Get lock offset from policy (default 0)
        let lockOffset = acceptancePolicies.first?.eventLockOffsetMinutes ?? 0

        var lockedNames: [String] = []
        for item in betSlipManager.items {
            if let event = events.first(where: { $0.id == item.eventId }) {
                if event.isLocked(offsetMinutes: lockOffset) {
                    // Use the event description from the bet slip item
                    lockedNames.append(item.eventDescription)
                }
            }
        }
        return lockedNames
    }

    /// US-013: Parse locked event IDs from server error message format "Events locked: [id1, id2]"
    static func parseLockedEventIds(from message: String) -> [String] {
        guard let range = message.range(of: "Events locked: [") else { return [] }
        let afterPrefix = message[range.upperBound...]
        guard let closingBracket = afterPrefix.firstIndex(of: "]") else { return [] }
        let idsString = afterPrefix[..<closingBracket]
        return idsString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// US-013: Remove all locked events from the bet slip
    private func removeLockedEvents() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            let indicesToRemove = betSlipManager.items.enumerated().compactMap { index, item -> Int? in
                serverLockedEventIds.contains(item.eventId.uuidString.lowercased()) ? index : nil
            }
            // Remove from highest index to lowest to maintain valid indices
            for index in indicesToRemove.reversed() {
                let item = betSlipManager.items[index]
                let key = betSlipManager.itemStakeKey(marketId: item.marketId, sideIndicator: item.sideIndicator)
                itemStakeTexts.removeValue(forKey: key)
                itemToWinTexts.removeValue(forKey: key)
                betSlipManager.remove(at: index)
            }
            serverLockedEventIds.removeAll()
        }
    }

    // MARK: - Submission Logic (US-006: Direct submission from bet slip, US-016: Edge Function)

    private func submitBets() {
        guard canSubmit, let player = player else { return }

        // US-009: Check for locked events before submission
        let lockedEvents = getLockedEventNames()
        if !lockedEvents.isEmpty {
            lockedEventNames = lockedEvents
            showLockedEventsAlert = true
            return
        }

        isSubmitting = true

        // Get bookieId - prefer authManager.currentBookieId, fall back to player.bookieId
        let bookieId: UUID
        if let currentBookieId = authManager.currentBookieId {
            // Bookie is logged in - use their bookie ID
            bookieId = currentBookieId
        } else if let playerBookieId = player.bookieId {
            // Player is logged in - use the player's associated bookie ID
            bookieId = playerBookieId
        } else {
            isSubmitting = false
            submissionError = "Player is not associated with a bookie"
            return
        }

        // DEBUG: Log IDs being sent
        print("DEBUG submitBets: player.id = \(player.id)")
        print("DEBUG submitBets: bookieId = \(bookieId)")
        print("DEBUG submitBets: player.bookieId = \(player.bookieId?.uuidString ?? "nil")")
        print("DEBUG submitBets: authManager.currentBookieId = \(authManager.currentBookieId?.uuidString ?? "nil")")
        print("DEBUG submitBets: player.name = \(player.name)")

        // Capture items to submit before async call
        let itemsToSubmit = betSlipManager.items
        let betMode = betSlipManager.betMode
        let sharedStake = betSlipManager.stake
        let itemStakesSnapshot = betSlipManager.itemStakes
        let combinedOdds = betSlipManager.combinedParlayOdds ?? 0

        // Submit bets via Edge Function (US-016, US-004: parlay endpoint)
        Task {
            var successCount = 0
            var errors: [String] = []

            if betMode == .parlay {
                // US-004: Single network call for parlay via submit_parlay endpoint
                guard sharedStake > 0 else {
                    await MainActor.run {
                        isSubmitting = false
                        submissionError = "No stake set for parlay"
                    }
                    return
                }

                let legs = itemsToSubmit.map { item in
                    ParlayLeg(
                        eventId: item.eventId.uuidString,
                        marketId: item.marketId.uuidString,
                        side: item.side,
                        sideIndicator: item.sideIndicator,
                        odds: item.odds
                    )
                }

                let result = await BetService.submitParlayToServer(
                    legs: legs,
                    stake: sharedStake,
                    playerId: player.id,
                    bookieId: bookieId,
                    combinedOdds: combinedOdds
                )

                switch result {
                case .success(let response):
                    let localBets = BetService.createLocalBetsFromParlayResponse(
                        response,
                        player: player,
                        items: itemsToSubmit,
                        events: events
                    )
                    if !localBets.isEmpty {
                        await MainActor.run {
                            for bet in localBets {
                                modelContext.insert(bet)
                            }
                        }
                        successCount = localBets.count
                    } else {
                        errors.append("Failed to process parlay server response")
                    }

                case .failure(let error):
                    var errorMessage = "Failed to submit parlay"
                    if let edgeFunctionError = error as? EdgeFunctionError {
                        switch edgeFunctionError {
                        case .notAuthenticated:
                            errorMessage = "Not authenticated - please sign in again"
                        case .serverError(_, let message):
                            errorMessage = message ?? "Server error submitting parlay"
                        default:
                            errorMessage = edgeFunctionError.localizedDescription
                        }
                    } else if let betError = error as? BetServiceError {
                        switch betError {
                        case .edgeFunctionError(let message):
                            errorMessage = message
                        default:
                            break
                        }
                    } else {
                        errorMessage = "Failed to submit parlay: \(error.localizedDescription)"
                    }

                    // US-013: Parse locked event IDs from server error
                    let parsedLockedIds = Self.parseLockedEventIds(from: errorMessage)
                    if !parsedLockedIds.isEmpty {
                        await MainActor.run {
                            serverLockedEventIds = Set(parsedLockedIds.map { $0.lowercased() })
                            // Build names for the alert
                            lockedEventNames = parsedLockedIds.compactMap { lockedId in
                                let normalizedId = lockedId.lowercased()
                                if let item = itemsToSubmit.first(where: { $0.eventId.uuidString.lowercased() == normalizedId }) {
                                    return item.eventDescription
                                }
                                return "Event \(lockedId.prefix(8))"
                            }
                            showLockedEventsAlert = true
                        }
                    } else {
                        errors.append(errorMessage)
                    }
                }
            } else {
                // Singles mode: existing per-bet loop calling submitBetToServer()
                // US-014: Track submission progress
                let validItems = itemsToSubmit.filter { item in
                    let key = betSlipManager.itemStakeKey(marketId: item.marketId, sideIndicator: item.sideIndicator)
                    return (itemStakesSnapshot[key] ?? 0) > 0
                }
                await MainActor.run {
                    singlesSubmissionTotal = validItems.count
                    singlesSubmissionIndex = 1
                }

                for item in itemsToSubmit {
                    let key = betSlipManager.itemStakeKey(marketId: item.marketId, sideIndicator: item.sideIndicator)
                    let betStake = itemStakesSnapshot[key] ?? 0

                    // Skip items with zero stake
                    guard betStake > 0 else {
                        errors.append("No stake set for \(item.side)")
                        continue
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
                        let matchedEvent = events.first(where: { $0.id.uuidString.lowercased() == item.eventId.uuidString.lowercased() })
                        if let bet = BetService.createLocalBetFromResponse(
                            response,
                            player: player,
                            localSide: item.side,
                            localMarket: item.marketType.rawValue,
                            eventDescription: item.eventDescription,
                            sportLeague: matchedEvent?.league,
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

                    // US-014: Increment singles progress counter
                    await MainActor.run {
                        singlesSubmissionIndex += 1
                    }
                }
            }

            // Update UI on main thread
            await MainActor.run {
                isSubmitting = false

                if successCount > 0 {
                    submittedCount = successCount
                    // Clear bet slip, stake, and local stake/to-win texts
                    betSlipManager.clearAll()
                    betSlipManager.stake = 0
                    itemStakeTexts.removeAll()
                    itemToWinTexts.removeAll()
                    toWinText = ""
                    stakeText = ""

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
        }
    }

    // MARK: - Helpers

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }

    /// US-001: Format "to win" amount without currency symbol (shown separately)
    private func formatToWin(_ value: Decimal) -> String {
        Self.formatToWinStatic(value)
    }

    /// US-002: Static version for use in init
    private static func formatToWinStatic(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }

    /// Create a binding for per-item stake text (US-004)
    /// Uses unique key combining marketId and sideIndicator
    private func itemStakeTextBinding(for item: BetSlipItem) -> Binding<String> {
        let key = betSlipManager.itemStakeKey(marketId: item.marketId, sideIndicator: item.sideIndicator)
        return Binding(
            get: { itemStakeTexts[key] ?? "" },
            set: { itemStakeTexts[key] = $0 }
        )
    }

    /// US-002: Create a binding for per-item to-win text (bidirectional entry)
    private func itemToWinTextBinding(for item: BetSlipItem) -> Binding<String> {
        let key = betSlipManager.itemStakeKey(marketId: item.marketId, sideIndicator: item.sideIndicator)
        return Binding(
            get: { itemToWinTexts[key] ?? "" },
            set: { itemToWinTexts[key] = $0 }
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

    /// US-002: Binding to per-item to-win text (bidirectional entry)
    @Binding var toWinText: String

    /// BetSlipManager for stake calculations (US-004)
    @ObservedObject var betSlipManager: BetSlipManager

    /// US-013: Whether this item's event is locked (server-reported)
    var isLocked: Bool = false

    /// US-014: Whether submission is in progress (disables inputs)
    var isSubmitting: Bool = false

    /// US-004 (betslip-redesign): Game start time for display on bet card
    var startTime: Date? = nil

    /// Track if stake field is focused (US-004)
    @FocusState private var isStakeFocused: Bool

    /// US-002: Track if to-win field is focused
    @FocusState private var isToWinFocused: Bool

    /// US-002: Track which field is actively being edited
    @State private var activeField: BetSlipSheet.ActiveField? = nil

    private var formattedOdds: String {
        item.odds >= 0 ? "+\(item.odds)" : "\(item.odds)"
    }

    private var marketTypeLabel: String {
        item.marketType.displayName.uppercased()
    }

    /// Calculate potential payout for this bet based on its individual stake (US-004)
    private var individualPayout: Decimal {
        let stake = betSlipManager.getItemStake(marketId: item.marketId, sideIndicator: item.sideIndicator)
        guard stake > 0 else { return 0 }
        return betSlipManager.calculatePayout(odds: item.odds, stake: stake)
    }

    /// US-001: Calculate "to win" (profit only) for this bet
    private var individualToWin: Decimal {
        let stake = betSlipManager.getItemStake(marketId: item.marketId, sideIndicator: item.sideIndicator)
        guard stake > 0 else { return 0 }
        return betSlipManager.calculateToWin(odds: item.odds, stake: stake)
    }

    /// Format currency for display
    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }

    /// US-001: Format "to win" amount without currency symbol
    private func formatToWin(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }

    /// US-004: Format game start time as "Thu 7:10 PM"
    private static func formatGameTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE h:mm a"
        return formatter.string(from: date)
    }

    var body: some View {
        VStack(spacing: 0) {
            // US-013: Locked event warning banner
            if isLocked {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                    Text("Event Locked")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(Theme.danger)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Theme.danger.opacity(0.15))
            }

            // US-005: Redesigned bet card layout - no team circles
            HStack(alignment: .top, spacing: 12) {
                // Left: Selection info stacked vertically
                VStack(alignment: .leading, spacing: 4) {
                    // Line 1: Selection name (bold) with odds badge on right
                    HStack(alignment: .center) {
                        Text(item.side)
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundStyle(Theme.textPrimary)

                        Spacer()

                        // Odds badge
                        Text(formattedOdds)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(item.odds >= 0 ? Theme.accent : Theme.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
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
                    }

                    // Line 2: Event matchup
                    Text(item.eventDescription)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)

                    // Line 3: Game start time (US-004)
                    if let startTime = startTime {
                        Text(Self.formatGameTime(startTime))
                            .font(.caption)
                            .foregroundStyle(Theme.textMuted)
                    }
                }

                // Right: Remove button (X) - more prominent
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(isSubmitting ? Theme.textMuted.opacity(0.3) : Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .disabled(isSubmitting)
            }
            .padding(16)

            // US-004/US-001: Per-bet stake input in singles mode with WAGER/TO WIN
            if betMode == .singles {
                VStack(spacing: 8) {
                    // Divider
                    Rectangle()
                        .fill(Theme.divider)
                        .frame(height: 1)

                    HStack(spacing: 12) {
                        // WAGER field
                        VStack(alignment: .leading, spacing: 4) {
                            Text("WAGER")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(isStakeFocused ? Theme.gold : Theme.textMuted)
                                .tracking(0.5)
                                .animation(.easeInOut(duration: 0.15), value: isStakeFocused)

                            HStack(spacing: 4) {
                                Text("$")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Theme.gold)

                                TextField("0", text: $stakeText)
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(isSubmitting ? Theme.textMuted : Theme.textPrimary)
                                    .keyboardType(.numberPad)
                                    .focused($isStakeFocused)
                                    .frame(minWidth: 40)
                                    .disabled(isSubmitting)
                                    .onChange(of: stakeText) { _, newValue in
                                        guard activeField == .wager else { return }
                                        if let value = Decimal(string: newValue.filter { $0.isNumber }) {
                                            betSlipManager.setItemStake(marketId: item.marketId, sideIndicator: item.sideIndicator, stake: value)
                                            // US-002: Update to-win text from wager
                                            let calculatedToWin = betSlipManager.calculateToWin(odds: item.odds, stake: value)
                                            toWinText = calculatedToWin > 0 ? formatToWin(calculatedToWin) : ""
                                        } else if newValue.isEmpty {
                                            betSlipManager.setItemStake(marketId: item.marketId, sideIndicator: item.sideIndicator, stake: 0)
                                            toWinText = ""
                                        }
                                    }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Theme.elevatedBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(
                                        isStakeFocused ? Theme.gold.opacity(0.6) : Theme.border,
                                        lineWidth: isStakeFocused ? 2 : 1
                                    )
                            )
                            .animation(.easeInOut(duration: 0.15), value: isStakeFocused)
                        }

                        // US-002: TO WIN field (editable, bidirectional with wager)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("TO WIN")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(isToWinFocused ? Theme.accent : Theme.textMuted)
                                .tracking(0.5)
                                .animation(.easeInOut(duration: 0.15), value: isToWinFocused)

                            HStack(spacing: 4) {
                                Text("$")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(isToWinFocused ? Theme.accent : (individualToWin > 0 ? Theme.accent : Theme.textMuted))
                                    .animation(.easeInOut(duration: 0.15), value: isToWinFocused)

                                TextField("0", text: $toWinText)
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(isSubmitting ? Theme.textMuted : (isToWinFocused ? Theme.accent : (individualToWin > 0 ? Theme.accent : Theme.textMuted)))
                                    .keyboardType(.numberPad)
                                    .focused($isToWinFocused)
                                    .frame(minWidth: 40)
                                    .disabled(isSubmitting)
                                    .onChange(of: toWinText) { _, newValue in
                                        guard activeField == .toWin else { return }
                                        if let toWinValue = Decimal(string: newValue.filter { $0.isNumber }), toWinValue > 0 {
                                            let calculatedWager = betSlipManager.calculateWagerFromToWin(odds: item.odds, toWin: toWinValue)
                                            betSlipManager.setItemStake(marketId: item.marketId, sideIndicator: item.sideIndicator, stake: calculatedWager)
                                            let wagerInt = NSDecimalNumber(decimal: calculatedWager).intValue
                                            stakeText = wagerInt > 0 ? "\(wagerInt)" : ""
                                        } else if newValue.isEmpty {
                                            betSlipManager.setItemStake(marketId: item.marketId, sideIndicator: item.sideIndicator, stake: 0)
                                            stakeText = ""
                                        }
                                    }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Theme.elevatedBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(
                                        isToWinFocused ? Theme.accent.opacity(0.6) : Theme.border,
                                        lineWidth: isToWinFocused ? 2 : 1
                                    )
                            )
                            .animation(.easeInOut(duration: 0.15), value: isToWinFocused)
                        }
                    }
                    // US-002: Track active field based on focus changes
                    .onChange(of: isStakeFocused) { _, focused in
                        if focused { activeField = .wager }
                    }
                    .onChange(of: isToWinFocused) { _, focused in
                        if focused { activeField = .toWin }
                    }

                    // US-003: Quick stake buttons for singles mode
                    QuickStakeRow { amount in
                        let currentStake = betSlipManager.getItemStake(marketId: item.marketId, sideIndicator: item.sideIndicator)
                        let newStake = currentStake + amount
                        betSlipManager.setItemStake(marketId: item.marketId, sideIndicator: item.sideIndicator, stake: newStake)
                        stakeText = "\(NSDecimalNumber(decimal: newStake).intValue)"
                        // Update to-win from new wager
                        let calculatedToWin = betSlipManager.calculateToWin(odds: item.odds, stake: newStake)
                        toWinText = calculatedToWin > 0 ? formatToWin(calculatedToWin) : ""
                    }
                    .disabled(isSubmitting)

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
                .stroke(isLocked ? Theme.danger.opacity(0.6) : Theme.border, lineWidth: isLocked ? 1.5 : 0.5)
        )
    }
}

// MARK: - Quick Stake Button Style (US-003)

/// Button style with scale-down tap animation for quick stake pills
struct QuickStakeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Row of quick stake buttons: +$5, +$10, +$25, +$50
/// US-003: Tapping adds to current wager (not replaces)
struct QuickStakeRow: View {
    /// Callback when a quick stake amount is tapped; receives the amount to add
    let onAdd: (Decimal) -> Void

    private let amounts: [Decimal] = [5, 10, 25, 50]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(amounts.map { NSDecimalNumber(decimal: $0).intValue }, id: \.self) { amount in
                Button {
                    onAdd(Decimal(amount))
                } label: {
                    Text("+$\(amount)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Theme.cardBackground)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Theme.border, lineWidth: 1)
                        )
                }
                .buttonStyle(QuickStakeButtonStyle())
            }
            Spacer()
        }
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
