import SwiftUI
import SwiftData

/// Redesigned player view for browsing games organized by sport with easy navigation
/// US-036: Horizontal scrolling sport tabs with sticky header
/// US-037: Game cards with quick-pick odds and bet slip integration
struct GamesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Event.startTime) private var events: [Event]
    @Query private var bets: [Bet]
    @Query private var ledgerEntries: [LedgerEntry]

    let player: Player

    /// Currently selected sport filter (nil = "All")
    @State private var selectedSport: String? = nil

    /// Selected odds for bet slip (US-037)
    @State private var betSlipSelections: Set<BetSlipSelection> = []

    /// Event to navigate to for full market view
    @State private var selectedEventForNavigation: Event? = nil

    // MARK: - Computed Properties

    /// Available events (scheduled or live, not final)
    private var availableEvents: [Event] {
        events.filter { $0.status != .final }
    }

    /// Unique sports that have available events, sorted alphabetically
    private var availableSports: [String] {
        let sports = Set(availableEvents.map { $0.sport })
        return sports.sorted()
    }

    /// Events filtered by selected sport
    private var filteredEvents: [Event] {
        if let sport = selectedSport {
            return availableEvents.filter { $0.sport == sport }
        }
        return availableEvents
    }

    /// Events grouped by sport and league for display
    private var eventsBySportAndLeague: [String: [String: [Event]]] {
        var result: [String: [String: [Event]]] = [:]

        for event in filteredEvents {
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
        eventsBySportAndLeague.keys.sorted()
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

    /// Color for available credit
    private var availableCreditColor: Color {
        balanceSummary.availableCredit >= 0 ? Color.primary : Color.red
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Sticky sport tabs header
            sportTabsHeader
                .background(Color(.systemBackground))

            // Games list
            if filteredEvents.isEmpty {
                emptyStateView
            } else {
                gamesList
            }

            // Floating bet slip indicator (US-037)
            if !betSlipSelections.isEmpty {
                betSlipIndicator
            }
        }
        .navigationTitle("Games")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Event.self) { event in
            MarketSelectionView(player: player, event: event)
        }
        .navigationDestination(item: $selectedEventForNavigation) { event in
            MarketSelectionView(player: player, event: event)
        }
    }

    // MARK: - Bet Slip Indicator

    @ViewBuilder
    private var betSlipIndicator: some View {
        HStack {
            Image(systemName: "ticket.fill")
                .foregroundStyle(.white)

            Text("\(betSlipSelections.count) Selection\(betSlipSelections.count == 1 ? "" : "s")")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)

            Spacer()

            Button(action: {
                withAnimation {
                    betSlipSelections.removeAll()
                }
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.blue)
    }

    // MARK: - Sport Tabs Header

    @ViewBuilder
    private var sportTabsHeader: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // "All" tab
                SportTabButton(
                    title: "All",
                    isSelected: selectedSport == nil,
                    action: { selectedSport = nil }
                )

                // Sport-specific tabs (only sports with events)
                ForEach(availableSports, id: \.self) { sport in
                    SportTabButton(
                        title: sport,
                        isSelected: selectedSport == sport,
                        action: { selectedSport = sport }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemBackground))
        .overlay(
            Divider(),
            alignment: .bottom
        )
    }

    // MARK: - Games List

    @ViewBuilder
    private var gamesList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                // Player account info section
                accountInfoCard

                // Events grouped by sport and league
                ForEach(sortedSports, id: \.self) { sport in
                    sportSection(sport: sport)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Account Info Card

    @ViewBuilder
    private var accountInfoCard: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Your Account")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
            }

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
            .padding(12)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Sport Section

    @ViewBuilder
    private func sportSection(sport: String) -> some View {
        let leaguesByEvent = eventsBySportAndLeague[sport] ?? [:]
        let sortedLeagues = leaguesByEvent.keys.sorted()

        ForEach(sortedLeagues, id: \.self) { league in
            VStack(alignment: .leading, spacing: 12) {
                // Section header
                HStack {
                    Text(sport)
                        .fontWeight(.semibold)
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text(league)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)

                // Game cards
                ForEach(leaguesByEvent[league] ?? [], id: \.id) { event in
                    GameCardView(
                        event: event,
                        selections: betSlipSelections,
                        onSelectOdds: { selection in
                            handleOddsSelection(selection)
                        },
                        onTapCard: {
                            selectedEventForNavigation = event
                        }
                    )
                }
            }
        }
    }

    // MARK: - Selection Handling

    /// Handle odds button tap - toggle selection in bet slip
    private func handleOddsSelection(_ selection: BetSlipSelection) {
        withAnimation(.easeInOut(duration: 0.15)) {
            if betSlipSelections.contains(selection) {
                betSlipSelections.remove(selection)
            } else {
                betSlipSelections.insert(selection)
            }
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyStateView: some View {
        ContentUnavailableView(
            "No Games Available",
            systemImage: "sportscourt",
            description: Text(selectedSport != nil
                ? "There are no upcoming \(selectedSport!) games."
                : "There are no upcoming games to bet on.")
        )
        .frame(maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }
}

// MARK: - Sport Tab Button

/// Button for sport filter tabs with selected state styling
struct SportTabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .medium)
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.blue : Color(.systemGray5))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Game Row View

/// Row view for displaying a game in the games list
struct GameRowView: View {
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

#Preview {
    NavigationStack {
        GamesView(player: Player(
            name: "Test Player",
            email: "test@example.com",
            creditLimit: 1000
        ))
    }
    .modelContainer(for: [Player.self, Event.self, Bet.self, LedgerEntry.self], inMemory: true)
}
