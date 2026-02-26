import SwiftUI
import SwiftData

/// Represents a group of parlay legs or a single bet for display in grading
struct GradingGroup: Identifiable {
    let id: UUID // ticketId for parlays, bet.id for singles
    let bets: [Bet]
    let isParlay: Bool

    var firstBet: Bet? { bets.first }
}

struct GradingView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var bets: [Bet]
    @Query private var events: [Event]
    @Query private var policies: [AcceptancePolicy]

    @State private var selectedBets: Set<UUID> = []
    @State private var isMultiSelectMode = false
    @State private var showingBulkSettlementConfirmation = false
    @State private var showingBulkSettlementSuccess = false
    @State private var settlementSummary: BulkSettlementSummary?

    /// Get the current parlay push/void policy
    private var parlayPolicy: ParlayPushVoidPolicy {
        policies.first?.parlayPushVoidPolicyEnum ?? .reduceLegReprice
    }

    /// Bets ready to grade, sorted by creation date (oldest first for grading priority)
    /// Includes both:
    /// - Bets explicitly marked as readyToGrade
    /// - Accepted bets whose events are finalized (handles server-side finalization via sync)
    private var readyToGradeBets: [Bet] {
        bets.filter { bet in
            if bet.status == .readyToGrade {
                return true
            }
            // Also include accepted bets whose event is final (server-side finalization)
            if bet.status == .accepted {
                let eventIsFinal = events.first { event in
                    event.id.uuidString.lowercased() == bet.eventId.lowercased()
                }?.status == .final
                return eventIsFinal
            }
            return false
        }
        .sorted { $0.createdAt < $1.createdAt }
    }

    /// Groups bets by ticketId for parlays, singles stay individual
    private var gradingGroups: [GradingGroup] {
        // Separate parlays and singles
        let parlayBets = readyToGradeBets.filter { $0.isParlay }
        let singleBets = readyToGradeBets.filter { !$0.isParlay }

        // Group parlay bets by ticketId
        var parlayGroups: [UUID: [Bet]] = [:]
        for bet in parlayBets {
            parlayGroups[bet.ticketId, default: []].append(bet)
        }

        // Also find other legs of parlays that may already be graded (same ticketId)
        for ticketId in parlayGroups.keys {
            // Get all bets with this ticketId (including already graded ones)
            let allLegsForTicket = bets.filter { $0.ticketId == ticketId }
            parlayGroups[ticketId] = allLegsForTicket.sorted { $0.createdAt < $1.createdAt }
        }

        // Create groups
        var groups: [GradingGroup] = []

        // Add parlay groups (sorted by earliest bet creation date)
        let sortedParlayGroups = parlayGroups.sorted {
            ($0.value.first?.createdAt ?? Date.distantPast) < ($1.value.first?.createdAt ?? Date.distantPast)
        }
        for (ticketId, betsInGroup) in sortedParlayGroups {
            groups.append(GradingGroup(id: ticketId, bets: betsInGroup, isParlay: true))
        }

        // Add single bets as individual groups
        for bet in singleBets {
            groups.append(GradingGroup(id: bet.id, bets: [bet], isParlay: false))
        }

        return groups
    }

    /// Bets that are graded and ready for settlement
    private var gradedBets: [Bet] {
        bets.filter { $0.status == .graded }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// Calculate settlement preview for confirmation dialog
    private var settlementPreview: BulkSettlementPreview {
        var totalWinnings: Decimal = 0
        var totalLosses: Decimal = 0

        for bet in gradedBets {
            guard let gradeResult = bet.gradeResult else { continue }

            switch gradeResult {
            case .win:
                let payout = LiabilityService.calculatePayout(stake: bet.stake, odds: bet.odds)
                totalWinnings += payout
            case .loss:
                totalLosses += bet.stake
            case .push:
                break
            }
        }

        return BulkSettlementPreview(
            betCount: gradedBets.count,
            totalWinnings: totalWinnings,
            totalLosses: totalLosses,
            netImpact: totalWinnings - totalLosses
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Settle All Graded section
                if !gradedBets.isEmpty {
                    bulkSettlementBanner
                }

                Group {
                    if readyToGradeBets.isEmpty && gradedBets.isEmpty {
                        ContentUnavailableView(
                            "No Picks to Grade",
                            systemImage: "checkmark.circle",
                            description: Text("Picks ready for grading will appear here.")
                        )
                    } else if readyToGradeBets.isEmpty {
                        ContentUnavailableView(
                            "No Picks to Grade",
                            systemImage: "checkmark.circle",
                            description: Text("All picks have been graded. Use the button above to settle graded picks.")
                        )
                    } else {
                        List {
                            ForEach(gradingGroups) { group in
                                if group.isParlay {
                                    ParlayGradingGroupView(
                                        group: group,
                                        events: events,
                                        policy: parlayPolicy,
                                        selectedBets: $selectedBets,
                                        isMultiSelectMode: isMultiSelectMode,
                                        onSelect: { bet in toggleSelection(bet) },
                                        onGrade: { bet, result in gradeBet(bet, result: result) },
                                        onVoid: { bet in voidBet(bet) }
                                    )
                                } else if let bet = group.firstBet {
                                    GradingBetRow(
                                        bet: bet,
                                        event: event(for: bet),
                                        isSelected: selectedBets.contains(bet.id),
                                        isMultiSelectMode: isMultiSelectMode,
                                        onSelect: { toggleSelection(bet) },
                                        onGrade: { result in gradeBet(bet, result: result) },
                                        onVoid: { voidBet(bet) }
                                    )
                                }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .background(Theme.background)
                    }
                }
            }
            .background(Theme.background)
            .navigationTitle("Grading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !readyToGradeBets.isEmpty {
                        Button(isMultiSelectMode ? "Done" : "Select") {
                            toggleMultiSelectMode()
                        }
                    }
                }

                ToolbarItem(placement: .topBarLeading) {
                    if isMultiSelectMode && !selectedBets.isEmpty {
                        Menu {
                            Button {
                                bulkGrade(.win)
                            } label: {
                                Label("Grade All Win", systemImage: "checkmark.circle.fill")
                            }

                            Button {
                                bulkGrade(.loss)
                            } label: {
                                Label("Grade All Loss", systemImage: "xmark.circle.fill")
                            }

                            Button {
                                bulkGrade(.push)
                            } label: {
                                Label("Grade All Push", systemImage: "equal.circle.fill")
                            }
                        } label: {
                            Text("Grade (\(selectedBets.count))")
                        }
                    }
                }
            }
            .confirmationDialog(
                "Settle All Graded Picks?",
                isPresented: $showingBulkSettlementConfirmation,
                titleVisibility: .visible
            ) {
                Button("Settle All") {
                    performBulkSettlement()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                let preview = settlementPreview
                Text("""
                    Total picks to settle: \(preview.betCount)
                    Total member winnings: \(formatCurrency(preview.totalWinnings))
                    Total member losses: \(formatCurrency(preview.totalLosses))
                    Net impact: \(formatCurrency(preview.netImpact))
                    """)
            }
            .alert("Settlement Complete", isPresented: $showingBulkSettlementSuccess) {
                Button("OK") {
                    settlementSummary = nil
                }
            } message: {
                if let summary = settlementSummary {
                    Text("Settled \(summary.settledCount) picks: \(summary.winCount) wins, \(summary.lossCount) losses, \(summary.pushCount) pushes")
                }
            }
        }
    }

    // MARK: - Bulk Settlement Banner

    private var bulkSettlementBanner: some View {
        Button {
            showingBulkSettlementConfirmation = true
        } label: {
            HStack {
                Image(systemName: "dollarsign.circle.fill")
                    .font(Theme.title2)
                    .foregroundStyle(Theme.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Settle All Graded")
                        .font(Theme.headline)
                        .foregroundStyle(Theme.textPrimary)

                    Text("\(gradedBets.count) pick\(gradedBets.count == 1 ? "" : "s") ready")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textMuted)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textMuted)
            }
            .padding()
            .background(Theme.cardBackground)
            .overlay(
                Rectangle()
                    .fill(Theme.accent)
                    .frame(width: 4),
                alignment: .leading
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helper Methods

    private func event(for bet: Bet) -> Event? {
        events.first { $0.id.uuidString.lowercased() == bet.eventId.lowercased() }
    }

    private func toggleSelection(_ bet: Bet) {
        if selectedBets.contains(bet.id) {
            selectedBets.remove(bet.id)
        } else {
            selectedBets.insert(bet.id)
        }
    }

    private func toggleMultiSelectMode() {
        isMultiSelectMode.toggle()
        if !isMultiSelectMode {
            selectedBets.removeAll()
        }
    }

    private func gradeBet(_ bet: Bet, result: GradeResult) {
        Task {
            do {
                try await GradingService.gradeBet(bet, result: result)
                selectedBets.remove(bet.id)
            } catch {
                print("Failed to grade bet: \(error)")
            }
        }
    }

    private func voidBet(_ bet: Bet) {
        Task {
            do {
                try await GradingService.voidBet(bet)
                selectedBets.remove(bet.id)
            } catch {
                print("Failed to void bet: \(error)")
            }
        }
    }

    private func bulkGrade(_ result: GradeResult) {
        let betsToGrade = selectedBets.compactMap { betId in
            readyToGradeBets.first(where: { $0.id == betId })
        }
        selectedBets.removeAll()
        isMultiSelectMode = false
        Task {
            for bet in betsToGrade {
                do {
                    try await GradingService.gradeBet(bet, result: result)
                } catch {
                    print("Failed to grade bet \(bet.id): \(error)")
                }
            }
        }
    }

    // MARK: - Bulk Settlement

    private func performBulkSettlement() {
        let betsToSettle = gradedBets
        let allBetsSnapshot = bets
        let policy = parlayPolicy
        let context = modelContext

        Task {
            var winCount = 0
            var lossCount = 0
            var pushCount = 0
            var settledCount = 0

            // Track which parlay ticketIds we've already settled
            var settledParlayTicketIds: Set<UUID> = []

            for bet in betsToSettle {
                // Handle parlay bets as groups
                if bet.isParlay {
                    // Skip if we've already settled this parlay's ticketId
                    if settledParlayTicketIds.contains(bet.ticketId) {
                        continue
                    }

                    // Get all bets for this parlay (including already graded ones)
                    let parlayBets = allBetsSnapshot.filter { $0.ticketId == bet.ticketId }

                    // Check if all legs are graded
                    let allGraded = parlayBets.allSatisfy { parlayBet in
                        parlayBet.gradeResult != nil || parlayBet.status == .void
                    }

                    if allGraded {
                        do {
                            try await GradingService.settleParlayBets(parlayBets, policy: policy, in: context)
                            settledCount += 1
                            settledParlayTicketIds.insert(bet.ticketId)

                            // Determine the outcome for counting
                            let outcome = ParlayGradingService.calculateParlayOutcome(bets: parlayBets, policy: policy)
                            switch outcome {
                            case .win: winCount += 1
                            case .loss: lossCount += 1
                            case .push: pushCount += 1
                            case .pending, .partiallyGraded: break
                            }
                        } catch {
                            print("Failed to settle parlay \(bet.ticketId): \(error)")
                        }
                    }
                } else {
                    // Handle single bets
                    do {
                        try await GradingService.settleBet(bet, in: context)
                        settledCount += 1

                        if let gradeResult = bet.gradeResult {
                            switch gradeResult {
                            case .win: winCount += 1
                            case .loss: lossCount += 1
                            case .push: pushCount += 1
                            }
                        }
                    } catch {
                        print("Failed to settle bet \(bet.id): \(error)")
                    }
                }
            }

            settlementSummary = BulkSettlementSummary(
                settledCount: settledCount,
                winCount: winCount,
                lossCount: lossCount,
                pushCount: pushCount
            )
            showingBulkSettlementSuccess = true
        }
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }
}

// MARK: - Bulk Settlement Models

struct BulkSettlementPreview {
    let betCount: Int
    let totalWinnings: Decimal
    let totalLosses: Decimal
    let netImpact: Decimal
}

struct BulkSettlementSummary {
    let settledCount: Int
    let winCount: Int
    let lossCount: Int
    let pushCount: Int
}

// MARK: - Grading Bet Row

struct GradingBetRow: View {
    let bet: Bet
    let event: Event?
    let isSelected: Bool
    let isMultiSelectMode: Bool
    let onSelect: () -> Void
    let onGrade: (GradeResult) -> Void
    var onVoid: (() -> Void)? = nil

    private var eventName: String {
        if let event = event {
            return "\(event.awayTeam) @ \(event.homeTeam)"
        }
        return bet.eventDescription ?? "Event \(bet.eventId.prefix(8))"
    }

    private var formattedStake: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: bet.stake as NSDecimalNumber) ?? "$\(bet.stake)"
    }

    /// Suggested outcome based on event final score (if available)
    private var suggestedOutcome: GradeResult? {
        guard let event = event,
              event.status == .final,
              let finalScore = event.finalScore else {
            return nil
        }

        // Parse final score (expected format: "homeScore-awayScore" like "24-17")
        let parts = finalScore.split(separator: "-")
        guard parts.count == 2,
              let homeScore = Int(parts[0].trimmingCharacters(in: .whitespaces)),
              let awayScore = Int(parts[1].trimmingCharacters(in: .whitespaces)) else {
            return nil
        }

        // Determine suggestion based on bet side and market
        let sideNormalized = bet.side.lowercased()
        let marketNormalized = bet.market.lowercased()

        // For moneyline bets
        if marketNormalized.contains("moneyline") || marketNormalized.contains("ml") {
            if sideNormalized.lowercased() == event.homeTeam.lowercased() {
                if homeScore > awayScore {
                    return .win
                } else if homeScore < awayScore {
                    return .loss
                } else {
                    return .push
                }
            } else if sideNormalized.lowercased() == event.awayTeam.lowercased() {
                if awayScore > homeScore {
                    return .win
                } else if awayScore < homeScore {
                    return .loss
                } else {
                    return .push
                }
            }
        }

        // For total (over/under) bets
        if marketNormalized.contains("total") || marketNormalized.contains("over") || marketNormalized.contains("under") {
            let totalPoints = homeScore + awayScore

            // Extract the line from the side (e.g., "Over 45.5" -> 45.5)
            if let lineValue = extractLine(from: bet.side) {
                if sideNormalized.contains("over") {
                    if Double(totalPoints) > lineValue {
                        return .win
                    } else if Double(totalPoints) < lineValue {
                        return .loss
                    } else {
                        return .push
                    }
                } else if sideNormalized.contains("under") {
                    if Double(totalPoints) < lineValue {
                        return .win
                    } else if Double(totalPoints) > lineValue {
                        return .loss
                    } else {
                        return .push
                    }
                }
            }
        }

        // For spread bets
        if marketNormalized.contains("spread") {
            // Extract the spread from the side (e.g., "Team -3.5" -> -3.5)
            if let spreadValue = extractLine(from: bet.side) {
                let isHome = sideNormalized.lowercased().contains(event.homeTeam.lowercased())
                let adjustedDiff: Double

                if isHome {
                    // Home team with spread
                    adjustedDiff = Double(homeScore - awayScore) + spreadValue
                } else {
                    // Away team with spread
                    adjustedDiff = Double(awayScore - homeScore) + spreadValue
                }

                if adjustedDiff > 0 {
                    return .win
                } else if adjustedDiff < 0 {
                    return .loss
                } else {
                    return .push
                }
            }
        }

        return nil
    }

    /// Extracts a numeric line/spread from a bet side string
    private func extractLine(from side: String) -> Double? {
        // Match patterns like "+3.5", "-3.5", "45.5", etc.
        let pattern = #"[+-]?\d+\.?\d*"#
        if let range = side.range(of: pattern, options: .regularExpression) {
            return Double(side[range])
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top row: Player name, event status, and selection
            HStack {
                if isMultiSelectMode {
                    Button {
                        onSelect()
                    } label: {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
                            .font(Theme.title2)
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(bet.player?.name ?? "Unknown Member")
                        .font(Theme.headline)

                    Text(eventName)
                        .font(Theme.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer()

                // Show final score if available
                if let event = event, let finalScore = event.finalScore, event.status == .final {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Final")
                            .font(Theme.caption2)
                            .foregroundStyle(Theme.textSecondary)
                        Text(finalScore)
                            .font(Theme.subheadline)
                            .fontWeight(.semibold)
                    }
                }
            }

            // Pick info via shared SelectionRow
            HStack {
                SelectionRow(
                    selectionLabel: bet.side,
                    odds: bet.odds,
                    eventName: eventName,
                    league: event?.league ?? bet.sportLeague
                )

                Spacer()

                Text(formattedStake)
                    .font(Theme.font(size: 15, weight: .bold))
            }

            // Suggested outcome (if available)
            if let suggested = suggestedOutcome {
                HStack {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(.yellow)
                        .font(Theme.caption)

                    Text("Suggested: \(suggested.rawValue.capitalized)")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            // Grading buttons (only when not in multi-select mode)
            if !isMultiSelectMode {
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        Button {
                            onGrade(.win)
                        } label: {
                            Label("Win", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)

                        Button {
                            onGrade(.loss)
                        } label: {
                            Label("Loss", systemImage: "xmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.danger)

                        Button {
                            onGrade(.push)
                        } label: {
                            Label("Push", systemImage: "equal.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.warning)
                    }
                    .labelStyle(.titleOnly)

                    // Void button (secondary option)
                    if let onVoid = onVoid {
                        Button {
                            onVoid()
                        } label: {
                            Label("Void Pick", systemImage: "nosign")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(Theme.textMuted)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Parlay Grading Group View

/// Displays a parlay with all its legs grouped together for grading
struct ParlayGradingGroupView: View {
    let group: GradingGroup
    let events: [Event]
    let policy: ParlayPushVoidPolicy
    @Binding var selectedBets: Set<UUID>
    let isMultiSelectMode: Bool
    let onSelect: (Bet) -> Void
    let onGrade: (Bet, GradeResult) -> Void
    var onVoid: ((Bet) -> Void)? = nil

    /// Legs that still need grading
    /// Includes both readyToGrade bets and accepted bets with finalized events
    private var legsToGrade: [Bet] {
        group.bets.filter { bet in
            if bet.status == .readyToGrade {
                return true
            }
            // Also include accepted bets whose event is final
            if bet.status == .accepted {
                let eventIsFinal = events.first { event in
                    event.id.uuidString.lowercased() == bet.eventId.lowercased()
                }?.status == .final
                return eventIsFinal
            }
            return false
        }
    }

    /// Number of legs that have been graded
    private var gradedCount: Int {
        group.bets.filter { $0.gradeResult != nil || $0.status == .void }.count
    }

    /// Total number of legs in the parlay
    private var totalLegs: Int {
        group.bets.count
    }

    /// Calculate the projected outcome based on current grades
    private var projectedOutcome: ParlayProjectedOutcome {
        // Check for any losses first
        let hasLoss = group.bets.contains { $0.gradeResult == .loss }
        if hasLoss {
            let lostLegs = group.bets.filter { $0.gradeResult == .loss }.count
            return .willLose(lostLegs: lostLegs)
        }

        // Count wins, pushes, and pending
        let winCount = group.bets.filter { $0.gradeResult == .win }.count
        let pushVoidCount = group.bets.filter { $0.gradeResult == .push || $0.status == .void }.count
        let pendingCount = group.bets.filter { $0.gradeResult == nil && $0.status != .void }.count

        if pendingCount == 0 {
            // All graded, no losses
            if pushVoidCount > 0 {
                switch policy {
                case .treatAsPush:
                    return .willPush
                case .reduceLegReprice:
                    if winCount == 0 {
                        return .willPush
                    }
                    return .canWin(validLegs: winCount)
                }
            }
            return .canWin(validLegs: winCount)
        }

        // Still has pending legs
        return .inProgress(gradedCount: gradedCount, totalCount: totalLegs)
    }

    /// Calculate the projected payout if all remaining legs win
    private var projectedPayout: Decimal? {
        guard let firstBet = group.bets.first else { return nil }

        // If parlay already lost, no payout
        if group.bets.contains(where: { $0.gradeResult == .loss }) {
            return nil
        }

        // Calculate assuming all pending legs win
        let stake = firstBet.stake

        // For reduceLegReprice, only use won + pending legs (exclude push/void)
        // For treatAsPush with any push/void, payout would be 0
        let hasPushVoid = group.bets.contains { $0.gradeResult == .push || $0.status == .void }
        if hasPushVoid && policy == .treatAsPush {
            return nil
        }

        // Get legs that would count (won + pending, excluding push/void)
        let validLegs = group.bets.filter { bet in
            bet.status != .void && bet.gradeResult != .push
        }

        if validLegs.isEmpty {
            return Decimal.zero
        }

        return ParlayGradingService.calculateParlayPayout(stake: stake, bets: validLegs, excludeVoidPush: false)
    }

    /// Format currency value
    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }

    /// Get event for a bet
    private func event(for bet: Bet) -> Event? {
        events.first { $0.id.uuidString.lowercased() == bet.eventId.lowercased() }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Parlay Status Header
            parlayStatusHeader

            // Projected Outcome
            projectedOutcomeView

            // Divider
            Rectangle()
                .fill(Theme.divider)
                .frame(height: 1)

            // Individual legs
            ForEach(group.bets) { bet in
                ParlayLegRow(
                    bet: bet,
                    event: event(for: bet),
                    isSelected: selectedBets.contains(bet.id),
                    isMultiSelectMode: isMultiSelectMode,
                    onSelect: { onSelect(bet) },
                    onGrade: { result in onGrade(bet, result) },
                    onVoid: onVoid != nil ? { onVoid?(bet) } : nil
                )

                if bet.id != group.bets.last?.id {
                    Rectangle()
                        .fill(Theme.divider.opacity(0.5))
                        .frame(height: 1)
                        .padding(.leading, 28)
                }
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Parlay Status Header

    private var parlayStatusHeader: some View {
        HStack {
            // Parlay icon
            Image(systemName: "link")
                .foregroundStyle(Theme.accentSecondary)
                .font(Theme.title3)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("Multi-Pick")
                        .font(Theme.headline)
                        .foregroundStyle(Theme.textPrimary)

                    Text("(\(totalLegs) legs)")
                        .font(Theme.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }

                Text("\(gradedCount) of \(totalLegs) legs graded")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textMuted)
            }

            Spacer()

            // Player name
            if let player = group.bets.first?.player {
                Text(player.bookieDisplayName)
                    .font(Theme.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    // MARK: - Projected Outcome View

    @ViewBuilder
    private var projectedOutcomeView: some View {
        HStack(spacing: 12) {
            switch projectedOutcome {
            case .willLose(let lostLegs):
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.danger)
                    Text("Will lose - \(lostLegs) leg\(lostLegs == 1 ? "" : "s") lost")
                        .font(Theme.font(size: 15, weight: .medium))
                        .foregroundStyle(Theme.danger)
                }

            case .willPush:
                HStack(spacing: 6) {
                    Image(systemName: "equal.circle.fill")
                        .foregroundStyle(Theme.warning)
                    Text("Will push - stake returned")
                        .font(Theme.font(size: 15, weight: .medium))
                        .foregroundStyle(Theme.warning)
                }

            case .canWin(let validLegs):
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.accent)
                    Text("Can win - \(validLegs) leg\(validLegs == 1 ? "" : "s") won")
                        .font(Theme.font(size: 15, weight: .medium))
                        .foregroundStyle(Theme.accent)
                }

            case .inProgress(let graded, let total):
                HStack(spacing: 6) {
                    Image(systemName: "clock.fill")
                        .foregroundStyle(Theme.textMuted)
                    Text("In progress - \(graded)/\(total) graded")
                        .font(Theme.font(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            Spacer()

            // Projected payout if applicable
            if let payout = projectedPayout, payout > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Projected return")
                        .font(Theme.caption2)
                        .foregroundStyle(Theme.textMuted)
                    Text(formatCurrency(payout))
                        .font(Theme.font(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.elevatedBackground.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// Projected outcome states for a parlay
enum ParlayProjectedOutcome {
    case willLose(lostLegs: Int)
    case willPush
    case canWin(validLegs: Int)
    case inProgress(gradedCount: Int, totalCount: Int)
}

// MARK: - Parlay Leg Row

/// Individual leg row within a parlay group - simplified version for parlay display
struct ParlayLegRow: View {
    let bet: Bet
    let event: Event?
    let isSelected: Bool
    let isMultiSelectMode: Bool
    let onSelect: () -> Void
    let onGrade: (GradeResult) -> Void
    var onVoid: (() -> Void)? = nil

    private var eventName: String {
        if let event = event {
            return "\(event.awayTeam) @ \(event.homeTeam)"
        }
        return bet.eventDescription ?? "Event \(bet.eventId.prefix(8))"
    }

    /// Whether this leg has already been graded
    private var isGraded: Bool {
        bet.gradeResult != nil || bet.status == .void
    }

    /// Status indicator color
    private var statusColor: Color {
        if bet.status == .void {
            return Theme.textMuted
        }
        guard let result = bet.gradeResult else {
            return Theme.textMuted
        }
        switch result {
        case .win: return Theme.accent
        case .loss: return Theme.danger
        case .push: return Theme.warning
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator dot for ungraded legs (SelectionRow handles graded legs)
            if !isGraded {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
            }

            // Multi-select checkbox (only for ungraded legs)
            if isMultiSelectMode && !isGraded {
                Button {
                    onSelect()
                } label: {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
                        .font(Theme.title3)
                }
                .buttonStyle(.plain)
            }

            // Leg info via shared SelectionRow
            SelectionRow(
                selectionLabel: bet.side,
                odds: bet.odds,
                eventName: eventName,
                league: event?.league ?? bet.sportLeague,
                gradeResult: isGraded ? bet.gradeResult : nil
            )
            .opacity(isGraded ? 0.6 : 1.0)

            Spacer()

            // Status badge or grading buttons
            if isGraded {
                let (settlement, _) = PickPresenter.mapStatus(betStatus: bet.status, gradeResult: bet.gradeResult)
                StatusPill(settlementStatus: settlement)
            } else if !isMultiSelectMode {
                // Compact grading buttons
                HStack(spacing: 8) {
                    Button {
                        onGrade(.win)
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(Theme.title2)
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)

                    Button {
                        onGrade(.loss)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(Theme.title2)
                            .foregroundStyle(Theme.danger)
                    }
                    .buttonStyle(.plain)

                    Button {
                        onGrade(.push)
                    } label: {
                        Image(systemName: "equal.circle.fill")
                            .font(Theme.title2)
                            .foregroundStyle(Theme.warning)
                    }
                    .buttonStyle(.plain)

                    // Void button
                    if let onVoid = onVoid {
                        Button {
                            onVoid()
                        } label: {
                            Image(systemName: "nosign")
                                .font(Theme.title2)
                                .foregroundStyle(Theme.textMuted)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    GradingView()
        .modelContainer(for: [Bet.self, Event.self, Player.self, AcceptancePolicy.self], inMemory: true)
}
