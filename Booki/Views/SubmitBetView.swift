import SwiftUI
import SwiftData

/// View for players to browse available events and submit bet requests
/// Uses compliant language: "Submit Request" instead of "Place Bet"
struct SubmitBetView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Event.startTime) private var events: [Event]
    @Query private var bets: [Bet]
    @Query private var ledgerEntries: [LedgerEntry]

    let player: Player

    // MARK: - Computed Properties

    /// Available events (scheduled or live, not final)
    private var availableEvents: [Event] {
        events.filter { $0.status != .final }
    }

    /// Events grouped by sport, then by league
    private var eventsBySport: [String: [String: [Event]]] {
        var result: [String: [String: [Event]]] = [:]

        for event in availableEvents {
            if result[event.sport] == nil {
                result[event.sport] = [:]
            }
            if result[event.sport]?[event.league] == nil {
                result[event.sport]?[event.league] = []
            }
            result[event.sport]?[event.league]?.append(event)
        }

        return result
    }

    /// Sorted sports for consistent display order
    private var sortedSports: [String] {
        eventsBySport.keys.sorted()
    }

    /// Player balance summary for display
    private var balanceSummary: PlayerBalanceSummary {
        let playerBets = bets.filter { $0.player?.id == player.id }
        let playerLedgerEntries = ledgerEntries.filter { $0.player?.id == player.id }
        return BalanceService.playerSummary(
            for: player,
            bets: playerBets,
            ledgerEntries: playerLedgerEntries
        )
    }

    /// Color for available credit (computed to avoid HierarchicalShapeStyle type mismatch)
    private var availableCreditColor: Color {
        balanceSummary.availableCredit >= 0 ? Color.primary : Color.red
    }

    // MARK: - Body

    var body: some View {
        List {
            // Player info section
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Available Credit")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(formatCurrency(balanceSummary.availableCredit))
                            .font(.title2.bold())
                            .foregroundStyle(availableCreditColor)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Credit Limit")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(formatCurrency(player.creditLimit))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Your Account")
            }

            // Events grouped by sport and league
            if availableEvents.isEmpty {
                ContentUnavailableView(
                    "No Available Events",
                    systemImage: "sportscourt",
                    description: Text("There are no upcoming events to submit requests for.")
                )
            } else {
                ForEach(sortedSports, id: \.self) { sport in
                    sportSection(sport: sport)
                }
            }
        }
        .navigationTitle("Submit Request")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Event.self) { event in
            MarketSelectionView(player: player, event: event)
        }
    }

    // MARK: - Section Views

    @ViewBuilder
    private func sportSection(sport: String) -> some View {
        let leaguesByEvent = eventsBySport[sport] ?? [:]
        let sortedLeagues = leaguesByEvent.keys.sorted()

        ForEach(sortedLeagues, id: \.self) { league in
            Section {
                ForEach(leaguesByEvent[league] ?? [], id: \.id) { event in
                    NavigationLink(value: event) {
                        EventRowView(event: event)
                    }
                }
            } header: {
                HStack {
                    Text(sport)
                        .fontWeight(.semibold)
                    Text("•")
                    Text(league)
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
}

// MARK: - Event Row View

struct EventRowView: View {
    let event: Event

    private var formattedStartTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: event.startTime)
    }

    private var statusColor: Color {
        switch event.status {
        case .scheduled: return .blue
        case .live: return .green
        case .final: return .gray
        }
    }

    private var statusText: String {
        switch event.status {
        case .scheduled: return "Upcoming"
        case .live: return "Live"
        case .final: return "Final"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Teams matchup
            HStack {
                Text("\(event.awayTeam) @ \(event.homeTeam)")
                    .font(.headline)

                Spacer()

                if event.status == .live {
                    Text(statusText)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(statusColor)
                        .clipShape(Capsule())
                }
            }

            // Start time
            HStack {
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
                    .font(.caption)

                Text(formattedStartTime)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Market Selection View (Placeholder for US-024)

/// Placeholder view for market selection (will be implemented in US-024)
struct MarketSelectionView: View {
    let player: Player
    let event: Event

    var body: some View {
        ContentUnavailableView(
            "Market Selection",
            systemImage: "list.bullet.rectangle",
            description: Text("Market selection will be available soon.")
        )
        .navigationTitle("Select Market")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        SubmitBetView(player: Player(
            name: "Test Player",
            email: "test@example.com",
            creditLimit: 1000
        ))
    }
    .modelContainer(for: [Player.self, Event.self, Bet.self, LedgerEntry.self], inMemory: true)
}
