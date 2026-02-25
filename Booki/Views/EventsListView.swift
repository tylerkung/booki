import SwiftUI
import SwiftData

struct EventsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Event.startTime) private var events: [Event]

    @State private var showingAddEvent = false
    @State private var showingSyncGames = false
    @State private var showingImportEvents = false
    @State private var showingFetchScores = false
    @State private var showingRefreshOdds = false

    /// Upcoming vs Past toggle
    @State private var showPast = false

    /// Currently selected sport filter (nil = "All")
    @State private var selectedSport: String? = nil

    /// Event navigation target (for CompactGameRow tap)
    @State private var selectedEvent: Event? = nil

    /// Search text
    @State private var searchText: String = ""
    @FocusState private var isSearchFocused: Bool

    // MARK: - Filtering

    /// 48-hour cutoff for "recent finals" in Upcoming tab
    private var recentFinalsCutoff: Date {
        Date().addingTimeInterval(-48 * 3600)
    }

    /// 14-day horizon — hide events further out than this
    private var upcomingHorizon: Date {
        Date().addingTimeInterval(14 * 24 * 3600)
    }

    /// Upcoming: non-final/non-canceled + finals from last 48h, within 14-day horizon. Sorted startTime ascending.
    private var upcomingEvents: [Event] {
        events.filter { event in
            if event.status == .canceled { return false }
            if event.status == .final {
                return event.startTime >= recentFinalsCutoff
            }
            // Hide events more than 14 days out
            return event.startTime <= upcomingHorizon
        }
        .sorted { $0.startTime < $1.startTime }
    }

    /// Past: finals older than 48h. Sorted startTime descending (newest first).
    private var pastEvents: [Event] {
        events.filter { event in
            event.status == .final && event.startTime < recentFinalsCutoff
        }
        .sorted { $0.startTime > $1.startTime }
    }

    /// Base events for current tab
    private var baseEvents: [Event] {
        showPast ? pastEvents : upcomingEvents
    }

    /// Filtered by search text
    private var searchFilteredEvents: [Event] {
        guard !searchText.isEmpty else { return baseEvents }
        let lowered = searchText.lowercased()
        return baseEvents.filter {
            $0.homeTeam.lowercased().contains(lowered) ||
            $0.awayTeam.lowercased().contains(lowered)
        }
    }

    /// Filtered by selected sport
    private var filteredEvents: [Event] {
        if let sport = selectedSport {
            return searchFilteredEvents.filter { $0.sport == sport }
        }
        return searchFilteredEvents
    }

    /// Unique sports from base events (for tab display)
    private var availableSports: [String] {
        Set(baseEvents.map { $0.sport }).sorted()
    }

    /// Events grouped by sport → league
    private var eventsBySportAndLeague: [String: [String: [Event]]] {
        var result: [String: [String: [Event]]] = [:]
        for event in filteredEvents {
            result[event.sport, default: [:]][event.league, default: []].append(event)
        }
        return result
    }

    /// Sorted sports for display
    private var sortedSports: [String] {
        eventsBySportAndLeague.keys.sorted()
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Persistent search bar
                searchBar

                // Upcoming / Past picker
                segmentedPicker

                // Sport tabs
                sportTabsHeader

                // Content: sport categories when idle, or game rows, or empty state
                if searchText.isEmpty && selectedSport == nil && !showPast {
                    sportCategoriesView
                } else if filteredEvents.isEmpty {
                    emptyStateView
                } else {
                    gamesList
                }
            }
            .background(Theme.background)
            .navigationTitle("Events")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $selectedEvent) { event in
                EventDetailView(event: event)
            }
            .navigationDestination(for: SportCategory.self) { category in
                SportPageView(category: category, isViewOnly: true)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Image("BookiWordmark")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 20)
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showingSyncGames = true
                        } label: {
                            Label("Sync Games", systemImage: "arrow.triangle.2.circlepath")
                        }

                        Divider()

                        Button {
                            showingAddEvent = true
                        } label: {
                            Label("Add Event Manually", systemImage: "plus")
                        }

                        Menu {
                            Button {
                                showingImportEvents = true
                            } label: {
                                Label("Import from Odds API", systemImage: "square.and.arrow.down")
                            }

                            Button {
                                showingFetchScores = true
                            } label: {
                                Label("Fetch Scores", systemImage: "sportscourt")
                            }

                            Button {
                                showingRefreshOdds = true
                            } label: {
                                Label("Refresh Odds", systemImage: "arrow.clockwise")
                            }
                        } label: {
                            Label("Advanced", systemImage: "ellipsis.circle")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddEvent) {
                AddEventSheet()
            }
            .sheet(isPresented: $showingSyncGames) {
                SyncGamesView()
            }
            .sheet(isPresented: $showingImportEvents) {
                ImportEventsView()
            }
            .sheet(isPresented: $showingFetchScores) {
                FetchScoresView()
            }
            .sheet(isPresented: $showingRefreshOdds) {
                RefreshOddsView()
            }
        }
    }

    // MARK: - Segmented Picker

    @ViewBuilder
    private var segmentedPicker: some View {
        Picker("", selection: $showPast) {
            Text("Upcoming").tag(false)
            Text("Past").tag(true)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .onChange(of: showPast) {
            // Reset sport filter when switching tabs
            selectedSport = nil
            searchText = ""
        }
    }

    // MARK: - Search Bar

    @ViewBuilder
    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundStyle(Theme.textSecondary)

            TextField("Search teams...", text: $searchText)
                .textFieldStyle(.plain)
                .font(Theme.body)
                .autocorrectionDisabled()
                .focused($isSearchFocused)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.background)
    }

    // MARK: - Sport Tabs Header

    @ViewBuilder
    private var sportTabsHeader: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // "All" tab
                SportTabButton(
                    title: "All",
                    iconName: "sportscourt",
                    isSelected: selectedSport == nil,
                    action: { selectedSport = nil }
                )

                // Sport-specific tabs
                ForEach(availableSports, id: \.self) { sport in
                    SportTabButton(
                        title: sport,
                        iconName: SportCategory.iconName(for: sport),
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
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(sortedSports, id: \.self) { sport in
                    let leaguesByEvent = eventsBySportAndLeague[sport] ?? [:]
                    let sortedLeagues = leaguesByEvent.keys.sorted()

                    let sportCategory = SportCategory.allCases.first { $0.displayName == sport }

                    ForEach(sortedLeagues, id: \.self) { league in
                        Section(header: stickyHeader(leftContent: {
                            HStack(spacing: 4) {
                                Text(sport)
                                    .fontWeight(.medium)
                                Text("·")
                                    .foregroundStyle(Theme.textMuted)
                                Text(league)
                                    .foregroundStyle(Theme.textMuted)
                            }
                        }, trailingNavigation: sportCategory)) {
                            ForEach(Array((leaguesByEvent[league] ?? []).enumerated()), id: \.element.id) { index, event in
                                CompactGameRow(
                                    event: event,
                                    selections: [],
                                    onSelectOdds: { _ in },
                                    onTapCard: {
                                        selectedEvent = event
                                    },
                                    isViewOnly: true,
                                    isAlternate: index.isMultiple(of: 2)
                                )
                            }
                            Color.clear.frame(height: 16)
                        }
                    }
                }
            }
        }
        .background(Theme.background)
    }

    // MARK: - Sport Categories (idle state)

    @ViewBuilder
    private var sportCategoriesView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("SPORTS")
                    .font(Theme.caption)
                    .tracking(1.0)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 12)

                VStack(spacing: 8) {
                    ForEach(SportCategory.allCases) { category in
                        NavigationLink(value: category) {
                            HStack(spacing: 12) {
                                Image(systemName: category.iconName)
                                    .font(.system(size: 18))
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 28)

                                Text(category.displayName)
                                    .font(Theme.body)
                                    .foregroundStyle(Theme.textPrimary)

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.textMuted)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(Theme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .background(Theme.background)
    }

    // MARK: - Sticky Section Header

    @ViewBuilder
    private func stickyHeader<Left: View>(@ViewBuilder leftContent: () -> Left, trailingNavigation: SportCategory? = nil) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                if let category = trailingNavigation {
                    NavigationLink(value: category) {
                        HStack(spacing: 4) {
                            leftContent()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.textMuted)
                        }
                    }
                    .buttonStyle(.plain)
                    .font(Theme.font(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                } else {
                    leftContent()
                        .font(Theme.font(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer()

                Text("SPREAD")
                    .font(Theme.font(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
                    .frame(width: 65)

                Text("MONEY")
                    .font(Theme.font(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
                    .frame(width: 65)

                Text("TOTAL")
                    .font(Theme.font(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
                    .frame(width: 65)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.background)

            Rectangle()
                .fill(Theme.divider)
                .frame(height: 0.5)
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()

            ContentUnavailableView(
                !searchText.isEmpty ? "No Results" : (showPast ? "No Past Events" : "No Events"),
                systemImage: !searchText.isEmpty ? "magnifyingglass" : "sportscourt",
                description: Text(emptyStateDescription)
            )

            if !searchText.isEmpty {
                Button("Clear Search") {
                    searchText = ""
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Theme.background)
    }

    private var emptyStateDescription: String {
        if !searchText.isEmpty {
            return "No events match '\(searchText)'."
        } else if let sport = selectedSport {
            return showPast
                ? "No past \(sport) events."
                : "No upcoming \(sport) events."
        } else if showPast {
            return "No completed events yet."
        }
        return "Add events to start managing your book."
    }
}

#Preview {
    EventsListView()
        .modelContainer(for: [Event.self, Market.self, Bet.self], inMemory: true)
}
