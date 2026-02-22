import SwiftUI
import SwiftData

/// Information about parlay partial grading status
struct ParlayPartialInfo {
    let gradedCount: Int
    let totalLegs: Int
    let willLose: Bool
    let awaitingCount: Int

    var isPartiallyGraded: Bool {
        gradedCount > 0 && gradedCount < totalLegs
    }
}

/// Filter options for bets list
enum BetFilter: String, CaseIterable {
    case open = "Open"
    case past = "Past"

    /// Returns the bet statuses that match this filter
    var matchingStatuses: [BetStatus] {
        switch self {
        case .open:
            return [.pending, .accepted, .readyToGrade, .graded]
        case .past:
            return [.settled, .declined, .void]
        }
    }
}

extension BetStatus: CaseIterable {
    static var allCases: [BetStatus] {
        [.pending, .accepted, .declined, .readyToGrade, .graded, .settled, .void]
    }
}

struct BetsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var bets: [Bet]
    @Query private var events: [Event]

    @State private var selectedFilter: BetFilter = .open
    @State private var selectedPlayerId: UUID? = nil

    /// Bets matching the current status filter (before player filter)
    private var statusFilteredBets: [Bet] {
        bets.filter { selectedFilter.matchingStatuses.contains($0.status) }
    }

    /// Players who have bets in the current status filter
    private var availablePlayers: [(id: UUID, name: String)] {
        var seen = Set<UUID>()
        var result: [(id: UUID, name: String)] = []
        for bet in statusFilteredBets {
            if let player = bet.player, !seen.contains(player.id) {
                seen.insert(player.id)
                result.append((id: player.id, name: player.name))
            }
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Filtered bets based on selected filter + player
    private var filteredBets: [Bet] {
        var result = statusFilteredBets
        if let playerId = selectedPlayerId {
            result = result.filter { $0.player?.id == playerId }
        }
        return result.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // MARK: - Filter Picker
                Picker("Filter", selection: $selectedFilter) {
                    ForEach(BetFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .onChange(of: selectedFilter) { _, _ in
                    // Reset player filter when switching tabs if selected player has no bets
                    if let playerId = selectedPlayerId,
                       !statusFilteredBets.contains(where: { $0.player?.id == playerId }) {
                        selectedPlayerId = nil
                    }
                }

                // MARK: - Player Filter Chips
                if !availablePlayers.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(availablePlayers, id: \.id) { player in
                                Button {
                                    if selectedPlayerId == player.id {
                                        selectedPlayerId = nil
                                    } else {
                                        selectedPlayerId = player.id
                                    }
                                } label: {
                                    Text(player.name)
                                        .font(Theme.bodyFont(size: 13, weight: .medium))
                                        .foregroundStyle(selectedPlayerId == player.id ? Theme.background : Theme.textSecondary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule()
                                                .fill(selectedPlayerId == player.id ? Theme.accent : Theme.cardBackground)
                                        )
                                        .overlay(
                                            Capsule()
                                                .stroke(selectedPlayerId == player.id ? Theme.accent : Theme.border, lineWidth: 0.5)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    }
                }

                // MARK: - Bets List
                if filteredBets.isEmpty {
                    ContentUnavailableView(
                        "No Picks",
                        systemImage: "list.bullet.rectangle",
                        description: Text("No picks match the selected filter.")
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(filteredBets) { bet in
                                NavigationLink(value: bet) {
                                    BetRowView(
                                        bet: bet,
                                        eventName: eventName(for: bet),
                                        betDisplayName: betDisplayName(for: bet),
                                        sportLeague: sportLeague(for: bet),
                                        policyViolationReason: bet.policyViolationReason,
                                        parlayInfo: parlayInfo(for: bet),
                                        event: findEvent(for: bet),
                                        parlayBets: bet.isParlay ? bets.filter({ $0.ticketId == bet.ticketId }) : [],
                                        events: Array(events)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                }
            }
            .background(Theme.background)
            .navigationTitle("Picks")
            .navigationDestination(for: Bet.self) { bet in
                BetDetailView(bet: bet)
            }
        }
    }

    // MARK: - Helper Methods

    private func findEvent(for bet: Bet) -> Event? {
        events.first(where: { $0.id.uuidString.lowercased() == bet.eventId.lowercased() })
    }

    private func eventName(for bet: Bet) -> String {
        if let event = events.first(where: { $0.id.uuidString.lowercased() == bet.eventId.lowercased() }) {
            return "\(event.awayTeam) @ \(event.homeTeam)"
        }
        if let desc = bet.eventDescription, !desc.isEmpty {
            return desc
        }
        return "Event \(bet.eventId.prefix(8))"
    }

    private func sportLeague(for bet: Bet) -> String? {
        if let event = events.first(where: { $0.id.uuidString.lowercased() == bet.eventId.lowercased() }) {
            return event.league
        }
        if let league = bet.sportLeague, !league.isEmpty {
            return league
        }
        return nil
    }

    /// Creates a display name for the bet ticket
    /// - Single bets: "Lakers ML -150" or "OKC -6.5 (-110)"
    /// - Parlays: "3-leg multi-pick +450"
    private func betDisplayName(for bet: Bet) -> String {
        if bet.isParlay {
            // For parlays, show leg count and combined odds
            let parlayBets = bets.filter { $0.ticketId == bet.ticketId }
            let combinedOdds = calculateCombinedOdds(for: parlayBets)
            let oddsString = combinedOdds > 0 ? "+\(combinedOdds)" : "\(combinedOdds)"
            return "\(parlayBets.count)-leg multi-pick \(oddsString)"
        } else {
            // For singles, show side with odds
            let oddsString = bet.odds > 0 ? "+\(bet.odds)" : "\(bet.odds)"
            return "\(bet.side) \(oddsString)"
        }
    }

    /// Calculate combined American odds for a parlay
    private func calculateCombinedOdds(for parlayBets: [Bet]) -> Int {
        let combinedDecimal = parlayBets.reduce(Decimal(1)) { result, bet in
            result * americanToDecimal(bet.odds)
        }
        return decimalToAmerican(combinedDecimal)
    }

    private func americanToDecimal(_ odds: Int) -> Decimal {
        if odds > 0 {
            return 1 + Decimal(odds) / 100
        } else {
            return 1 + 100 / Decimal(abs(odds))
        }
    }

    private func decimalToAmerican(_ decimal: Decimal) -> Int {
        if decimal >= 2 {
            return Int(truncating: ((decimal - 1) * 100) as NSDecimalNumber)
        } else {
            return Int(truncating: (-100 / (decimal - 1)) as NSDecimalNumber)
        }
    }

    /// Calculate parlay partial info for a bet
    private func parlayInfo(for bet: Bet) -> ParlayPartialInfo? {
        guard bet.isParlay else { return nil }

        // Find all bets with the same ticketId
        let parlayBets = bets.filter { $0.ticketId == bet.ticketId }
        guard parlayBets.count > 1 else { return nil }

        let gradedCount = parlayBets.filter { $0.gradeResult != nil || $0.status == .void }.count
        let totalLegs = parlayBets.count
        let awaitingCount = totalLegs - gradedCount
        let willLose = parlayBets.contains { $0.gradeResult == .loss }

        return ParlayPartialInfo(
            gradedCount: gradedCount,
            totalLegs: totalLegs,
            willLose: willLose,
            awaitingCount: awaitingCount
        )
    }
}

// MARK: - Bet Row View

struct BetRowView: View {
    let bet: Bet
    let eventName: String
    let betDisplayName: String
    var sportLeague: String? = nil
    var policyViolationReason: String? = nil
    var parlayInfo: ParlayPartialInfo? = nil
    var event: Event? = nil
    var parlayBets: [Bet] = []
    var events: [Event] = []

    /// Build a PickPresenter from the bet data, using multi-pick factory for parlays
    /// Note: playerName is passed separately to PickCardCompact for emphasis styling
    private var presenter: PickPresenter {
        if bet.isParlay && parlayBets.count > 1 {
            return PickPresenter.multiPick(bets: parlayBets, events: events)
        } else {
            return PickPresenter(bet: bet, event: event)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Canonical pick card display
            PickCardCompact(presenter: presenter, playerName: bet.player?.name)

            // Parlay partial grading badge (bookie-specific overlay)
            if let info = parlayInfo, info.isPartiallyGraded {
                Text("Partial (\(info.gradedCount)/\(info.totalLegs))")
                    .font(Theme.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.background)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.warning)
                    .clipShape(Capsule())
                    .padding(.leading, 12)
            }

            // Policy violation reason (only for pending picks with violations)
            if bet.status == .pending, let reason = policyViolationReason, !reason.isEmpty {
                Text("Review: \(reason)")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.warning)
                    .padding(.leading, 12)
            }

            // Parlay will lose indicator
            if let info = parlayInfo, info.willLose {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(Theme.caption)
                    Text("Multi-pick will lose when reconciled")
                        .font(Theme.caption)
                }
                .foregroundStyle(Theme.danger)
                .padding(.leading, 12)
            }
        }
    }
}

// MARK: - Bet Detail View

struct BetDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var events: [Event]
    @Query private var ledgerEntries: [LedgerEntry]
    @Query private var allBets: [Bet]
    @Query private var policies: [AcceptancePolicy]

    let bet: Bet

    /// Get the current parlay push/void policy
    private var parlayPolicy: ParlayPushVoidPolicy {
        policies.first?.parlayPushVoidPolicyEnum ?? .reduceLegReprice
    }

    /// Get all bets with the same ticketId (for parlay settlement)
    private var parlayBets: [Bet] {
        allBets.filter { $0.ticketId == bet.ticketId }
    }

    @State private var showingVoidConfirmation = false
    @State private var showingSettleConfirmation = false
    @State private var showingOverrideGradeSheet = false
    @State private var overrideNewOutcome: String = "win"
    @State private var overrideReason: String = ""
    @State private var overrideIsLoading = false
    @State private var overrideErrorMessage: String?
    @State private var showingOverrideError = false

    // Reverse Settlement state
    @State private var showingReverseSettlementSheet = false
    @State private var reverseReason: String = ""
    @State private var reverseIsLoading = false
    @State private var reverseErrorMessage: String?
    @State private var showingReverseError = false
    @State private var showingReverseSuccess = false

    // MARK: - Computed Properties

    private var event: Event? {
        events.first { $0.id.uuidString.lowercased() == bet.eventId.lowercased() }
    }

    private var eventName: String {
        if let event = event {
            return "\(event.awayTeam) @ \(event.homeTeam)"
        }
        if let desc = bet.eventDescription, !desc.isEmpty {
            return desc
        }
        return "Event \(bet.eventId.prefix(8))"
    }

    /// Creates a display name for the bet ticket
    /// - Single bets: "Lakers ML -150" or "OKC -6.5 (-110)"
    /// - Parlays: "3-leg multi-pick +450"
    private var betDisplayName: String {
        if bet.isParlay {
            // For parlays, show leg count and combined odds
            let combinedOdds = calculateCombinedOdds(for: parlayBets)
            let oddsString = combinedOdds > 0 ? "+\(combinedOdds)" : "\(combinedOdds)"
            return "\(parlayBets.count)-leg multi-pick \(oddsString)"
        } else {
            // For singles, show side with odds
            let oddsString = bet.odds > 0 ? "+\(bet.odds)" : "\(bet.odds)"
            return "\(bet.side) \(oddsString)"
        }
    }

    /// Calculate combined American odds for a parlay
    private func calculateCombinedOdds(for parlayBets: [Bet]) -> Int {
        let combinedDecimal = parlayBets.reduce(Decimal(1)) { result, bet in
            result * americanToDecimal(bet.odds)
        }
        return decimalToAmerican(combinedDecimal)
    }

    private func americanToDecimal(_ odds: Int) -> Decimal {
        if odds > 0 {
            return 1 + Decimal(odds) / 100
        } else {
            return 1 + 100 / Decimal(abs(odds))
        }
    }

    private func decimalToAmerican(_ decimal: Decimal) -> Int {
        if decimal >= 2 {
            return Int(truncating: ((decimal - 1) * 100) as NSDecimalNumber)
        } else {
            return Int(truncating: (-100 / (decimal - 1)) as NSDecimalNumber)
        }
    }

    private var formattedOdds: String {
        bet.odds > 0 ? "+\(bet.odds)" : "\(bet.odds)"
    }

    private var formattedStake: String {
        formatCurrency(bet.stake)
    }

    private var potentialPayout: Decimal {
        LiabilityService.calculatePayout(stake: bet.stake, odds: bet.odds)
    }

    private var formattedPotentialPayout: String {
        formatCurrency(potentialPayout)
    }

    private var totalReturn: Decimal {
        bet.stake + potentialPayout
    }

    private var formattedTotalReturn: String {
        formatCurrency(totalReturn)
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: bet.createdAt)
    }

    // MARK: - Parlay Partial Grading Info

    /// Whether this is a parlay that is only partially graded
    private var isParlayPartiallyGraded: Bool {
        guard bet.isParlay else { return false }
        let gradedCount = parlayBets.filter { $0.gradeResult != nil || $0.status == .void }.count
        return gradedCount > 0 && gradedCount < parlayBets.count
    }

    /// Number of legs awaiting results
    private var legsAwaitingCount: Int {
        guard bet.isParlay else { return 0 }
        return parlayBets.filter { $0.gradeResult == nil && $0.status != .void }.count
    }

    /// Whether the parlay already has a losing leg (will lose when settled)
    private var parlayWillLose: Bool {
        guard bet.isParlay else { return false }
        return parlayBets.contains { $0.gradeResult == .loss }
    }

    /// Whether all parlay legs are graded and settlement can proceed
    private var isParlayFullyGraded: Bool {
        guard bet.isParlay else { return true }
        return parlayBets.allSatisfy { $0.gradeResult != nil || $0.status == .void }
    }

    // MARK: - Shared Card Components

    private var detailCardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.cardBackground)
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.border, lineWidth: 0.5)
        }
        .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
    }

    private func detailSectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(Theme.caption)
                .fontWeight(.semibold)
                .tracking(1)
                .foregroundStyle(Theme.textMuted)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func detailLabeledRow(label: String, value: String, valueColor: Color = Theme.textPrimary) -> some View {
        HStack {
            Text(label)
                .font(Theme.bodyFont(size: 14))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(Theme.bodyFont(size: 14, weight: .medium))
                .foregroundStyle(valueColor)
        }
    }

    // MARK: - Presenter

    private var presenter: PickPresenter {
        if bet.isParlay && parlayBets.count > 1 {
            return PickPresenter.multiPick(bets: parlayBets, events: Array(events))
        } else {
            return PickPresenter(bet: bet, event: event)
        }
    }

    private var isSettled: Bool {
        switch presenter.settlementStatus {
        case .won, .lost, .push, .void, .cancelled: return true
        case .open: return false
        }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                detailHeroCard
                detailFinancialsCard
                detailActivityCard
                if shouldShowActions {
                    detailActionsCard
                }
            }
            .padding(16)
        }
        .background(Theme.background)
        .navigationTitle(betDisplayName)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Void this pick?",
            isPresented: $showingVoidConfirmation,
            titleVisibility: .visible
        ) {
            Button("Void Pick", role: .destructive) {
                voidBet()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone. The pick will be marked as void.")
        }
        .confirmationDialog(
            "Reconcile this pick?",
            isPresented: $showingSettleConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reconcile Pick") {
                settleBet()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let result = bet.gradeResult {
                Text("This will create a ledger entry for a \(result.rawValue) reconciliation.")
            } else {
                Text("This will create a ledger entry for the reconciliation.")
            }
        }
        .sheet(isPresented: $showingReverseSettlementSheet) {
            reverseSettlementSheetContent
        }
        .sheet(isPresented: $showingOverrideGradeSheet) {
            overrideGradeSheetContent
        }
        .alert("Reversal Successful", isPresented: $showingReverseSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The reconciliation has been reversed. The pick has returned to 'graded' status.")
        }
        .alert("Reversal Failed", isPresented: $showingReverseError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(reverseErrorMessage ?? "An unknown error occurred.")
        }
        .alert("Override Failed", isPresented: $showingOverrideError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(overrideErrorMessage ?? "An unknown error occurred.")
        }
    }

    // MARK: - Actions View

    private var shouldShowActions: Bool {
        switch bet.status {
        case .pending, .accepted, .graded, .settled:
            return true
        default:
            return false
        }
    }

    /// Calculate the balance impact description for reversal warning
    private var reversalImpactDescription: String {
        if let settlementEntry = ledgerEntries.first(where: { $0.bet?.id == bet.id && $0.type == .settlement }) {
            let amount = settlementEntry.amount
            let formattedAmount = formatCurrency(abs(amount))
            if amount > 0 {
                return "This will remove \(formattedAmount) from the member's balance."
            } else if amount < 0 {
                return "This will add \(formattedAmount) to the member's balance."
            } else {
                return "This will have no impact on the member's balance (push)."
            }
        }
        return "This will reverse the reconciliation and adjust the member's balance."
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch bet.status {
        case .pending:
            actionButton("Accept Pick", icon: "checkmark.circle.fill", color: Theme.accent) {
                acceptBet()
            }
            actionButton("Decline Pick", icon: "xmark.circle.fill", color: Theme.danger) {
                declineBet()
            }

        case .accepted:
            actionButton("Void Pick", icon: "trash.circle.fill", color: Theme.danger) {
                showingVoidConfirmation = true
            }

        case .graded:
            if bet.isParlay {
                if isParlayPartiallyGraded {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.warning)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Partial (\(parlayBets.count - legsAwaitingCount)/\(parlayBets.count))")
                                .font(Theme.font(size: 15, weight: .medium))
                                .foregroundStyle(Theme.warning)
                            Text("Cannot reconcile - \(legsAwaitingCount) leg\(legsAwaitingCount == 1 ? "" : "s") awaiting results")
                                .font(Theme.caption)
                                .foregroundStyle(Theme.textMuted)
                        }
                    }

                    if parlayWillLose {
                        parlayWillLoseBanner
                    }
                } else if isParlayFullyGraded {
                    if parlayWillLose {
                        parlayWillLoseBanner
                    }

                    actionButton("Reconcile Multi-Pick", icon: "dollarsign.circle.fill", color: Theme.accent) {
                        showingSettleConfirmation = true
                    }
                }
            } else {
                actionButton("Reconcile Pick", icon: "dollarsign.circle.fill", color: Theme.accent) {
                    showingSettleConfirmation = true
                }
            }

            if bet.gradeResult != nil {
                actionButton("Override Grade", icon: "pencil.circle.fill", color: Theme.warning) {
                    prepareOverrideGradeSheet()
                }
            }

        case .settled:
            actionButton("Reverse Reconciliation", icon: "arrow.uturn.backward.circle.fill", color: Theme.danger) {
                prepareReverseSettlementSheet()
            }

            if bet.gradeResult != nil {
                actionButton("Override Grade", icon: "pencil.circle.fill", color: Theme.warning) {
                    prepareOverrideGradeSheet()
                }
            }

        default:
            EmptyView()
        }
    }

    private var parlayWillLoseBanner: some View {
        HStack {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(Theme.danger)
            Text("Multi-pick will lose when reconciled")
                .font(Theme.caption)
                .foregroundStyle(Theme.danger)
        }
    }

    private func actionButton(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                Text(title)
                    .fontWeight(.medium)
            }
            .font(Theme.bodyFont(size: 14))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Hero Card

    private var detailHeroCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            detailHeroHeader
                .padding(12)

            if bet.isParlay && parlayBets.count > 1 {
                ForEach(parlayBets) { leg in
                    Divider().background(Theme.divider)
                    detailHeroLegRow(bet: leg)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
            }
        }
        .background(detailCardBackground)
    }

    private var detailHeroHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Text(presenter.title)
                    .font(Theme.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                Spacer()
                StatusPill(
                    settlementStatus: presenter.settlementStatus,
                    workflowStatus: presenter.workflowStatus
                )
            }

            if let player = bet.player {
                Text(player.name)
                    .font(Theme.bodyFont(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }

            if !presenter.contextLine.isEmpty {
                Text(presenter.contextLine)
                    .font(Theme.bodyFont(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                Text(presenter.stakeLine)
                    .font(Theme.bodyFont(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                Text(presenter.profitLine)
                    .font(Theme.bodyFont(size: 13, weight: .medium))
                    .foregroundStyle(presenter.profitColor)
            }

            if bet.isParlay && parlayBets.count > 1 {
                HStack(spacing: 4) {
                    ForEach(parlayBets) { leg in
                        Circle()
                            .fill(legStatusColor(for: leg))
                            .frame(width: 8, height: 8)
                    }
                }
            }
        }
    }

    private func detailHeroLegRow(bet leg: Bet) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SelectionRow(
                selectionLabel: leg.side,
                odds: leg.odds,
                eventName: detailEventName(for: leg),
                league: detailEventLeague(for: leg),
                gradeResult: leg.gradeResult
            )

            if leg.gradeResult == nil && (leg.status == .accepted || leg.status == .readyToGrade) {
                Text("Awaiting Result")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textMuted)
                    .italic()
            }
        }
    }

    private func legStatusColor(for bet: Bet) -> Color {
        if let result = bet.gradeResult {
            switch result {
            case .win: return Theme.accent
            case .loss: return Theme.danger
            case .push: return Theme.warning
            }
        }
        if bet.status == .void { return Theme.textMuted }
        return Theme.textMuted.opacity(0.5)
    }

    private func detailEventName(for bet: Bet) -> String {
        if let event = events.first(where: { $0.id.uuidString.lowercased() == bet.eventId.lowercased() }) {
            return "\(event.awayTeam) @ \(event.homeTeam)"
        }
        if let desc = bet.eventDescription, !desc.isEmpty { return desc }
        return "Event \(bet.eventId.prefix(8))"
    }

    private func detailEventLeague(for bet: Bet) -> String? {
        if let event = events.first(where: { $0.id.uuidString.lowercased() == bet.eventId.lowercased() }) {
            return event.league
        }
        return bet.sportLeague
    }

    // MARK: - Financials Card

    private var detailFinancialsCard: some View {
        VStack(spacing: 0) {
            detailSectionHeader("FINANCIALS")

            VStack(spacing: 10) {
                detailLabeledRow(label: "Stake", value: formattedStake)
                detailLabeledRow(label: "Odds", value: formattedOdds, valueColor: Theme.gold)

                Divider().background(Theme.divider)

                if isSettled {
                    let profitStr = potentialPayout > 0 ? "+\(formattedPotentialPayout)" : formattedPotentialPayout
                    detailLabeledRow(label: "Profit", value: profitStr, valueColor: presenter.profitColor)
                    detailLabeledRow(label: "Total Return", value: formattedTotalReturn)
                } else {
                    detailLabeledRow(label: "Potential", value: "+\(formattedPotentialPayout)", valueColor: Theme.accent)
                    detailLabeledRow(label: "Total Return", value: formattedTotalReturn)
                }
            }
            .padding(12)
        }
        .background(detailCardBackground)
    }

    // MARK: - Activity Card

    private var detailActivityCard: some View {
        VStack(spacing: 0) {
            detailSectionHeader("ACTIVITY")

            VStack(spacing: 10) {
                detailLabeledRow(label: "Placed", value: formattedDate, valueColor: Theme.textSecondary)

                detailLabeledRow(
                    label: "Pick ID",
                    value: String(bet.id.uuidString.prefix(8)) + "...",
                    valueColor: Theme.textMuted
                )

                if let player = bet.player {
                    detailLabeledRow(label: "Member", value: player.name)
                }

                NavigationLink {
                    BetHistoryView(betId: bet.id)
                } label: {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(Theme.accent)
                        Text("View History")
                            .font(Theme.bodyFont(size: 14))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textMuted)
                    }
                }
            }
            .padding(12)
        }
        .background(detailCardBackground)
    }

    // MARK: - Actions Card

    private var detailActionsCard: some View {
        VStack(spacing: 0) {
            detailSectionHeader("ACTIONS")

            VStack(spacing: 10) {
                actionButtons
            }
            .padding(12)
        }
        .background(detailCardBackground)
    }

    // MARK: - Actions

    private func acceptBet() {
        Task {
            do {
                try await BetService.acceptBet(bet)
            } catch {
                print("Failed to accept bet: \(error)")
            }
        }
    }

    private func declineBet() {
        Task {
            do {
                try await BetService.declineBet(bet)
            } catch {
                print("Failed to decline bet: \(error)")
            }
        }
    }

    private func voidBet() {
        Task {
            do {
                try await BetService.voidBet(bet)
            } catch {
                print("Failed to void bet: \(error)")
            }
        }
    }

    private func settleBet() {
        Task {
            do {
                if bet.isParlay {
                    try await GradingService.settleParlayBets(parlayBets, policy: parlayPolicy, in: modelContext)
                } else {
                    try await GradingService.settleBet(bet, in: modelContext)
                }
            } catch {
                print("Failed to settle bet: \(error)")
            }
        }
    }

    // MARK: - Override Grade

    /// Available outcome options for override (includes void)
    private let overrideOutcomeOptions = ["win", "loss", "push", "void"]

    /// Prepare the override grade sheet with current values
    private func prepareOverrideGradeSheet() {
        overrideNewOutcome = bet.gradeResult?.rawValue ?? "win"
        overrideReason = ""
        overrideIsLoading = false
        overrideErrorMessage = nil
        showingOverrideGradeSheet = true
    }

    /// Whether the confirm button should be disabled
    private var isOverrideConfirmDisabled: Bool {
        overrideReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        overrideNewOutcome == bet.gradeResult?.rawValue ||
        overrideIsLoading
    }

    /// Human-readable label for an outcome
    private func outcomeLabel(_ outcome: String) -> String {
        switch outcome {
        case "win": return "Win"
        case "loss": return "Loss"
        case "push": return "Push"
        case "void": return "Void"
        default: return outcome.capitalized
        }
    }

    /// Color for an outcome
    private func outcomeColor(_ outcome: String) -> Color {
        switch outcome {
        case "win": return Theme.accent
        case "loss": return Theme.danger
        case "push": return Theme.warning
        case "void": return Theme.textMuted
        default: return Theme.textSecondary
        }
    }

    /// The sheet content for overriding a grade
    @ViewBuilder
    private var overrideGradeSheetContent: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                VStack(spacing: 24) {
                    // Current Grade Display
                    VStack(spacing: 8) {
                        Text("Current Grade")
                            .font(Theme.subheadline)
                            .foregroundStyle(Theme.textSecondary)

                        if let currentGrade = bet.gradeResult {
                            Text(outcomeLabel(currentGrade.rawValue))
                                .font(Theme.title2)
                                .foregroundStyle(outcomeColor(currentGrade.rawValue))
                        } else {
                            Text("Not Graded")
                                .font(Theme.title2)
                                .foregroundStyle(Theme.textMuted)
                        }

                        if bet.status == .settled {
                            Text("Reconciliation will be reversed")
                                .font(Theme.caption)
                                .foregroundStyle(Theme.warning)
                                .padding(.top, 4)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Theme.cardBackground)
                    .cornerRadius(Theme.cornerRadius)

                    // New Grade Picker
                    VStack(alignment: .leading, spacing: 12) {
                        Text("New Grade")
                            .font(Theme.subheadline)
                            .foregroundStyle(Theme.textSecondary)

                        Picker("New Grade", selection: $overrideNewOutcome) {
                            ForEach(overrideOutcomeOptions, id: \.self) { outcome in
                                Text(outcomeLabel(outcome))
                                    .tag(outcome)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    // Reason TextField
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reason (Required)")
                            .font(Theme.subheadline)
                            .foregroundStyle(Theme.textSecondary)

                        TextField("Enter reason for override...", text: $overrideReason, axis: .vertical)
                            .textFieldStyle(.plain)
                            .padding()
                            .background(Theme.cardBackground)
                            .cornerRadius(Theme.cornerRadiusSmall)
                            .lineLimit(3...6)
                    }

                    Spacer()

                    // Confirm Button
                    Button {
                        Task {
                            await submitOverrideGrade()
                        }
                    } label: {
                        if overrideIsLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: Theme.background))
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else {
                            Text("Confirm Override")
                                .font(Theme.headline)
                                .foregroundStyle(Theme.background)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                    }
                    .background(isOverrideConfirmDisabled ? Theme.accent.opacity(0.5) : Theme.accent)
                    .cornerRadius(Theme.cornerRadiusSmall)
                    .disabled(isOverrideConfirmDisabled)
                }
                .padding()
            }
            .navigationTitle("Override Grade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingOverrideGradeSheet = false
                    }
                    .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    /// Submit the override grade request to the Edge Function
    private func submitOverrideGrade() async {
        overrideIsLoading = true

        do {
            let request = OverrideGradeRequest(
                betId: bet.id,
                newOutcome: overrideNewOutcome,
                reason: overrideReason.trimmingCharacters(in: .whitespacesAndNewlines),
                idempotencyKey: UUID().uuidString
            )

            let response: OverrideGradeResponse = try await EdgeFunctionService.shared.callFunction(
                name: "override_grade",
                body: request
            )

            // Update local bet with response
            await MainActor.run {
                if let newGradeResult = GradeResult(rawValue: response.bet.gradeResult ?? "") {
                    bet.gradeResult = newGradeResult
                }
                if let newStatus = BetStatus(rawValue: response.bet.status) {
                    bet.status = newStatus
                }

                overrideIsLoading = false
                showingOverrideGradeSheet = false
            }
        } catch let error as EdgeFunctionError {
            await MainActor.run {
                overrideIsLoading = false
                overrideErrorMessage = error.errorDescription
                showingOverrideGradeSheet = false
                showingOverrideError = true
            }
        } catch {
            await MainActor.run {
                overrideIsLoading = false
                overrideErrorMessage = error.localizedDescription
                showingOverrideGradeSheet = false
                showingOverrideError = true
            }
        }
    }

    // MARK: - Reverse Settlement

    /// Prepare the reverse settlement sheet with reset values
    private func prepareReverseSettlementSheet() {
        reverseReason = ""
        reverseIsLoading = false
        reverseErrorMessage = nil
        showingReverseSettlementSheet = true
    }

    /// Whether the reverse confirm button should be disabled
    private var isReverseConfirmDisabled: Bool {
        reverseReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || reverseIsLoading
    }

    /// The sheet content for reversing a settlement
    @ViewBuilder
    private var reverseSettlementSheetContent: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                VStack(spacing: 24) {
                    // Warning Section
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(Theme.largeTitle)
                            .foregroundStyle(Theme.warning)

                        Text("Reverse Reconciliation")
                            .font(Theme.title2)
                            .foregroundStyle(Theme.textPrimary)

                        Text("This will undo the ledger entry created when this pick was reconciled. The member's balance will be adjusted accordingly.")
                            .font(Theme.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Theme.cardBackground)
                    .cornerRadius(Theme.cornerRadius)

                    // Impact Description
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Balance Impact")
                            .font(Theme.subheadline)
                            .foregroundStyle(Theme.textSecondary)

                        Text(reversalImpactDescription)
                            .font(Theme.body)
                            .foregroundStyle(Theme.textPrimary)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.cardBackground)
                            .cornerRadius(Theme.cornerRadiusSmall)
                    }

                    // Reason TextField
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reason (Required)")
                            .font(Theme.subheadline)
                            .foregroundStyle(Theme.textSecondary)

                        TextField("Enter reason for reversal...", text: $reverseReason, axis: .vertical)
                            .textFieldStyle(.plain)
                            .padding()
                            .background(Theme.cardBackground)
                            .cornerRadius(Theme.cornerRadiusSmall)
                            .lineLimit(3...6)
                    }

                    Spacer()

                    // Confirm Button
                    Button {
                        Task {
                            await submitReverseSettlement()
                        }
                    } label: {
                        if reverseIsLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: Theme.background))
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else {
                            Text("Confirm Reversal")
                                .font(Theme.headline)
                                .foregroundStyle(Theme.background)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                    }
                    .background(isReverseConfirmDisabled ? Theme.danger.opacity(0.5) : Theme.danger)
                    .cornerRadius(Theme.cornerRadiusSmall)
                    .disabled(isReverseConfirmDisabled)
                }
                .padding()
            }
            .navigationTitle("Reverse Reconciliation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingReverseSettlementSheet = false
                    }
                    .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    /// Submit the reverse settlement request to the Edge Function
    private func submitReverseSettlement() async {
        reverseIsLoading = true

        do {
            let request = ReverseSettlementRequest(
                betId: bet.id,
                reason: reverseReason.trimmingCharacters(in: .whitespacesAndNewlines),
                idempotencyKey: UUID().uuidString
            )

            let response: ReverseSettlementResponse = try await EdgeFunctionService.shared.callFunction(
                name: "reverse_settlement",
                body: request
            )

            // Update local bet with response
            await MainActor.run {
                if let newStatus = BetStatus(rawValue: response.bet.status) {
                    bet.status = newStatus
                }

                reverseIsLoading = false
                showingReverseSettlementSheet = false
                showingReverseSuccess = true
            }
        } catch let error as EdgeFunctionError {
            await MainActor.run {
                reverseIsLoading = false
                reverseErrorMessage = error.errorDescription
                showingReverseSettlementSheet = false
                showingReverseError = true
            }
        } catch {
            await MainActor.run {
                reverseIsLoading = false
                reverseErrorMessage = error.localizedDescription
                showingReverseSettlementSheet = false
                showingReverseError = true
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

    private func gradeResultColor(_ result: GradeResult) -> Color {
        switch result {
        case .win: return Theme.accent
        case .loss: return Theme.danger
        case .push: return Theme.warning
        }
    }
}

// MARK: - Override Grade Request/Response

/// Request body for override_grade Edge Function
private struct OverrideGradeRequest: Encodable {
    let betId: UUID
    let newOutcome: String
    let reason: String
    let idempotencyKey: String

    enum CodingKeys: String, CodingKey {
        case betId = "bet_id"
        case newOutcome = "new_outcome"
        case reason
        case idempotencyKey = "idempotency_key"
    }
}

/// Response from override_grade Edge Function
private struct OverrideGradeResponse: Decodable {
    let success: Bool
    let bet: OverrideGradeBetResponse
    let settlementReversed: Bool

    enum CodingKeys: String, CodingKey {
        case success
        case bet
        case settlementReversed = "settlement_reversed"
    }
}

/// Bet data from override_grade response
private struct OverrideGradeBetResponse: Decodable {
    let id: UUID
    let status: String
    let gradeResult: String?

    enum CodingKeys: String, CodingKey {
        case id
        case status
        case gradeResult = "grade_result"
    }
}

// MARK: - Reverse Settlement Request/Response

/// Request body for reverse_settlement Edge Function
private struct ReverseSettlementRequest: Encodable {
    let betId: UUID
    let reason: String
    let idempotencyKey: String

    enum CodingKeys: String, CodingKey {
        case betId = "bet_id"
        case reason
        case idempotencyKey = "idempotency_key"
    }
}

/// Response from reverse_settlement Edge Function
private struct ReverseSettlementResponse: Decodable {
    let success: Bool
    let bet: ReverseSettlementBetResponse
    let reversalEntry: ReverseSettlementLedgerResponse

    enum CodingKeys: String, CodingKey {
        case success
        case bet
        case reversalEntry = "reversal_entry"
    }
}

/// Bet data from reverse_settlement response
private struct ReverseSettlementBetResponse: Decodable {
    let id: UUID
    let status: String

    enum CodingKeys: String, CodingKey {
        case id
        case status
    }
}

/// Ledger entry data from reverse_settlement response
private struct ReverseSettlementLedgerResponse: Decodable {
    let id: UUID
    let amount: String
    let type: String

    enum CodingKeys: String, CodingKey {
        case id
        case amount
        case type
    }
}

#Preview {
    BetsListView()
        .modelContainer(for: [Bet.self, Event.self], inMemory: true)
}
