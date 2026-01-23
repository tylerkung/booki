import SwiftUI
import SwiftData

/// Sheet for bulk grading all bets for a finalized event
struct GradeEventSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let event: Event
    let betsToGrade: [Bet]

    /// Override grades per bet (nil = use suggested)
    @State private var overrideGrades: [UUID: GradeResult] = [:]

    /// Confirmation dialog state
    @State private var showingConfirmation = false

    /// Success state
    @State private var showingSuccess = false
    @State private var gradeSummary: GradeSummary?

    /// Parsed final scores
    private var homeScore: Int? {
        guard let finalScore = event.finalScore else { return nil }
        let parts = finalScore.split(separator: "-")
        guard parts.count == 2 else { return nil }
        return Int(parts[0].trimmingCharacters(in: .whitespaces))
    }

    private var awayScore: Int? {
        guard let finalScore = event.finalScore else { return nil }
        let parts = finalScore.split(separator: "-")
        guard parts.count == 2 else { return nil }
        return Int(parts[1].trimmingCharacters(in: .whitespaces))
    }

    /// Bets grouped by market
    private var betsByMarket: [(String, [Bet])] {
        let grouped = Dictionary(grouping: betsToGrade, by: { $0.market })
        return grouped.sorted { $0.key < $1.key }
    }

    /// Get the effective grade for a bet (override or suggested)
    private func effectiveGrade(for bet: Bet) -> GradeResult? {
        if let override = overrideGrades[bet.id] {
            return override
        }
        return suggestedOutcome(for: bet)
    }

    /// Calculate suggested outcome for a bet based on final score
    private func suggestedOutcome(for bet: Bet) -> GradeResult? {
        guard let homeScore = homeScore, let awayScore = awayScore else {
            return nil
        }

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
            if let spreadValue = extractLine(from: bet.side) {
                let isHome = sideNormalized.lowercased().contains(event.homeTeam.lowercased())
                let adjustedDiff: Double

                if isHome {
                    adjustedDiff = Double(homeScore - awayScore) + spreadValue
                } else {
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
        let pattern = #"[+-]?\d+\.?\d*"#
        if let range = side.range(of: pattern, options: .regularExpression) {
            return Double(side[range])
        }
        return nil
    }

    /// Count of each grade type
    private var gradeCounts: (wins: Int, losses: Int, pushes: Int, ungraded: Int) {
        var wins = 0
        var losses = 0
        var pushes = 0
        var ungraded = 0

        for bet in betsToGrade {
            guard let grade = effectiveGrade(for: bet) else {
                ungraded += 1
                continue
            }
            switch grade {
            case .win: wins += 1
            case .loss: losses += 1
            case .push: pushes += 1
            }
        }

        return (wins, losses, pushes, ungraded)
    }

    /// Whether all bets have grades (suggested or override)
    private var allBetsHaveGrades: Bool {
        betsToGrade.allSatisfy { effectiveGrade(for: $0) != nil }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if showingSuccess, let summary = gradeSummary {
                    // Success view
                    successView(summary: summary)
                } else {
                    // Main grading view
                    gradingListView
                }
            }
            .background(Theme.background)
            .navigationTitle("Grade Event Bets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                if !showingSuccess {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Apply All") {
                            showingConfirmation = true
                        }
                        .disabled(!allBetsHaveGrades)
                    }
                }
            }
            .toolbarBackground(Theme.cardBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .alert("Confirm Grading", isPresented: $showingConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Apply All Grades") {
                    applyAllGrades()
                }
            } message: {
                let counts = gradeCounts
                Text("Grade \(betsToGrade.count) bets?\n\n• \(counts.wins) wins\n• \(counts.losses) losses\n• \(counts.pushes) pushes")
            }
        }
    }

    // MARK: - Main Grading List View

    private var gradingListView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Event summary card
                eventSummaryCard

                // Summary stats
                summaryStatsCard

                // Bets grouped by market
                ForEach(betsByMarket, id: \.0) { market, bets in
                    marketSection(market: market, bets: bets)
                }
            }
            .padding()
        }
    }

    // MARK: - Event Summary Card

    private var eventSummaryCard: some View {
        VStack(spacing: 12) {
            // Teams and score
            HStack {
                VStack(spacing: 4) {
                    Text(event.awayTeam)
                        .font(.headline)
                    if let awayScore = awayScore {
                        Text("\(awayScore)")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
                .frame(maxWidth: .infinity)

                Text("@")
                    .font(.title2)
                    .foregroundStyle(Theme.textMuted)

                VStack(spacing: 4) {
                    Text(event.homeTeam)
                        .font(.headline)
                    if let homeScore = homeScore {
                        Text("\(homeScore)")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
                .frame(maxWidth: .infinity)
            }

            // Sport and league
            HStack {
                Text(event.sport)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.accent)
                    .clipShape(Capsule())

                Text(event.league)
                    .font(.caption)
                    .foregroundStyle(Theme.textMuted)
            }

            // Final badge
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.accent)
                Text("FINAL")
                    .font(.caption)
                    .fontWeight(.bold)
                    .tracking(1)
            }
            .foregroundStyle(Theme.textMuted)
        }
        .padding()
        .background(Theme.cardBackground)
        .cornerRadius(16)
    }

    // MARK: - Summary Stats Card

    private var summaryStatsCard: some View {
        let counts = gradeCounts

        return VStack(spacing: 12) {
            Text("Grading Summary")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.textMuted)

            HStack(spacing: 16) {
                statBadge(value: counts.wins, label: "Wins", color: Theme.accent)
                statBadge(value: counts.losses, label: "Losses", color: Theme.danger)
                statBadge(value: counts.pushes, label: "Pushes", color: Theme.gold)
                if counts.ungraded > 0 {
                    statBadge(value: counts.ungraded, label: "Manual", color: Theme.textMuted)
                }
            }
        }
        .padding()
        .background(Theme.cardBackground)
        .cornerRadius(16)
    }

    private func statBadge(value: Int, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.textMuted)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Market Section

    private func marketSection(market: String, bets: [Bet]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Market header
            HStack {
                Text(market)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.textPrimary)

                Spacer()

                Text("\(bets.count) bet\(bets.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(Theme.textMuted)
            }

            // Bet rows
            ForEach(bets) { bet in
                BetGradeRow(
                    bet: bet,
                    suggestedGrade: suggestedOutcome(for: bet),
                    overrideGrade: overrideGrades[bet.id],
                    onOverrideChanged: { newGrade in
                        if newGrade == suggestedOutcome(for: bet) {
                            // If override matches suggested, remove override
                            overrideGrades.removeValue(forKey: bet.id)
                        } else {
                            overrideGrades[bet.id] = newGrade
                        }
                    }
                )
            }
        }
        .padding()
        .background(Theme.cardBackground)
        .cornerRadius(16)
    }

    // MARK: - Success View

    private func successView(summary: GradeSummary) -> some View {
        VStack(spacing: 24) {
            Spacer()

            // Checkmark animation
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.2))
                    .frame(width: 120, height: 120)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(Theme.accent)
            }

            Text("Grading Complete!")
                .font(.title2)
                .fontWeight(.bold)

            // Summary stats
            VStack(spacing: 16) {
                HStack(spacing: 24) {
                    VStack {
                        Text("\(summary.wins)")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.accent)
                        Text("Wins")
                            .font(.caption)
                            .foregroundStyle(Theme.textMuted)
                    }

                    VStack {
                        Text("\(summary.losses)")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.danger)
                        Text("Losses")
                            .font(.caption)
                            .foregroundStyle(Theme.textMuted)
                    }

                    VStack {
                        Text("\(summary.pushes)")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.gold)
                        Text("Pushes")
                            .font(.caption)
                            .foregroundStyle(Theme.textMuted)
                    }
                }
            }
            .padding()
            .background(Theme.cardBackground)
            .cornerRadius(16)

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Theme.accent)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
        }
        .padding()
    }

    // MARK: - Actions

    private func applyAllGrades() {
        var wins = 0
        var losses = 0
        var pushes = 0

        for bet in betsToGrade {
            guard let grade = effectiveGrade(for: bet) else { continue }

            // Directly update bet status and grade result
            // Note: GradingService.gradeBet expects .accepted, but we have .readyToGrade
            // So we set properties directly for bulk grading
            bet.status = .graded
            bet.gradeResult = grade

            switch grade {
            case .win: wins += 1
            case .loss: losses += 1
            case .push: pushes += 1
            }
        }

        gradeSummary = GradeSummary(wins: wins, losses: losses, pushes: pushes)

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            showingSuccess = true
        }
    }
}

// MARK: - Grade Summary

struct GradeSummary {
    let wins: Int
    let losses: Int
    let pushes: Int

    var total: Int { wins + losses + pushes }
}

// MARK: - Bet Grade Row

struct BetGradeRow: View {
    let bet: Bet
    let suggestedGrade: GradeResult?
    let overrideGrade: GradeResult?
    let onOverrideChanged: (GradeResult?) -> Void

    private var effectiveGrade: GradeResult? {
        overrideGrade ?? suggestedGrade
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Bet info row
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(bet.player?.name ?? "Unknown Player")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    HStack(spacing: 6) {
                        Text(bet.side)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)

                        Text(formattedOdds)
                            .font(.caption)
                            .foregroundStyle(Theme.textMuted)

                        Text("•")
                            .foregroundStyle(Theme.textMuted)

                        Text(formattedStake)
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                }

                Spacer()

                // Current grade indicator
                if let grade = effectiveGrade {
                    gradeIndicator(grade: grade, isOverride: overrideGrade != nil)
                } else {
                    Text("Manual")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.textMuted)
                        .clipShape(Capsule())
                }
            }

            // Grade selection buttons
            HStack(spacing: 8) {
                gradeButton(grade: .win, label: "Win", color: Theme.accent)
                gradeButton(grade: .loss, label: "Loss", color: Theme.danger)
                gradeButton(grade: .push, label: "Push", color: Theme.gold)
            }
        }
        .padding()
        .background(Theme.elevatedBackground)
        .cornerRadius(12)
    }

    private func gradeIndicator(grade: GradeResult, isOverride: Bool) -> some View {
        HStack(spacing: 4) {
            if isOverride {
                Image(systemName: "pencil.circle.fill")
                    .font(.caption2)
            }
            Text(grade.rawValue.capitalized)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(gradeColor(for: grade))
        .clipShape(Capsule())
    }

    private func gradeButton(grade: GradeResult, label: String, color: Color) -> some View {
        let isSelected = effectiveGrade == grade
        let isSuggested = suggestedGrade == grade && overrideGrade == nil

        return Button {
            if overrideGrade == grade {
                // Tapping current override removes it
                onOverrideChanged(nil)
            } else {
                onOverrideChanged(grade)
            }
        } label: {
            HStack(spacing: 4) {
                if isSuggested {
                    Image(systemName: "lightbulb.fill")
                        .font(.caption2)
                }
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isSelected ? color : color.opacity(0.15))
            .foregroundStyle(isSelected ? .white : color)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    private func gradeColor(for grade: GradeResult) -> Color {
        switch grade {
        case .win: return Theme.accent
        case .loss: return Theme.danger
        case .push: return Theme.gold
        }
    }
}

#Preview {
    GradeEventSheet(
        event: Event(
            sport: "NFL",
            league: "Football",
            homeTeam: "Patriots",
            awayTeam: "Jets",
            startTime: Date(),
            status: .final,
            finalScore: "24 - 17"
        ),
        betsToGrade: []
    )
}
