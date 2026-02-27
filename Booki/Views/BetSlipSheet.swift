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
    @Environment(AuthManager.self) private var authManager
    private var betSlipManager = BetSlipManager.shared
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

    /// US-005: Store submitted items for re-use
    @State private var lastSubmittedItems: [BetSlipItem] = []

    /// Animation state for success (US-006)
    @State private var showCheckmark: Bool = false
    @State private var checkmarkScale: CGFloat = 0
    @State private var outerRingScale: CGFloat = 0.8
    @State private var outerRingOpacity: Double = 0

    /// US-009: State for locked events error alert (client-side pre-check)
    @State private var showLockedEventsAlert: Bool = false
    @State private var showFuturesParlayAlert: Bool = false
    @State private var showMultiPickTierMessage: Bool = false
    @State private var lockedEventNames: [String] = []

    /// US-010: Track which stake field is active for the custom keypad
    @State private var activeFieldId: String?

    /// US-013: State for server-reported locked event IDs
    @State private var serverLockedEventIds: Set<String> = []

    /// Initialize with available credit for validation and optional player
    init(availableCredit: Decimal = Decimal.greatestFiniteMagnitude, player: Player? = nil) {
        self.availableCredit = availableCredit
        self.player = player
        let manager = BetSlipManager.shared
        // Initialize stake text from manager's current stake
        let currentStake = BetSlipManager.shared.stake
        _stakeText = State(initialValue: currentStake > 0 ? Self.formatStakeText(currentStake) : "")
        // Initialize per-item stake texts from manager's existing itemStakes (US-004)
        var initialItemStakeTexts: [String: String] = [:]
        var initialItemToWinTexts: [String: String] = [:]
        for item in manager.items {
            let key = manager.itemStakeKey(marketId: item.marketId, sideIndicator: item.sideIndicator)
            let stake = manager.itemStakes[key] ?? 0
            if stake > 0 {
                initialItemStakeTexts[key] = Self.formatStakeText(stake)
                let toWin = manager.calculateToWin(odds: item.odds, stake: stake)
                if toWin > 0 {
                    initialItemToWinTexts[key] = Self.formatStakeText(toWin)
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
            .navigationTitle(submissionComplete ? "Success" : "Pick Entry")
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
            .alert("Multi-Pick Unavailable", isPresented: $showFuturesParlayAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Your organizer does not allow futures in multi-picks. Place futures as singles.")
            }
            .alert("Events Locked", isPresented: $showLockedEventsAlert) {
                // US-013: Offer to remove locked events
                Button("Remove Locked Events", role: .destructive) {
                    removeLockedEvents()
                }
                Button("OK", role: .cancel) { }
            } message: {
                Text("The following events are locked:\n\n\(lockedEventNames.joined(separator: "\n"))\n\nRemove them from your pick entry to continue.")
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
            // Auto-remove selections whose events have started or locked
            .onAppear {
                let lockOffset = acceptancePolicies.first?.eventLockOffsetMinutes ?? 0
                let lockedIndices = betSlipManager.items.enumerated().compactMap { index, item -> Int? in
                    guard let event = events.first(where: { $0.id.uuidString.lowercased() == item.eventId.uuidString.lowercased() }) else {
                        return nil
                    }
                    return event.isLocked(offsetMinutes: lockOffset) ? index : nil
                }
                if !lockedIndices.isEmpty {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        for index in lockedIndices.reversed() {
                            let key = betSlipManager.itemStakeKey(marketId: betSlipManager.items[index].marketId, sideIndicator: betSlipManager.items[index].sideIndicator)
                            betSlipManager.remove(at: index)
                            itemStakeTexts.removeValue(forKey: key)
                            itemToWinTexts.removeValue(forKey: key)
                        }
                    }
                    if betSlipManager.isEmpty {
                        dismiss()
                    }
                }
            }
            // US-010: Dismiss keypad when switching bet modes
            .onChange(of: betSlipManager.betMode) { _, _ in
                activeFieldId = nil
            }
            // Pad decimal places when switching away from a field
            .onChange(of: activeFieldId) { oldFieldId, _ in
                guard let oldId = oldFieldId else { return }
                if oldId == "parlay_stake" {
                    stakeText = Self.padDecimalPlaces(stakeText)
                } else if oldId == "parlay_towin" {
                    toWinText = Self.padDecimalPlaces(toWinText)
                } else if oldId.hasSuffix("_towin") {
                    let itemKey = String(oldId.dropLast(6))
                    if let text = itemToWinTexts[itemKey] {
                        itemToWinTexts[itemKey] = Self.padDecimalPlaces(text)
                    }
                } else {
                    if let text = itemStakeTexts[oldId] {
                        itemStakeTexts[oldId] = Self.padDecimalPlaces(text)
                    }
                    // Also pad the corresponding to-win text
                    if let toWin = itemToWinTexts[oldId] {
                        itemToWinTexts[oldId] = Self.padDecimalPlaces(toWin)
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
                .font(Theme.font(size: 48))
                .foregroundStyle(Theme.textMuted)
            Text("No Selections")
                .font(Theme.title2)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.textPrimary)
            Text("Tap odds buttons on game cards to add selections to your pick entry.")
                .font(Theme.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }

    // MARK: - Balance Display (US-008)

    /// Player balance summary computed from ledger entries
    private var balanceSummary: PlayerBalanceSummary {
        guard let player = player else {
            return PlayerBalanceSummary(creditLimit: 0, openStakes: 0, openLiability: 0, balanceOwed: 0, availableCredit: 0)
        }
        let playerBets = bets.filter { $0.player?.id == player.id }
        let playerLedgerEntries = ledgerEntries.filter { $0.player?.id == player.id }
        return BalanceService.playerSummary(
            for: player,
            bets: playerBets,
            ledgerEntries: playerLedgerEntries
        )
    }

    /// Display balance (negated: positive = credit, negative = debt)
    private var displayBalance: Decimal {
        -balanceSummary.balanceOwed
    }

    /// Balance color: green for credit, red for debt, muted for zero
    private var balanceColor: Color {
        if displayBalance > 0 {
            return Theme.accent
        } else if displayBalance < 0 {
            return Theme.danger
        } else {
            return Theme.textSecondary
        }
    }

    @ViewBuilder
    private var balanceDisplayRow: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Balance:")
                    .font(Theme.subheadline)
                    .foregroundStyle(Theme.textSecondary)

                Text(formatCurrency(displayBalance))
                    .font(Theme.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(balanceColor)

                Text("/")
                    .font(Theme.subheadline)
                    .foregroundStyle(Theme.textMuted)

                Text("\(formatCurrency(balanceSummary.creditLimit)) limit")
                    .font(Theme.subheadline)
                    .foregroundStyle(Theme.textMuted)

                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            Rectangle()
                .fill(Theme.divider)
                .frame(height: 1)
        }
    }

    // MARK: - Selections List (US-005: Restructured with sticky bottom)

    @ViewBuilder
    private var selectionsList: some View {
        VStack(spacing: 0) {
            // Scrollable content area
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(spacing: 16) {
                        selectionsHeaderSection

                        // Selections (US-053: animated item transitions, US-004: per-item stakes)
                        selectionsCardsSection

                        // Combined Parlay Odds + Wager/To Win (US-041, US-008)
                        if betSlipManager.betMode == .parlay && betSlipManager.count > 1 {
                            parlayOddsCard
                                .padding(.horizontal)

                            // US-008: Parlay stake entry directly below odds card
                            parlayStakeEntrySection
                                .padding(.horizontal)
                                .id("parlay_stake")
                        }

                        // Bet summary (scrollable, above sticky bottom)
                        if betSlipManager.betMode == .parlay && betSlipManager.stake > 0 {
                            payoutSummarySection
                                .padding(.horizontal)
                        } else if betSlipManager.betMode == .singles && betSlipManager.individualTotalStake > 0 {
                            singlesSummarySection
                                .padding(.horizontal)
                        }
                    }
                    .padding(.bottom, 16)
                }
                .onChange(of: activeFieldId) { oldFieldId, newFieldId in
                    if let fieldId = newFieldId {
                        let scrollTarget: String
                        if fieldId == "parlay_stake" || fieldId == "parlay_towin" {
                            scrollTarget = "parlay_stake"
                        } else {
                            scrollTarget = fieldId.replacingOccurrences(of: "_towin", with: "")
                        }
                        // Longer delay when keypad is first opening (layout needs to settle)
                        let delay: Double = oldFieldId == nil ? 0.25 : 0.05
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                scrollProxy.scrollTo(scrollTarget, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .background(Theme.background)

            // US-005: Sticky bottom section with divider
            stickyBottomSection
        }
    }

    // MARK: - Extracted Sub-Views (type-checker workaround)

    @ViewBuilder
    private var selectionsHeaderSection: some View {
        VStack(spacing: 8) {
            // Primary: bet mode toggle
            betModeToggle

            if showMultiPickTierMessage {
                Text("Multi-Picks aren't available. Ask your organizer to unlock this feature.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }

            // Secondary: selection count + balance on one line
            HStack {
                Text("\(betSlipManager.count) selection\(betSlipManager.count == 1 ? "" : "s")")
                    .foregroundStyle(Theme.textSecondary)

                if player != nil {
                    Text("·")
                        .foregroundStyle(Theme.textMuted)
                    Text(formatCurrency(displayBalance))
                        .foregroundStyle(balanceColor)
                    Text("/")
                        .foregroundStyle(Theme.textMuted)
                    Text("\(formatCurrency(balanceSummary.creditLimit)) limit")
                        .foregroundStyle(Theme.textMuted)
                }

                Spacer()
            }
            .font(Theme.bodyFont(size: 13))

            // Warnings
            if let conflictMessage = betSlipManager.conflictDescription {
                warningBanner(icon: "exclamationmark.triangle.fill", text: conflictMessage, color: Theme.warning)
            }

            if let sgpWarning = betSlipManager.sameGameParlayWarning {
                warningBanner(icon: "exclamationmark.triangle.fill", text: sgpWarning, color: Theme.warning)
            }

            if isFuturesParlayBlocked {
                warningBanner(icon: "nosign", text: "Your organizer does not allow futures in multi-picks. Place futures as singles.", color: Theme.danger)
            }

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
        .padding(.top, 12)
    }

    @ViewBuilder
    private var betModeToggle: some View {
        HStack(spacing: 0) {
            ForEach(BetMode.allCases, id: \.self) { mode in
                let isFuturesBlocked = mode == .parlay && betSlipManager.containsOutrightSelection && !bookieAllowsFuturesParlays
                let isTierBlocked = mode == .parlay && !bookieIsPro
                let isDisabled = isSubmitting || (mode == .parlay && betSlipManager.hasConflictingSelections) || isFuturesBlocked || isTierBlocked
                Button(action: {
                    if isTierBlocked {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showMultiPickTierMessage = true
                        }
                    } else if isFuturesBlocked {
                        showFuturesParlayAlert = true
                    } else {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            betSlipManager.betMode = mode
                        }
                    }
                }) {
                    Text(mode.rawValue)
                        .font(Theme.subheadline)
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
                .disabled(isDisabled && !isFuturesBlocked && !isTierBlocked)
            }
        }
        .background(Theme.elevatedBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    /// Quick stake addition button — adds amount to current active field
    private func quickStakeButton(_ amount: Int) -> some View {
        Button {
            let current = Decimal(string: activeKeypadBinding.wrappedValue) ?? 0
            let newValue = current + Decimal(amount)
            let formatter = NumberFormatter()
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 2
            activeKeypadBinding.wrappedValue = formatter.string(from: newValue as NSDecimalNumber) ?? "\(amount)"
        } label: {
            Text("+$\(amount)")
                .font(Theme.font(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Theme.elevatedBackground)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Field Navigation

    private enum NavigationDirection {
        case previous, next
    }

    /// Ordered list of item keys matching betSlipManager.items order
    private var orderedItemKeys: [String] {
        betSlipManager.items.map {
            betSlipManager.itemStakeKey(marketId: $0.marketId, sideIndicator: $0.sideIndicator)
        }
    }

    /// Whether navigation is possible in the given direction
    private func canNavigateField(_ direction: NavigationDirection) -> Bool {
        guard let fieldId = activeFieldId else { return false }
        let baseKey = fieldId.replacingOccurrences(of: "_towin", with: "")
        let keys = orderedItemKeys
        guard let currentIndex = keys.firstIndex(of: baseKey) else { return false }
        switch direction {
        case .previous: return currentIndex > 0
        case .next: return currentIndex < keys.count - 1
        }
    }

    /// Navigate to the previous or next item's field, maintaining field type (stake vs to-win)
    private func navigateField(direction: NavigationDirection) {
        guard let fieldId = activeFieldId else { return }
        let isToWin = fieldId.hasSuffix("_towin")
        let baseKey = fieldId.replacingOccurrences(of: "_towin", with: "")
        let keys = orderedItemKeys
        guard let currentIndex = keys.firstIndex(of: baseKey) else { return }

        let newIndex: Int
        switch direction {
        case .previous:
            guard currentIndex > 0 else { return }
            newIndex = currentIndex - 1
        case .next:
            guard currentIndex < keys.count - 1 else { return }
            newIndex = currentIndex + 1
        }

        let newKey = keys[newIndex]
        activeFieldId = isToWin ? "\(newKey)_towin" : newKey
    }

    private func warningBanner(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(Theme.caption)
                .foregroundStyle(color)
            Text(text)
                .font(Theme.caption)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var selectionsCardsSection: some View {
        VStack(spacing: 12) {
            ForEach(Array(betSlipManager.items.enumerated()), id: \.element) { index, item in
                let key = betSlipManager.itemStakeKey(marketId: item.marketId, sideIndicator: item.sideIndicator)
                PremiumBetSlipItemCard(
                    item: item,
                    onRemove: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            if activeFieldId == key {
                                activeFieldId = nil
                            }
                            betSlipManager.remove(at: index)
                            itemStakeTexts.removeValue(forKey: key)
                            itemToWinTexts.removeValue(forKey: key)
                            serverLockedEventIds.remove(item.eventId.uuidString.lowercased())
                        }
                    },
                    betMode: betSlipManager.betMode,
                    stakeText: itemStakeTextBinding(for: item),
                    toWinText: itemToWinTextBinding(for: item),
                    betSlipManager: betSlipManager,
                    isLocked: serverLockedEventIds.contains(item.eventId.uuidString.lowercased()),
                    isSubmitting: isSubmitting,
                    event: events.first(where: { $0.id.uuidString.lowercased() == item.eventId.uuidString.lowercased() }),
                    activeFieldId: $activeFieldId,
                    fieldId: key
                )
                .id(key)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.9).combined(with: .opacity),
                    removal: .scale(scale: 0.9).combined(with: .opacity).combined(with: .move(edge: .trailing))
                ))
            }
        }
        .padding(.horizontal)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: betSlipManager.count)
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
                // Open bet limit warning for standalone users
                if isAtStandaloneOpenBetLimit {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.warning)
                        Text("You've reached the open pick limit (\(Self.standaloneOpenBetLimit)). Wait for picks to settle or grade before placing more.")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.warning)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.warning.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // Stake validation warnings (inline, no summary)
                if betSlipManager.betMode == .parlay {
                    if betSlipManager.stake > 0 && !betSlipManager.isStakeValid(availableCredit: availableCredit) {
                        stakeValidationWarning
                    }
                } else {
                    if betSlipManager.individualTotalStake > 0 && !betSlipManager.isIndividualStakeValid(availableCredit: availableCredit) {
                        stakeValidationWarning
                    }
                }

                // Custom numeric keypad (shown when a field is active)
                if activeFieldId != nil {
                    VStack(spacing: 4) {
                        // Quick stakes + navigation arrows + Done row
                        HStack(spacing: 8) {
                            quickStakeButton(1)
                            quickStakeButton(5)
                            quickStakeButton(25)

                            // Field navigation arrows (singles mode with 2+ items)
                            if betSlipManager.betMode == .singles && betSlipManager.count > 1,
                               let fieldId = activeFieldId,
                               fieldId != "parlay_stake" && fieldId != "parlay_towin" {
                                HStack(spacing: 4) {
                                    Button {
                                        navigateField(direction: .previous)
                                    } label: {
                                        Image(systemName: "chevron.up")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(canNavigateField(.previous) ? Theme.textPrimary : Theme.textMuted)
                                            .frame(width: 36, height: 32)
                                            .background(Theme.elevatedBackground)
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                    }
                                    .disabled(!canNavigateField(.previous))

                                    Button {
                                        navigateField(direction: .next)
                                    } label: {
                                        Image(systemName: "chevron.down")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(canNavigateField(.next) ? Theme.textPrimary : Theme.textMuted)
                                            .frame(width: 36, height: 32)
                                            .background(Theme.elevatedBackground)
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                    }
                                    .disabled(!canNavigateField(.next))
                                }
                            }

                            Button("Done") {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    activeFieldId = nil
                                }
                            }
                            .font(Theme.font(size: 14, weight: .semibold))
                            .textCase(.uppercase)
                            .foregroundStyle(Theme.accent)
                        }

                        NumericKeypadView(text: activeKeypadBinding)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Submit Button (always visible at bottom, dimmed when disabled)
                submitSection
                    .opacity(canSubmit ? 1.0 : 0.4)
                    .disabled(!canSubmit)

                // Compliance disclaimer
                Text("For tracking purposes only.")
                    .font(.caption)
                    .foregroundStyle(Theme.textMuted)
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
                .font(Theme.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.textMuted)
                .tracking(1)

            VStack(spacing: 0) {
                // Number of bets row
                HStack {
                    Text("Number of Picks")
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
                        .font(Theme.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text(formatCurrency(betSlipManager.individualTotalStake))
                        .font(Theme.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.textPrimary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                // Divider
                Rectangle()
                    .fill(Theme.divider)
                    .frame(height: 1)

                // Potential payout row - Premium styled with accent highlight
                HStack {
                    Text("Total Return")
                        .font(Theme.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text(formatCurrency(betSlipManager.individualTotalPayout))
                        .font(Theme.title1)
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
                .font(Theme.caption)
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
                Text("\(betSlipManager.count)-Leg Multi-Pick")
                    .font(Theme.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text("Combined odds")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            if let parlayOdds = betSlipManager.formattedParlayOdds {
                Text(parlayOdds)
                    .font(Theme.title1)
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

    /// US-008: Side-by-side Wager/To Win tappable fields routed to custom keypad
    /// Placed directly below the parlay odds card in the scrollable area
    @ViewBuilder
    private var parlayStakeEntrySection: some View {
        VStack(spacing: 12) {
            // Side-by-side WAGER and TO WIN fields
            HStack(spacing: 12) {
                // WAGER field (tappable, routes to custom keypad)
                let isWagerActive = activeFieldId == "parlay_stake"
                VStack(alignment: .leading, spacing: 6) {
                    Text("STAKE")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(isWagerActive ? Theme.gold : Theme.textMuted)
                        .tracking(1)
                        .animation(.easeInOut(duration: 0.15), value: isWagerActive)

                    HStack(spacing: 4) {
                        Text("$")
                            .font(Theme.font(size: 18, weight: .bold))
                            .foregroundStyle(isWagerActive ? Theme.gold : (stakeText.isEmpty ? Theme.textMuted : Theme.gold))
                            .animation(.easeInOut(duration: 0.15), value: isWagerActive)

                        Text(stakeText.isEmpty ? "0" : stakeText)
                            .font(Theme.font(size: 22, weight: .bold))
                            .foregroundStyle(isSubmitting ? Theme.textMuted : (stakeText.isEmpty ? Theme.textMuted : Theme.textPrimary))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Theme.elevatedBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                isWagerActive ? Theme.gold.opacity(0.6) : Theme.border,
                                lineWidth: isWagerActive ? 2 : 1
                            )
                    )
                    .glowingBorder(color: Theme.gold, isActive: isWagerActive, cornerRadius: 10)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            activeFieldId = isWagerActive ? nil : "parlay_stake"
                        }
                    }
                }

                // TO WIN field (tappable, routes to custom keypad)
                let isToWinActive = activeFieldId == "parlay_towin"
                VStack(alignment: .leading, spacing: 6) {
                    Text("POTENTIAL")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(isToWinActive ? Theme.accent : Theme.textMuted)
                        .tracking(1)
                        .animation(.easeInOut(duration: 0.15), value: isToWinActive)

                    HStack(spacing: 4) {
                        Text("$")
                            .font(Theme.font(size: 18, weight: .bold))
                            .foregroundStyle(isToWinActive ? Theme.accent : (parlayToWin > 0 ? Theme.accent : Theme.textMuted))
                            .animation(.easeInOut(duration: 0.15), value: isToWinActive)

                        Text(toWinText.isEmpty ? "0" : toWinText)
                            .font(Theme.font(size: 22, weight: .bold))
                            .foregroundStyle(isSubmitting ? Theme.textMuted : (isToWinActive ? Theme.accent : (parlayToWin > 0 ? Theme.accent : Theme.textMuted)))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Theme.elevatedBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                isToWinActive ? Theme.accent.opacity(0.6) : Theme.border,
                                lineWidth: isToWinActive ? 2 : 1
                            )
                    )
                    .glowingBorder(color: Theme.accent, isActive: isToWinActive, cornerRadius: 10)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            activeFieldId = isToWinActive ? nil : "parlay_towin"
                        }
                    }
                }
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

    // MARK: - Can Submit Check (US-043, US-006)

    /// Whether the bet slip is ready to submit
    /// Whether the bookie allows outright/futures in multi-picks
    private var bookieAllowsFuturesParlays: Bool {
        if let bookieId = player?.bookieId {
            let predicate = #Predicate<Bookie> { $0.id == bookieId }
            let descriptor = FetchDescriptor<Bookie>(predicate: predicate)
            if let bookie = try? modelContext.fetch(descriptor).first {
                return bookie.allowFuturesParlays
            }
        }
        return true
    }

    /// Whether the bookie is on Pro tier (for multi-pick gating)
    private var bookieIsPro: Bool {
        if let bookieId = player?.bookieId {
            let predicate = #Predicate<Bookie> { $0.id == bookieId }
            let descriptor = FetchDescriptor<Bookie>(predicate: predicate)
            if let bookie = try? modelContext.fetch(descriptor).first {
                return bookie.isPro
            }
        }
        return true // Default to allowing if bookie not found
    }

    /// Whether the parlay is blocked because it contains futures and the bookie disallows it
    private var isFuturesParlayBlocked: Bool {
        betSlipManager.betMode == .parlay
            && betSlipManager.containsOutrightSelection
            && !bookieAllowsFuturesParlays
    }

    /// Maximum open bets for standalone users (no bookie)
    private static let standaloneOpenBetLimit = 25

    /// Whether the standalone user has reached the open bet limit
    private var isAtStandaloneOpenBetLimit: Bool {
        guard let player = player, player.bookie == nil else { return false }
        let openBetCount = bets.filter { bet in
            bet.player?.id == player.id && (bet.status == .accepted || bet.status == .pending)
        }.count
        return openBetCount >= Self.standaloneOpenBetLimit
    }

    private var canSubmit: Bool {
        guard !betSlipManager.isEmpty else { return false }
        guard player != nil else { return false }
        guard !isAtStandaloneOpenBetLimit else { return false }

        // US-006: Different validation based on bet mode
        switch betSlipManager.betMode {
        case .parlay:
            guard !isFuturesParlayBlocked else { return false }
            guard betSlipManager.stake > 0 else { return false }
            return betSlipManager.isStakeValid(availableCredit: availableCredit)
        case .singles:
            // US-003: Every single must have a stake > 0
            let allHaveStakes = betSlipManager.items.allSatisfy { item in
                betSlipManager.getItemStake(marketId: item.marketId, sideIndicator: item.sideIndicator) > 0
            }
            guard allHaveStakes else { return false }
            return betSlipManager.isIndividualStakeValid(availableCredit: availableCredit)
        }
    }

    // MARK: - Submit Button Label (US-014)

    /// US-014: Mode-specific submit button label
    private var submitButtonLabel: String {
        guard isSubmitting else { return "Record Pick" }
        switch betSlipManager.betMode {
        case .parlay:
            return "Submitting multi-pick..."
        case .singles:
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
                    .font(Theme.title3)
                Text(submitButtonLabel)
                    .font(Theme.headline)
                    .fontWeight(.bold)
                    .textCase(.uppercase)
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
                .font(Theme.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.textMuted)
                .tracking(1)

            VStack(spacing: 0) {
                // Total stake row
                HStack {
                    Text("Total Stake")
                        .font(Theme.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text(formatCurrency(betSlipManager.currentTotalStake))
                        .font(Theme.subheadline)
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
                    Text("Total Return")
                        .font(Theme.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text(formatCurrency(betSlipManager.currentTotalPayout))
                        .font(Theme.title1)
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
                    .font(Theme.font(size: 70))
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
                Text("You're in!")
                    .font(Theme.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.textPrimary)

                Text("\(submittedCount) pick\(submittedCount == 1 ? "" : "s") recorded.")
                    .font(Theme.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(spacing: 12) {
                // US-005: Re-use selections button
                if !lastSubmittedItems.isEmpty {
                    Button(action: {
                        // Re-add each saved selection
                        for item in lastSubmittedItems {
                            betSlipManager.add(item)
                        }
                        // Clear stake texts (only selections restored, not amounts)
                        itemStakeTexts.removeAll()
                        stakeText = ""
                        betSlipManager.stake = 0
                        // Return to bet slip view
                        submissionComplete = false
                        // Reset animation states
                        showCheckmark = false
                        checkmarkScale = 0
                        outerRingScale = 0.8
                        outerRingOpacity = 0
                    }) {
                        Text("Re-use selections")
                            .font(Theme.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 8)
                }

                // Done button
                Button(action: {
                    dismiss()
                }) {
                    Text("Done")
                        .font(Theme.headline)
                        .textCase(.uppercase)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Theme.accent)
                        .foregroundStyle(Theme.background)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
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

    /// Map known server error codes to user-friendly messages
    static func friendlyErrorMessage(from message: String?) -> String? {
        guard let message else { return nil }
        if message.contains("open_bet_limit_reached") {
            return "You've reached the open pick limit (25). Wait for picks to settle or grade before placing more."
        }
        if message.contains("member_limit_reached") {
            return "Your organizer has reached their member limit."
        }
        return nil
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
            submissionError = "Member is not associated with an organizer"
            return
        }

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
                        submissionError = "No stake set for multi-pick"
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
                        errors.append("Failed to process multi-pick server response")
                    }

                case .failure(let error):
                    var errorMessage = "Failed to submit multi-pick"
                    if let edgeFunctionError = error as? EdgeFunctionError {
                        switch edgeFunctionError {
                        case .notAuthenticated:
                            errorMessage = "Not authenticated - please sign in again"
                        case .serverError(_, let message):
                            errorMessage = Self.friendlyErrorMessage(from: message) ?? "Server error submitting multi-pick"
                        default:
                            errorMessage = Self.friendlyErrorMessage(from: edgeFunctionError.localizedDescription) ?? edgeFunctionError.localizedDescription
                        }
                    } else if let betError = error as? BetServiceError {
                        switch betError {
                        case .edgeFunctionError(let message):
                            errorMessage = Self.friendlyErrorMessage(from: message) ?? message
                        default:
                            break
                        }
                    } else {
                        errorMessage = "Failed to submit multi-pick: \(error.localizedDescription)"
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
                // Singles mode: batch submission via submit_bets Edge Function
                let validEntries: [(item: BetSlipItem, stake: Decimal)] = itemsToSubmit.compactMap { item in
                    let key = betSlipManager.itemStakeKey(marketId: item.marketId, sideIndicator: item.sideIndicator)
                    let betStake = itemStakesSnapshot[key] ?? 0
                    guard betStake > 0 else { return nil }
                    return (item: item, stake: betStake)
                }

                if validEntries.isEmpty {
                    errors.append("No stakes set")
                } else {
                    let batchResult = await BetService.submitBetsToServer(
                        items: validEntries,
                        playerId: player.id,
                        bookieId: bookieId
                    )

                    switch batchResult {
                    case .success(let response):
                        let localBets = BetService.createLocalBetsFromBatchResponse(
                            response,
                            player: player,
                            items: validEntries,
                            events: events
                        )
                        await MainActor.run {
                            for bet in localBets {
                                modelContext.insert(bet)
                            }
                        }
                        successCount += localBets.count

                        // Handle partial failures (e.g., locked events)
                        if let failedBets = response.failed, !failedBets.isEmpty {
                            let lockedFailures = failedBets.filter { $0.error.contains("locked") }
                            if !lockedFailures.isEmpty {
                                let failedNames = lockedFailures.compactMap { failure in
                                    if failure.index < validEntries.count {
                                        return validEntries[failure.index].item.eventDescription
                                    }
                                    return "Event \(failure.eventId.prefix(8))"
                                }
                                await MainActor.run {
                                    lockedEventNames = failedNames
                                    showLockedEventsAlert = true
                                }
                            }
                            for failure in failedBets where !failure.error.contains("locked") {
                                errors.append(failure.error)
                            }
                        }

                    case .failure(let error):
                        if let edgeFunctionError = error as? EdgeFunctionError {
                            switch edgeFunctionError {
                            case .notAuthenticated:
                                errors.append("Not authenticated - please sign in again")
                            case .serverError(_, let message):
                                errors.append(Self.friendlyErrorMessage(from: message) ?? message ?? "Server error")
                            default:
                                errors.append(Self.friendlyErrorMessage(from: edgeFunctionError.localizedDescription) ?? edgeFunctionError.localizedDescription)
                            }
                        } else if let betError = error as? BetServiceError {
                            switch betError {
                            case .edgeFunctionError(let message):
                                errors.append(Self.friendlyErrorMessage(from: message) ?? message)
                            default:
                                errors.append("Failed to submit picks")
                            }
                        } else {
                            errors.append("Failed to submit picks: \(error.localizedDescription)")
                        }
                    }
                }
            }

            // Update UI on main thread
            await MainActor.run {
                isSubmitting = false

                if successCount > 0 {
                    submittedCount = successCount
                    // US-005: Save items before clearing for re-use
                    lastSubmittedItems = itemsToSubmit
                    // Clear bet slip, stake, and local stake texts
                    betSlipManager.clearAll()
                    betSlipManager.stake = 0
                    itemStakeTexts.removeAll()
                    itemToWinTexts.removeAll()
                    toWinText = ""
                    stakeText = ""
                    activeFieldId = nil

                    // Haptic feedback for successful submission
                    UINotificationFeedbackGenerator().notificationOccurred(.success)

                    // Show success animation
                    withAnimation(.easeInOut(duration: 0.3)) {
                        submissionComplete = true
                    }
                }

                if !errors.isEmpty && successCount == 0 {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    submissionError = errors.joined(separator: "\n")
                } else if !errors.isEmpty {
                    // Partial success - some bets failed
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    submissionError = "\(successCount) picks submitted. Some failed:\n" + errors.joined(separator: "\n")
                }
            }
        }
    }

    // MARK: - Keypad Binding (US-010)

    /// Returns a binding to the text for whichever field is active
    private var activeKeypadBinding: Binding<String> {
        Binding(
            get: {
                guard let fieldId = activeFieldId else { return "" }
                if fieldId == "parlay_stake" {
                    return stakeText
                } else if fieldId == "parlay_towin" {
                    return toWinText
                } else if fieldId.hasSuffix("_towin") {
                    let itemKey = String(fieldId.dropLast(6)) // remove "_towin"
                    return itemToWinTexts[itemKey] ?? ""
                } else {
                    return itemStakeTexts[fieldId] ?? ""
                }
            },
            set: { newValue in
                guard let fieldId = activeFieldId else { return }
                if fieldId == "parlay_stake" {
                    stakeText = newValue
                    parlayActiveField = .wager
                    if let value = Decimal(string: newValue) {
                        betSlipManager.stake = value
                        // Auto-calculate to-win
                        if let odds = betSlipManager.combinedParlayOdds {
                            let calculatedToWin = betSlipManager.calculateToWin(odds: odds, stake: value)
                            toWinText = calculatedToWin > 0 ? formatToWin(calculatedToWin) : ""
                        }
                    } else if newValue.isEmpty {
                        betSlipManager.stake = 0
                        toWinText = ""
                    }
                } else if fieldId == "parlay_towin" {
                    toWinText = newValue
                    parlayActiveField = .toWin
                    if let toWinValue = Decimal(string: newValue), toWinValue > 0 {
                        if let odds = betSlipManager.combinedParlayOdds {
                            let calculatedWager = betSlipManager.calculateWagerFromToWin(odds: odds, toWin: toWinValue)
                            betSlipManager.stake = calculatedWager
                            stakeText = Self.formatStakeText(calculatedWager)
                        }
                    } else if newValue.isEmpty {
                        betSlipManager.stake = 0
                        stakeText = ""
                    }
                } else if fieldId.hasSuffix("_towin") {
                    let itemKey = String(fieldId.dropLast(6))
                    itemToWinTexts[itemKey] = newValue
                    // Reverse-calculate wager from to-win for this item
                    if let item = betSlipManager.items.first(where: {
                        betSlipManager.itemStakeKey(marketId: $0.marketId, sideIndicator: $0.sideIndicator) == itemKey
                    }) {
                        if let toWinValue = Decimal(string: newValue), toWinValue > 0 {
                            let calculatedWager = betSlipManager.calculateWagerFromToWin(odds: item.odds, toWin: toWinValue)
                            itemStakeTexts[itemKey] = Self.formatStakeText(calculatedWager)
                            betSlipManager.setItemStake(marketId: item.marketId, sideIndicator: item.sideIndicator, stake: calculatedWager)
                        } else if newValue.isEmpty {
                            itemStakeTexts[itemKey] = ""
                            betSlipManager.setItemStake(marketId: item.marketId, sideIndicator: item.sideIndicator, stake: 0)
                        }
                    }
                } else {
                    itemStakeTexts[fieldId] = newValue
                    // Sync to betSlipManager and auto-calculate to-win
                    if let value = Decimal(string: newValue) {
                        syncItemStake(fieldId: fieldId, stake: value)
                        // Auto-calculate to-win for this item
                        if let item = betSlipManager.items.first(where: {
                            betSlipManager.itemStakeKey(marketId: $0.marketId, sideIndicator: $0.sideIndicator) == fieldId
                        }) {
                            let toWin = betSlipManager.calculateToWin(odds: item.odds, stake: value)
                            itemToWinTexts[fieldId] = toWin > 0 ? formatToWin(toWin) : ""
                        }
                    } else if newValue.isEmpty {
                        syncItemStake(fieldId: fieldId, stake: 0)
                        itemToWinTexts[fieldId] = ""
                    }
                }
            }
        )
    }

    /// Sync item stake from fieldId (format: "marketId_sideIndicator") to BetSlipManager
    private func syncItemStake(fieldId: String, stake: Decimal) {
        // Find the matching item by checking all items' keys
        for item in betSlipManager.items {
            let key = betSlipManager.itemStakeKey(marketId: item.marketId, sideIndicator: item.sideIndicator)
            if key == fieldId {
                betSlipManager.setItemStake(marketId: item.marketId, sideIndicator: item.sideIndicator, stake: stake)
                return
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

    private func itemToWinTextBinding(for item: BetSlipItem) -> Binding<String> {
        let key = betSlipManager.itemStakeKey(marketId: item.marketId, sideIndicator: item.sideIndicator)
        return Binding(
            get: { itemToWinTexts[key] ?? "" },
            set: { itemToWinTexts[key] = $0 }
        )
    }

    /// Sanitize stake input: allow digits and one decimal point, max 2 decimal places (US-002)
    static func sanitizeStakeInput(_ input: String) -> String {
        // Allow only digits and decimal point
        var filtered = String(input.filter { $0.isNumber || $0 == "." })

        // Only allow one decimal point
        let parts = filtered.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count > 2 {
            // More than one decimal — keep only first decimal
            filtered = String(parts[0]) + "." + String(parts[1])
        }

        // Max 2 digits after decimal point
        if let dotIndex = filtered.firstIndex(of: ".") {
            let afterDot = filtered[filtered.index(after: dotIndex)...]
            if afterDot.count > 2 {
                let endIndex = filtered.index(dotIndex, offsetBy: 3) // dot + 2 chars
                filtered = String(filtered[...endIndex])
            }
        }

        return filtered
    }

    /// Format a Decimal stake for display in text field (US-002)
    static func formatStakeText(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value)
        let intPart = number.intValue
        if value == Decimal(intPart) {
            return "\(intPart)"
        } else {
            // Has decimal component — always show 2 decimal places
            let formatter = NumberFormatter()
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 2
            formatter.groupingSeparator = ""
            return formatter.string(from: number) ?? "\(value)"
        }
    }

    /// Pad a raw text string to 2 decimal places if it contains a decimal point
    /// e.g. "12.5" → "12.50", "12" → "12", "0." → "0.00"
    private static func padDecimalPlaces(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        guard text.contains(".") else { return text }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        let intPart = parts[0]
        let fracPart = parts.count > 1 ? String(parts[1]) : ""
        let padded = fracPart.padding(toLength: 2, withPad: "0", startingAt: 0)
        return "\(intPart).\(padded)"
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
    var betSlipManager: BetSlipManager

    /// US-013: Whether this item's event is locked (server-reported)
    var isLocked: Bool = false

    /// US-014: Whether submission is in progress (disables inputs)
    var isSubmitting: Bool = false

    /// Event for context line (league, abbreviated teams, start time)
    var event: Event? = nil

    /// US-010: Active field ID for custom keypad integration
    @Binding var activeFieldId: String?

    /// Unique field ID for this card's stake input
    var fieldId: String

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

    /// Format game start time as "Fri 5:10 PM"
    private static func formatGameTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE h:mm a"
        return formatter.string(from: date)
    }

    /// Build context line: "NBA · MIL @ NOP · Fri 5:10 PM" or "Masters · Outright Winner · Sun 2:45 PM"
    private var contextLine: String {
        if let event = event {
            if event.awayTeam == "Outright" {
                return "\(event.league) · Outright Winner · \(Self.formatGameTime(event.startTime))"
            }
            let away = TeamAbbreviations.abbreviation(for: event.awayTeam)
            let home = TeamAbbreviations.abbreviation(for: event.homeTeam)
            return "\(event.league) · \(away) @ \(home) · \(Self.formatGameTime(event.startTime))"
        }
        return item.eventDescription
    }

    var body: some View {
        VStack(spacing: 0) {
            // US-013: Locked event warning banner
            if isLocked {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(Theme.caption)
                    Text("Event Locked")
                        .font(Theme.caption)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(Theme.danger)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Theme.danger.opacity(0.15))
            }

            // Selection info: name + odds on one line, event + time below
            VStack(alignment: .leading, spacing: 4) {
                // Line 1: Selection name + odds + remove button
                HStack(alignment: .center, spacing: 8) {
                    Text(item.side)
                        .font(Theme.bodyFont(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)

                    Text(formattedOdds)
                        .font(Theme.font(size: 14, weight: .bold))
                        .foregroundStyle(item.odds >= 0 ? Theme.accent : Theme.textPrimary)

                    Spacer()

                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(isSubmitting ? Theme.textMuted.opacity(0.3) : Theme.textMuted)
                    }
                    .buttonStyle(.plain)
                    .disabled(isSubmitting)
                }

                // Line 2: "NBA · MIL @ NOP · Fri 5:10 PM"
                Text(contextLine)
                    .font(Theme.bodyFont(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            // US-004/US-010: Per-bet bidirectional WAGER/TO WIN in singles mode
            if betMode == .singles {
                let isWagerActive = activeFieldId == fieldId
                let toWinFieldId = fieldId + "_towin"
                let isToWinActive = activeFieldId == toWinFieldId
                VStack(spacing: 8) {
                    // Divider
                    Rectangle()
                        .fill(Theme.divider)
                        .frame(height: 1)

                    HStack(spacing: 12) {
                        // WAGER field (tappable, routes to custom keypad)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("STAKE")
                                .font(Theme.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(isWagerActive ? Theme.gold : Theme.textMuted)
                                .tracking(0.5)

                            HStack(spacing: 4) {
                                Text("$")
                                    .font(Theme.font(size: 14, weight: .semibold))
                                    .foregroundStyle(isWagerActive ? Theme.gold : (stakeText.isEmpty ? Theme.textMuted : Theme.gold))

                                Text(stakeText.isEmpty ? "0" : stakeText)
                                    .font(Theme.font(size: 16, weight: .bold))
                                    .foregroundStyle(stakeText.isEmpty ? Theme.textMuted : Theme.textPrimary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Theme.elevatedBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isWagerActive ? Theme.gold.opacity(0.6) : Theme.border, lineWidth: isWagerActive ? 2 : 0.5)
                        )
                        .glowingBorder(color: Theme.gold, isActive: isWagerActive, cornerRadius: 8)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                activeFieldId = isWagerActive ? nil : fieldId
                            }
                        }

                        // TO WIN field (tappable, routes to custom keypad)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("POTENTIAL")
                                .font(Theme.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(isToWinActive ? Theme.accent : Theme.textMuted)
                                .tracking(0.5)

                            HStack(spacing: 4) {
                                Text("$")
                                    .font(Theme.font(size: 14, weight: .semibold))
                                    .foregroundStyle(isToWinActive ? Theme.accent : (individualToWin > 0 ? Theme.accent : Theme.textMuted))

                                Text(toWinText.isEmpty ? "0" : toWinText)
                                    .font(Theme.font(size: 16, weight: .bold))
                                    .foregroundStyle(isToWinActive ? Theme.accent : (individualToWin > 0 ? Theme.accent : Theme.textMuted))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Theme.elevatedBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isToWinActive ? Theme.accent.opacity(0.6) : Theme.border, lineWidth: isToWinActive ? 2 : 0.5)
                        )
                        .glowingBorder(color: Theme.accent, isActive: isToWinActive, cornerRadius: 8)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                activeFieldId = isToWinActive ? nil : toWinFieldId
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }

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
