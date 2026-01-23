import SwiftUI
import SwiftData

struct GradingView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var bets: [Bet]
    @Query private var events: [Event]

    @State private var selectedBets: Set<UUID> = []
    @State private var isMultiSelectMode = false
    @State private var showingBulkSettlementConfirmation = false
    @State private var showingBulkSettlementSuccess = false
    @State private var settlementSummary: BulkSettlementSummary?

    /// Bets ready to grade, sorted by creation date (oldest first for grading priority)
    private var readyToGradeBets: [Bet] {
        bets.filter { $0.status == .readyToGrade }
            .sorted { $0.createdAt < $1.createdAt }
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
                            "No Bets to Grade",
                            systemImage: "checkmark.circle",
                            description: Text("Bets ready for grading will appear here.")
                        )
                    } else if readyToGradeBets.isEmpty {
                        ContentUnavailableView(
                            "No Bets to Grade",
                            systemImage: "checkmark.circle",
                            description: Text("All bets have been graded. Use the button above to settle graded bets.")
                        )
                    } else {
                        List {
                            ForEach(readyToGradeBets) { bet in
                                GradingBetRow(
                                    bet: bet,
                                    event: event(for: bet),
                                    isSelected: selectedBets.contains(bet.id),
                                    isMultiSelectMode: isMultiSelectMode,
                                    onSelect: { toggleSelection(bet) },
                                    onGrade: { result in gradeBet(bet, result: result) }
                                )
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
                "Settle All Graded Bets?",
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
                    Total bets to settle: \(preview.betCount)
                    Total player winnings: \(formatCurrency(preview.totalWinnings))
                    Total player losses: \(formatCurrency(preview.totalLosses))
                    Net impact: \(formatCurrency(preview.netImpact))
                    """)
            }
            .alert("Settlement Complete", isPresented: $showingBulkSettlementSuccess) {
                Button("OK") {
                    settlementSummary = nil
                }
            } message: {
                if let summary = settlementSummary {
                    Text("Settled \(summary.settledCount) bets: \(summary.winCount) wins, \(summary.lossCount) losses, \(summary.pushCount) pushes")
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
                    .font(.title2)
                    .foregroundStyle(Theme.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Settle All Graded")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)

                    Text("\(gradedBets.count) bet\(gradedBets.count == 1 ? "" : "s") ready")
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
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
        events.first { $0.id.uuidString == bet.eventId }
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
        let gradeResult = GradingService.gradeBet(bet, result: result)
        switch gradeResult {
        case .success:
            // Remove from selection if was selected
            selectedBets.remove(bet.id)
        case .failure(let error):
            print("Failed to grade bet: \(error)")
        }
    }

    private func bulkGrade(_ result: GradeResult) {
        // Grade all selected bets
        for betId in selectedBets {
            if let bet = readyToGradeBets.first(where: { $0.id == betId }) {
                let _ = GradingService.gradeBet(bet, result: result)
            }
        }
        selectedBets.removeAll()
        isMultiSelectMode = false
    }

    // MARK: - Bulk Settlement

    private func performBulkSettlement() {
        var winCount = 0
        var lossCount = 0
        var pushCount = 0
        var settledCount = 0

        for bet in gradedBets {
            let result = GradingService.settleBet(bet)
            switch result {
            case .success(let ledgerEntry):
                modelContext.insert(ledgerEntry)
                settledCount += 1

                if let gradeResult = bet.gradeResult {
                    switch gradeResult {
                    case .win: winCount += 1
                    case .loss: lossCount += 1
                    case .push: pushCount += 1
                    }
                }
            case .failure(let error):
                print("Failed to settle bet \(bet.id): \(error)")
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

    private var eventName: String {
        if let event = event {
            return "\(event.awayTeam) @ \(event.homeTeam)"
        }
        return "Event \(bet.eventId.prefix(8))"
    }

    private var formattedOdds: String {
        bet.odds > 0 ? "+\(bet.odds)" : "\(bet.odds)"
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
                            .foregroundStyle(isSelected ? .blue : .secondary)
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(bet.player?.name ?? "Unknown Player")
                        .font(.headline)

                    Text(eventName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Show final score if available
                if let event = event, let finalScore = event.finalScore, event.status == .final {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Final")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(finalScore)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                }
            }

            // Middle row: Bet details
            HStack {
                Text(bet.market)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("•")
                    .foregroundStyle(.secondary)

                Text(bet.side)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(formattedOdds)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(formattedStake)
                    .font(.subheadline.bold())
            }

            // Suggested outcome (if available)
            if let suggested = suggestedOutcome {
                HStack {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption)

                    Text("Suggested: \(suggested.rawValue.capitalized)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Grading buttons (only when not in multi-select mode)
            if !isMultiSelectMode {
                HStack(spacing: 12) {
                    Button {
                        onGrade(.win)
                    } label: {
                        Label("Win", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)

                    Button {
                        onGrade(.loss)
                    } label: {
                        Label("Loss", systemImage: "xmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)

                    Button {
                        onGrade(.push)
                    } label: {
                        Label("Push", systemImage: "equal.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
                .labelStyle(.titleOnly)
            }
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    GradingView()
        .modelContainer(for: [Bet.self, Event.self, Player.self], inMemory: true)
}
