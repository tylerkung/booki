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

// MARK: - Market Selection View

/// View for selecting a market and side for bet submission
struct MarketSelectionView: View {
    let player: Player
    let event: Event

    /// Selected market and side for the bet
    @State private var selectedMarket: Market?
    @State private var selectedSide: SelectedSide?

    /// Which side is selected (A or B)
    enum SelectedSide: Hashable {
        case sideA
        case sideB
    }

    // MARK: - Computed Properties

    /// Markets for this event grouped by type
    private var marketsByType: [MarketType: [Market]] {
        guard let markets = event.markets else { return [:] }
        return Dictionary(grouping: markets, by: { $0.type })
    }

    /// Ordered market types for display
    private var orderedMarketTypes: [MarketType] {
        [.spread, .total, .moneyline].filter { marketsByType[$0] != nil }
    }

    /// Display name for market type
    private func marketTypeName(_ type: MarketType) -> String {
        switch type {
        case .spread: return "Spread"
        case .total: return "Total"
        case .moneyline: return "Moneyline"
        }
    }

    /// Check if a selection has been made
    private var hasSelection: Bool {
        selectedMarket != nil && selectedSide != nil
    }

    /// Get the selected side label for display
    private var selectedSideLabel: String? {
        guard let market = selectedMarket, let side = selectedSide else { return nil }
        switch side {
        case .sideA: return market.sideA
        case .sideB: return market.sideB
        }
    }

    /// Get the selected odds for display
    private var selectedOdds: Int? {
        guard let market = selectedMarket, let side = selectedSide else { return nil }
        switch side {
        case .sideA: return market.oddsA
        case .sideB: return market.oddsB
        }
    }

    // MARK: - Body

    var body: some View {
        List {
            // Event info section
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(event.awayTeam) @ \(event.homeTeam)")
                        .font(.headline)
                    HStack {
                        Text(event.sport)
                        Text("•")
                        Text(event.league)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            } header: {
                Text("Event")
            }

            // Markets section
            if event.markets?.isEmpty ?? true {
                ContentUnavailableView(
                    "No Markets Available",
                    systemImage: "exclamationmark.triangle",
                    description: Text("No betting markets are available for this event.")
                )
            } else {
                ForEach(orderedMarketTypes, id: \.self) { marketType in
                    marketTypeSection(type: marketType)
                }
            }

            // Selection summary (shown when something is selected)
            if hasSelection {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Your Selection")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(selectedSideLabel ?? "")
                                .font(.headline)
                        }
                        Spacer()
                        Text(formatOdds(selectedOdds ?? 0))
                            .font(.title2.bold())
                            .foregroundStyle(.blue)
                    }
                } header: {
                    Text("Selected")
                }
            }
        }
        .navigationTitle("Select Market")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if hasSelection {
                continueButton
            }
        }
        .navigationDestination(for: BetSelection.self) { selection in
            StakeEntryView(player: player, event: event, selection: selection)
        }
    }

    // MARK: - Section Views

    @ViewBuilder
    private func marketTypeSection(type: MarketType) -> some View {
        let markets = marketsByType[type] ?? []

        Section {
            ForEach(markets, id: \.id) { market in
                MarketRowView(
                    market: market,
                    selectedSide: selectedMarket?.id == market.id ? selectedSide : nil,
                    onSelectSideA: {
                        selectedMarket = market
                        selectedSide = .sideA
                    },
                    onSelectSideB: {
                        selectedMarket = market
                        selectedSide = .sideB
                    }
                )
            }
        } header: {
            Text(marketTypeName(type))
        }
    }

    // MARK: - Continue Button

    @ViewBuilder
    private var continueButton: some View {
        NavigationLink(value: BetSelection(
            market: selectedMarket!,
            side: selectedSide == .sideA ? selectedMarket!.sideA : selectedMarket!.sideB,
            odds: selectedSide == .sideA ? selectedMarket!.oddsA : selectedMarket!.oddsB
        )) {
            Text("Continue")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    // MARK: - Helpers

    private func formatOdds(_ odds: Int) -> String {
        odds >= 0 ? "+\(odds)" : "\(odds)"
    }
}

// MARK: - Market Row View

/// Row view for displaying a single market with tappable sides
struct MarketRowView: View {
    let market: Market
    let selectedSide: MarketSelectionView.SelectedSide?
    let onSelectSideA: () -> Void
    let onSelectSideB: () -> Void

    private func formatOdds(_ odds: Int) -> String {
        odds >= 0 ? "+\(odds)" : "\(odds)"
    }

    private var sideASelected: Bool {
        selectedSide == .sideA
    }

    private var sideBSelected: Bool {
        selectedSide == .sideB
    }

    var body: some View {
        HStack(spacing: 12) {
            // Side A button
            Button(action: onSelectSideA) {
                VStack(spacing: 4) {
                    Text(market.sideA)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    Text(formatOdds(market.oddsA))
                        .font(.headline.bold())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .padding(.horizontal, 8)
                .background(sideASelected ? Color.blue : Color(.systemGray5))
                .foregroundStyle(sideASelected ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            // Side B button
            Button(action: onSelectSideB) {
                VStack(spacing: 4) {
                    Text(market.sideB)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    Text(formatOdds(market.oddsB))
                        .font(.headline.bold())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .padding(.horizontal, 8)
                .background(sideBSelected ? Color.blue : Color(.systemGray5))
                .foregroundStyle(sideBSelected ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Bet Selection Model

/// Model to pass selected bet details to stake entry view
struct BetSelection: Hashable {
    let market: Market
    let side: String
    let odds: Int

    func hash(into hasher: inout Hasher) {
        hasher.combine(market.id)
        hasher.combine(side)
        hasher.combine(odds)
    }

    static func == (lhs: BetSelection, rhs: BetSelection) -> Bool {
        lhs.market.id == rhs.market.id && lhs.side == rhs.side && lhs.odds == rhs.odds
    }
}

// MARK: - Stake Entry View (Placeholder for US-025)

/// Placeholder view for stake entry (will be implemented in US-025)
struct StakeEntryView: View {
    let player: Player
    let event: Event
    let selection: BetSelection

    var body: some View {
        ContentUnavailableView(
            "Stake Entry",
            systemImage: "dollarsign.circle",
            description: Text("Stake entry will be available soon.")
        )
        .navigationTitle("Enter Stake")
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
