import SwiftUI
import SwiftData

/// Filter options for bets list
enum BetFilter: String, CaseIterable {
    case pending = "Pending"
    case open = "Open"
    case readyToGrade = "Ready to Grade"
    case settled = "Settled"
    case all = "All"

    /// Returns the bet statuses that match this filter
    var matchingStatuses: [BetStatus] {
        switch self {
        case .pending:
            return [.pending]
        case .open:
            return [.accepted]
        case .readyToGrade:
            return [.readyToGrade]
        case .settled:
            return [.settled, .graded, .declined, .void]
        case .all:
            return BetStatus.allCases
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

    @State private var selectedFilter: BetFilter = .all

    /// Filtered bets based on selected filter
    private var filteredBets: [Bet] {
        bets.filter { selectedFilter.matchingStatuses.contains($0.status) }
            .sorted { $0.createdAt > $1.createdAt }
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
                .padding()

                // MARK: - Bets List
                List {
                    if filteredBets.isEmpty {
                        ContentUnavailableView(
                            "No Bets",
                            systemImage: "list.bullet.rectangle",
                            description: Text("No bets match the selected filter.")
                        )
                    } else {
                        ForEach(filteredBets) { bet in
                            NavigationLink(value: bet) {
                                BetRowView(
                                    bet: bet,
                                    eventName: eventName(for: bet)
                                )
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Bets")
            .navigationDestination(for: Bet.self) { bet in
                BetDetailView(bet: bet)
            }
        }
    }

    // MARK: - Helper Methods

    private func eventName(for bet: Bet) -> String {
        if let event = events.first(where: { $0.id.uuidString == bet.eventId }) {
            return "\(event.awayTeam) @ \(event.homeTeam)"
        }
        return "Event \(bet.eventId.prefix(8))"
    }
}

// MARK: - Bet Row View

struct BetRowView: View {
    let bet: Bet
    let eventName: String

    private var formattedOdds: String {
        if bet.odds > 0 {
            return "+\(bet.odds)"
        } else {
            return "\(bet.odds)"
        }
    }

    private var formattedStake: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: bet.stake as NSDecimalNumber) ?? "$\(bet.stake)"
    }

    private var statusColor: Color {
        switch bet.status {
        case .pending:
            return .orange
        case .accepted:
            return .blue
        case .declined:
            return .red
        case .readyToGrade:
            return .purple
        case .graded:
            return .indigo
        case .settled:
            return .green
        case .void:
            return .gray
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top row: Player name and status badge
            HStack {
                Text(bet.player?.name ?? "Unknown Player")
                    .font(.headline)

                Spacer()

                Text(bet.status.rawValue.capitalized)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor)
                    .clipShape(Capsule())
            }

            // Second row: Event name
            Text(eventName)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Third row: Market and side
            HStack {
                Text(bet.market)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("•")
                    .foregroundStyle(.secondary)

                Text(bet.side)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            // Bottom row: Odds and stake
            HStack {
                Text(formattedOdds)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(formattedStake)
                    .font(.subheadline.bold())
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Bet Detail View (Placeholder)

struct BetDetailView: View {
    let bet: Bet

    var body: some View {
        Text("Bet Detail: \(bet.id.uuidString)")
            .navigationTitle("Bet Details")
    }
}

#Preview {
    BetsListView()
        .modelContainer(for: [Bet.self, Event.self], inMemory: true)
}
