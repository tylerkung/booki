import SwiftUI
import SwiftData

/// US-002: View mode for GamesView (Upcoming vs Past)
enum GameViewMode: String, CaseIterable, Identifiable {
    case upcoming = "Upcoming"
    case past = "Past"

    var id: String { rawValue }
}

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
    /// US-008: Query acceptance policy for event lock offset
    @Query private var acceptancePolicies: [AcceptancePolicy]

    let player: Player

    /// US-008: Get lock offset from policy (default 0 if no policy)
    private var lockOffsetMinutes: Int {
        acceptancePolicies.first?.eventLockOffsetMinutes ?? 0
    }

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

    /// US-002: View mode selection (Upcoming vs Past)
    @State private var viewMode: GameViewMode = .upcoming

    /// Favorites manager (US-039)
    @ObservedObject private var favoritesManager = FavoritesManager.shared

    // MARK: - Computed Properties

    /// US-001: Cutoff date for showing recently finished events (48 hours ago)
    private var recentFinishedCutoff: Date {
        Calendar.current.date(byAdding: .hour, value: -48, to: Date()) ?? Date()
    }

    /// US-004: Bettable events - only shows events the player can actually bet on
    /// Filters to: status is scheduled, not locked, and start time is in the future
    private var bettableEvents: [Event] {
        let now = Date()
        return events.filter { event in
            // Only show scheduled events (not live, final, postponed, or canceled)
            guard event.status == .scheduled else { return false }
            // Only show events that haven't started yet
            guard event.startTime > now else { return false }
            // Only show events that aren't locked for betting
            guard !event.isLocked(offsetMinutes: lockOffsetMinutes) else { return false }
            return true
        }
    }

    /// US-001: Upcoming events - shows bettable events PLUS recently finished events for reference
    /// Events are sorted by startTime ascending (soonest first)
    private var upcomingEvents: [Event] {
        let bettable = bettableEvents
        let recentlyFinished = events.filter { event in
            // Include final events from the last 48 hours for bet result reference
            event.status == .final && event.startTime >= recentFinishedCutoff
        }
        // Combine and sort by start time ascending
        return (bettable + recentlyFinished).sorted { $0.startTime < $1.startTime }
    }

    /// US-002: Past events - final events older than 48 hours
    /// Events are sorted by startTime descending (most recent first)
    private var pastEvents: [Event] {
        events
            .filter { event in
                event.status == .final && event.startTime < recentFinishedCutoff
            }
            .sorted { $0.startTime > $1.startTime }
    }

    /// US-002: Available events based on view mode
    /// Returns upcomingEvents for .upcoming mode, pastEvents for .past mode
    private var availableEvents: [Event] {
        switch viewMode {
        case .upcoming:
            return upcomingEvents
        case .past:
            return pastEvents
        }
    }

    /// Unique sports that have available events, sorted alphabetically
    private var availableSports: [String] {
        let sports = Set(availableEvents.map { $0.sport })
        return sports.sorted()
    }

    /// Events filtered by time (US-038) and favorites (US-039)
    /// US-002: Time filters are bypassed in past mode (only search/sport filtering applies)
    private var timeFilteredEvents: [Event] {
        // US-002: Past mode bypasses time filters (they don't apply to historical data)
        if viewMode == .past {
            return availableEvents
        }

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

    /// Whether any filters are active (US-038, US-039, US-002)
    private var hasActiveFilters: Bool {
        // US-002: In past mode, time filters don't apply
        if viewMode == .past {
            return !searchText.isEmpty
        }
        return timeFilter != .all || !searchText.isEmpty
    }

    /// Whether showing favorites filter (US-039)
    private var isShowingFavorites: Bool {
        timeFilter == .favorites
    }

    /// Description of empty state based on filters (US-038, US-039, US-002)
    private var emptyStateDescription: String {
        // US-002: Handle past mode empty states
        if viewMode == .past {
            if !searchText.isEmpty {
                return "No past games match '\(searchText)'."
            } else if let sport = selectedSport {
                return "There are no past \(sport) games."
            }
            return "There are no past games to view."
        }

        // Upcoming mode empty states
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

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Search bar and filter (US-038)
            searchAndFilterHeader
                .background(Theme.background)

            // Sticky sport tabs header
            sportTabsHeader
                .background(Theme.background)

            // Games list
            if filteredEvents.isEmpty {
                emptyStateView
            } else {
                gamesList
            }

            // Floating bet slip indicator (US-037, US-040, US-053)
            // US-053: Animated appear/disappear transition
            if !betSlipManager.isEmpty {
                betSlipIndicator
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Theme.background)
        .navigationBarHidden(true)
        // US-010: Navigate to GameDetailView instead of MarketSelectionView
        .navigationDestination(for: Event.self) { event in
            GameDetailView(player: player, event: event)
        }
        .navigationDestination(item: $selectedEventForNavigation) { event in
            GameDetailView(player: player, event: event)
        }
        .sheet(isPresented: $showingFilterSheet) {
            TimeFilterSheet(selectedFilter: $timeFilter)
                .presentationDetents([.height(280)])
        }
        .sheet(isPresented: $showingBetSlipSheet) {
            BetSlipSheet(availableCredit: balanceSummary.availableCredit, player: player)
                .presentationDetents([.large])
        }
        // US-002: Reset time filter when switching to past mode (time filters don't apply)
        .onChange(of: viewMode) { _, newMode in
            if newMode == .past {
                timeFilter = .all
            }
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
                    .font(Theme.subheadline)
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

    // MARK: - Search and Filter Header (US-038, US-002)

    @ViewBuilder
    private var searchAndFilterHeader: some View {
        VStack(spacing: 12) {
            // US-002: View mode picker (Upcoming/Past)
            Picker("View Mode", selection: $viewMode) {
                ForEach(GameViewMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)

            // Search bar and filter row
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
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // Filter button - only show for upcoming mode (past mode doesn't need time filters)
                if viewMode == .upcoming {
                    Button(action: { showingFilterSheet = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .font(Theme.font(size: 16))
                            if timeFilter != .all {
                                Text(timeFilter.rawValue)
                                    .font(Theme.caption)
                                    .fontWeight(.medium)
                            }
                        }
                        .foregroundStyle(timeFilter != .all ? Theme.background : Theme.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(timeFilter != .all ? Theme.accent : Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
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
        .background(Theme.background)
        .overlay(
            Rectangle()
                .fill(Theme.divider)
                .frame(height: 0.5),
            alignment: .bottom
        )
    }

    // MARK: - Games List

    @ViewBuilder
    private var gamesList: some View {
        ScrollView {
            // US-006: Use LazyVStack with pinnedViews for sticky column headers
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                // Column headers section - sticks below sport tabs
                Section(header: columnHeadersRow) {
                    // US-008: Favorites section at top of All games (US-039)
                    if timeFilter == .all && selectedSport == nil && !favoriteEvents.isEmpty {
                        favoritesSection
                    }

                    // Events grouped by sport and league
                    ForEach(sortedSports, id: \.self) { sport in
                        sportSection(sport: sport)
                    }
                }
            }
        }
        .background(Theme.background)
    }

    // MARK: - Column Headers Row (US-006)

    /// Sticky column headers for SPREAD/MONEY/TOTAL columns
    @ViewBuilder
    private var columnHeadersRow: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                // Spacer for team name column
                Spacer()

                // Column headers aligned with odds buttons
                Text("SPREAD")
                    .font(Theme.font(size: 10, weight: .semibold))
                    .foregroundColor(Theme.textMuted)
                    .frame(width: 52)

                Text("MONEY")
                    .font(Theme.font(size: 10, weight: .semibold))
                    .foregroundColor(Theme.textMuted)
                    .frame(width: 52)

                Text("TOTAL")
                    .font(Theme.font(size: 10, weight: .semibold))
                    .foregroundColor(Theme.textMuted)
                    .frame(width: 52)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.background)

            // Bottom border
            Rectangle()
                .fill(Theme.divider)
                .frame(height: 0.5)
        }
    }

    // MARK: - Favorites Section (US-039, US-008)

    @ViewBuilder
    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header - styled similar to sport headers
            HStack {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .font(Theme.font(size: 10))
                Text("Favorites")
                    .fontWeight(.medium)
            }
            .font(Theme.font(size: 12, weight: .medium))
            .foregroundStyle(Theme.textSecondary)
            .padding(.top, 16)
            .padding(.bottom, 8)
            .padding(.horizontal, 12)

            // US-008: Favorite games using CompactGameRow
            ForEach(favoriteEvents, id: \.id) { event in
                CompactGameRow(
                    event: event,
                    selections: betSlipManager.selectionsSet,
                    onSelectOdds: { selection in
                        handleOddsSelection(selection, event: event)
                    },
                    onTapCard: {
                        selectedEventForNavigation = event
                    },
                    lockOffsetMinutes: lockOffsetMinutes
                )
            }
        }
    }

    // MARK: - Sport Section

    @ViewBuilder
    private func sportSection(sport: String) -> some View {
        let leaguesByEvent = eventsBySportAndLeague[sport] ?? [:]
        let sortedLeagues = leaguesByEvent.keys.sorted()

        ForEach(sortedLeagues, id: \.self) { league in
            VStack(alignment: .leading, spacing: 0) {
                // US-007: Section header - compact inline format
                HStack {
                    Text(sport)
                        .fontWeight(.medium)
                    Text("•")
                        .foregroundStyle(Theme.textSecondary)
                    Text(league)
                        .foregroundStyle(Theme.textSecondary)
                }
                .font(Theme.font(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 16)
                .padding(.bottom, 8)
                .padding(.horizontal, 12)

                // US-008: Game rows using CompactGameRow
                ForEach(leaguesByEvent[league] ?? [], id: \.id) { event in
                    CompactGameRow(
                        event: event,
                        selections: betSlipManager.selectionsSet,
                        onSelectOdds: { selection in
                            handleOddsSelection(selection, event: event)
                        },
                        onTapCard: {
                            selectedEventForNavigation = event
                        },
                        lockOffsetMinutes: lockOffsetMinutes
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
                        .font(Theme.subheadline)
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
/// US-053: Enhanced with smooth selection animation
struct SportTabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    /// US-053: Press state for scale animation
    @State private var isPressed: Bool = false

    var body: some View {
        Button(action: {
            // US-053: Animate tab selection
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                action()
            }
        }) {
            Text(title)
                .font(Theme.subheadline)
                .fontWeight(isSelected ? .semibold : .medium)
                .foregroundStyle(isSelected ? Theme.background : Theme.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Theme.accent : Theme.cardBackground)
                .clipShape(Capsule())
                // US-053: Scale animation on press
                .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        .buttonStyle(.plain)
        // US-053: Smooth background/selection animation
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isSelected)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.easeInOut(duration: 0.1)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.easeInOut(duration: 0.1)) {
                        isPressed = false
                    }
                }
        )
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
        case .postponed: return .orange
        case .canceled: return .red
        }
    }

    private var statusText: String {
        switch event.status {
        case .scheduled: return "Upcoming"
        case .live: return "Live"
        case .final: return "Final"
        case .postponed: return "Postponed"
        case .canceled: return "Canceled"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Teams matchup
            HStack {
                Text("\(event.awayTeam) @ \(event.homeTeam)")
                    .font(Theme.headline)

                Spacer()

                if event.status == .live {
                    Text(statusText)
                        .font(Theme.caption2)
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
                    .font(Theme.caption)

                Text(formattedStartTime)
                    .font(Theme.subheadline)
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
                                    .foregroundStyle(Theme.accent)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
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
