import SwiftUI
import SwiftData

struct EventDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allBets: [Bet]

    let event: Event

    // MARK: - Computed Properties

    /// All bets for this event
    private var eventBets: [Bet] {
        allBets.filter { $0.eventId == event.id.uuidString }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Active bets (pending + accepted) for exposure calculation
    private var activeBets: [Bet] {
        eventBets.filter { $0.status == .pending || $0.status == .accepted }
    }

    /// Event exposure breakdown
    private var eventExposure: EventExposure? {
        guard !activeBets.isEmpty else { return nil }
        return ExposureService.calculateEventExposure(eventId: event.id.uuidString, bets: activeBets)
    }

    /// Formatted start time
    private var formattedStartTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: event.startTime)
    }

    /// Event display name
    private var displayName: String {
        "\(event.awayTeam) @ \(event.homeTeam)"
    }

    // MARK: - Body

    var body: some View {
        List {
            // MARK: - Event Info Section
            Section("Event Info") {
                LabeledContent("Matchup", value: displayName)
                LabeledContent("Sport", value: event.sport)
                LabeledContent("League", value: event.league)
                LabeledContent("Start Time", value: formattedStartTime)

                HStack {
                    Text("Status")
                    Spacer()
                    Text(event.status.rawValue.capitalized)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(statusColor)
                        .clipShape(Capsule())
                }

                if let finalScore = event.finalScore {
                    LabeledContent("Final Score", value: finalScore)
                        .fontWeight(.semibold)
                }
            }

            // MARK: - Exposure Breakdown Section
            Section("Exposure Breakdown") {
                if let exposure = eventExposure {
                    ForEach(exposure.sides.sorted(by: { $0.totalExposure > $1.totalExposure }), id: \.side) { sideExposure in
                        ExposureSideRow(sideExposure: sideExposure)
                    }

                    // Total max exposure
                    HStack {
                        Text("Max Exposure")
                            .fontWeight(.semibold)
                        Spacer()
                        Text(formatCurrency(exposure.maxExposure))
                            .font(.headline)
                            .foregroundStyle(.red)
                    }
                    .padding(.top, 4)
                } else {
                    Text("No active exposure")
                        .foregroundStyle(.secondary)
                }
            }

            // MARK: - Bets for Event Section
            Section {
                if eventBets.isEmpty {
                    Text("No bets for this event")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(eventBets) { bet in
                        EventBetRow(bet: bet)
                    }
                }
            } header: {
                HStack {
                    Text("Bets")
                    Spacer()
                    Text("\(eventBets.count) total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // MARK: - Liability by Side Section
            if !activeBets.isEmpty {
                Section("Liability by Side") {
                    let betsBySide = Dictionary(grouping: activeBets, by: { $0.side })
                    ForEach(betsBySide.keys.sorted(), id: \.self) { side in
                        if let sideBets = betsBySide[side] {
                            LiabilitySideRow(side: side, bets: sideBets)
                        }
                    }
                }
            }
        }
        .navigationTitle("Event Details")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Helpers

    private var statusColor: Color {
        switch event.status {
        case .scheduled:
            return .blue
        case .live:
            return .green
        case .final:
            return .gray
        }
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }
}

// MARK: - Exposure Side Row

struct ExposureSideRow: View {
    let sideExposure: SideExposure

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(sideExposure.side)
                    .font(.headline)
                Spacer()
                Text(formatCurrency(sideExposure.totalExposure))
                    .font(.subheadline.bold())
                    .foregroundStyle(.red)
            }

            HStack(spacing: 16) {
                // Soft exposure (pending)
                HStack(spacing: 4) {
                    Circle()
                        .fill(.orange)
                        .frame(width: 8, height: 8)
                    Text("Pending: \(formatCurrency(sideExposure.softExposure))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Hard exposure (accepted)
                HStack(spacing: 4) {
                    Circle()
                        .fill(.blue)
                        .frame(width: 8, height: 8)
                    Text("Accepted: \(formatCurrency(sideExposure.hardExposure))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Event Bet Row

struct EventBetRow: View {
    let bet: Bet

    private var formattedOdds: String {
        bet.odds > 0 ? "+\(bet.odds)" : "\(bet.odds)"
    }

    private var formattedStake: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: bet.stake as NSDecimalNumber) ?? "$\(bet.stake)"
    }

    private var statusColor: Color {
        switch bet.status {
        case .pending: return .orange
        case .accepted: return .blue
        case .declined: return .red
        case .readyToGrade: return .purple
        case .graded: return .indigo
        case .settled: return .green
        case .void: return .gray
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Top row: Player name and status
            HStack {
                Text(bet.player?.name ?? "Unknown Player")
                    .font(.subheadline.bold())

                Spacer()

                Text(bet.status.rawValue.capitalized)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(statusColor)
                    .clipShape(Capsule())
            }

            // Middle row: Side and odds
            HStack {
                Text(bet.side)
                    .font(.subheadline)

                Text(formattedOdds)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(formattedStake)
                    .font(.subheadline.bold())
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Liability Side Row

struct LiabilitySideRow: View {
    let side: String
    let bets: [Bet]

    private var totalLiability: Decimal {
        LiabilityService.calculateTotalLiability(for: bets)
    }

    private var pendingCount: Int {
        bets.filter { $0.status == .pending }.count
    }

    private var acceptedCount: Int {
        bets.filter { $0.status == .accepted }.count
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(side)
                    .font(.headline)

                Text("\(bets.count) bets (\(pendingCount) pending, \(acceptedCount) accepted)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(formatCurrency(totalLiability))
                .font(.subheadline.bold())
                .foregroundStyle(.red)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        EventDetailView(
            event: Event(
                sport: "NFL",
                league: "Football",
                homeTeam: "Patriots",
                awayTeam: "Jets",
                startTime: Date(),
                status: .scheduled
            )
        )
    }
    .modelContainer(for: [Bet.self, Event.self], inMemory: true)
}
