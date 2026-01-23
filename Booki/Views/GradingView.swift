import SwiftUI
import SwiftData

struct GradingView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var bets: [Bet]
    @Query private var events: [Event]

    @State private var selectedBets: Set<UUID> = []
    @State private var isMultiSelectMode = false

    /// Bets ready to grade, sorted by creation date (oldest first for grading priority)
    private var readyToGradeBets: [Bet] {
        bets.filter { $0.status == .readyToGrade }
            .sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        NavigationStack {
            Group {
                if readyToGradeBets.isEmpty {
                    ContentUnavailableView(
                        "No Bets to Grade",
                        systemImage: "checkmark.circle",
                        description: Text("Bets ready for grading will appear here.")
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
        }
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
