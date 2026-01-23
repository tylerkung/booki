import SwiftUI
import SwiftData

/// Time filter options for games (US-038)
enum TimeFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case today = "Today"
    case tomorrow = "Tomorrow"
    case thisWeek = "This Week"
    case favorites = "Favorites"

    var id: String { rawValue }
}

/// Redesigned player view for browsing games organized by sport with easy navigation
/// US-036: Horizontal scrolling sport tabs with sticky header
/// US-037: Game cards with quick-pick odds and bet slip integration
/// US-038: Search and filter functionality
/// US-039: Favorites system with filter and section
struct GamesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Event.startTime) private var events: [Event]
    @Query private var bets: [Bet]
    @Query private var ledgerEntries: [LedgerEntry]

    let player: Player

    /// Currently selected sport filter (nil = "All")
    @State private var selectedSport: String? = nil

    /// Bet slip manager for persistent selections (US-040)
    @ObservedObject private var betSlipManager = BetSlipManager.shared

    /// Show bet slip sheet (US-040)
    @State private var showingBetSlipSheet: Bool = false

    /// Event to navigate to for full market view
    @State private var selectedEventForNavigation: Event? = nil

    /// Search text for filtering by team name (US-038)
    @State private var searchText: String = ""

    /// Time filter option (US-038, US-039)
    @State private var timeFilter: TimeFilter = .all

    /// Show filter options sheet (US-038)
    @State private var showingFilterSheet: Bool = false

    /// Favorites manager (US-039)
    @ObservedObject private var favoritesManager = FavoritesManager.shared

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

    /// Events filtered by time (US-038) and favorites (US-039)
    private var timeFilteredEvents: [Event] {
        let calendar = Calendar.current
        let now = Date()

        switch timeFilter {
        case .all:
            return availableEvents
        case .today:
            return availableEvents.filter { calendar.isDateInToday($0.startTime) }
        case .tomorrow:
            return availableEvents.filter { calendar.isDateInTomorrow($0.startTime) }
        case .thisWeek:
            guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: now) else {
                return availableEvents
            }
            return availableEvents.filter { $0.startTime >= now && $0.startTime <= weekEnd }
        case .favorites:
            return availableEvents.filter {
                favoritesManager.hasFavoritedTeam(homeTeam: $0.homeTeam, awayTeam: $0.awayTeam)
            }
        }
    }

    /// Events with favorited teams (US-039) - for "All" view favorites section
    private var favoriteEvents: [Event] {
        guard !favoritesManager.favoriteTeams.isEmpty else { return [] }
        return availableEvents.filter {
            favoritesManager.hasFavoritedTeam(homeTeam: $0.homeTeam, awayTeam: $0.awayTeam)
        }
    }

    /// Events filtered by search text (US-038) - matches team names
    private var searchFilteredEvents: [Event] {
        guard !searchText.isEmpty else {
            return timeFilteredEvents
        }
        let lowercasedSearch = searchText.lowercased()
        return timeFilteredEvents.filter {
            $0.homeTeam.lowercased().contains(lowercasedSearch) ||
            $0.awayTeam.lowercased().contains(lowercasedSearch)
        }
    }

    /// Events filtered by selected sport (combines all filters)
    private var filteredEvents: [Event] {
        if let sport = selectedSport {
            return searchFilteredEvents.filter { $0.sport == sport }
        }
        return searchFilteredEvents
    }

    /// Whether any filters are active (US-038, US-039)
    private var hasActiveFilters: Bool {
        timeFilter != .all || !searchText.isEmpty
    }

    /// Whether showing favorites filter (US-039)
    private var isShowingFavorites: Bool {
        timeFilter == .favorites
    }

    /// Description of empty state based on filters (US-038, US-039)
    private var emptyStateDescription: String {
        if timeFilter == .favorites && favoritesManager.favoriteTeams.isEmpty {
            return "Star your favorite teams to see them here."
        } else if timeFilter == .favorites {
            return "No games with your favorite teams right now."
        } else if !searchText.isEmpty && timeFilter != .all {
            return "No games match '\(searchText)' for \(timeFilter.rawValue.lowercased())."
        } else if !searchText.isEmpty {
            return "No games match '\(searchText)'."
        } else if timeFilter != .all {
            return "No games available for \(timeFilter.rawValue.lowercased())."
        } else if let sport = selectedSport {
            return "There are no upcoming \(sport) games."
        }
        return "There are no upcoming games to bet on."
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
            // Search bar and filter (US-038)
            searchAndFilterHeader
                .background(Color(.systemBackground))

            // Sticky sport tabs header
            sportTabsHeader
                .background(Color(.systemBackground))

            // Games list
            if filteredEvents.isEmpty {
                emptyStateView
            } else {
                gamesList
            }

            // Floating bet slip indicator (US-037, US-040)
            if !betSlipManager.isEmpty {
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
        .sheet(isPresented: $showingFilterSheet) {
            TimeFilterSheet(selectedFilter: $timeFilter)
                .presentationDetents([.height(280)])
        }
        .sheet(isPresented: $showingBetSlipSheet) {
            BetSlipSheet(availableCredit: balanceSummary.availableCredit, player: player)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Bet Slip Indicator (US-040)

    @ViewBuilder
    private var betSlipIndicator: some View {
        Button(action: {
            showingBetSlipSheet = true
        }) {
            HStack {
                Image(systemName: "ticket.fill")
                    .foregroundStyle(.white)

                Text("\(betSlipManager.count) Selection\(betSlipManager.count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)

                Spacer()

                Image(systemName: "chevron.up")
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.blue)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Search and Filter Header (US-038)

    @ViewBuilder
    private var searchAndFilterHeader: some View {
        HStack(spacing: 12) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search teams...", text: $searchText)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGray5))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Filter button
            Button(action: { showingFilterSheet = true }) {
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 16))
                    if timeFilter != .all {
                        Text(timeFilter.rawValue)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
                .foregroundStyle(timeFilter != .all ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(timeFilter != .all ? Color.blue : Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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

                // Favorites section at top of All games (US-039)
                if timeFilter == .all && selectedSport == nil && !favoriteEvents.isEmpty {
                    favoritesSection
                }

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

    // MARK: - Favorites Section (US-039)

    @ViewBuilder
    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                Text("Favorites")
                    .fontWeight(.semibold)
            }
            .font(.subheadline)

            // Favorite game cards
            ForEach(favoriteEvents, id: \.id) { event in
                GameCardView(
                    event: event,
                    selections: betSlipManager.selectionsSet,
                    onSelectOdds: { selection in
                        handleOddsSelection(selection, event: event)
                    },
                    onTapCard: {
                        selectedEventForNavigation = event
                    }
                )
            }
        }
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
                        selections: betSlipManager.selectionsSet,
                        onSelectOdds: { selection in
                            handleOddsSelection(selection, event: event)
                        },
                        onTapCard: {
                            selectedEventForNavigation = event
                        }
                    )
                }
            }
        }
    }

    // MARK: - Selection Handling (US-040)

    /// Handle odds button tap - toggle selection in bet slip using manager
    private func handleOddsSelection(_ selection: BetSlipSelection, event: Event) {
        // Build descriptions for the bet slip item
        let eventDescription = "\(event.awayTeam) @ \(event.homeTeam)"
        let marketDescription = buildMarketDescription(selection: selection, event: event)

        withAnimation(.easeInOut(duration: 0.15)) {
            betSlipManager.toggle(
                selection,
                eventDescription: eventDescription,
                marketDescription: marketDescription
            )
        }
    }

    /// Build market description string for bet slip display
    private func buildMarketDescription(selection: BetSlipSelection, event: Event) -> String {
        let market = event.markets?.first { $0.id == selection.marketId }
        guard let market = market else {
            return selection.side
        }

        switch market.type {
        case .spread:
            return "Spread"
        case .total:
            return "Total"
        case .moneyline:
            return "Moneyline"
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            ContentUnavailableView(
                hasActiveFilters ? "No Results" : "No Games Available",
                systemImage: hasActiveFilters ? "magnifyingglass" : "sportscourt",
                description: Text(emptyStateDescription)
            )

            // Clear filters button if filters are active (US-038)
            if hasActiveFilters {
                Button(action: clearFilters) {
                    Text("Clear Filters")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxHeight: .infinity)
    }

    /// Clear all search and time filters (US-038)
    private func clearFilters() {
        searchText = ""
        timeFilter = .all
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

// MARK: - Time Filter Sheet (US-038)

/// Sheet for selecting time filter options
struct TimeFilterSheet: View {
    @Binding var selectedFilter: TimeFilter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(TimeFilter.allCases) { filter in
                    Button(action: {
                        selectedFilter = filter
                        dismiss()
                    }) {
                        HStack {
                            Text(filter.rawValue)
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedFilter == filter {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Filter by Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
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
