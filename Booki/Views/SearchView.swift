import SwiftUI
import SwiftData

/// Full-screen search experience for finding games by team name
/// Positioned as the 2nd tab in the player tab bar
struct SearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Event.startTime) private var events: [Event]
    @Query private var bets: [Bet]
    @Query private var ledgerEntries: [LedgerEntry]
    @Query private var acceptancePolicies: [AcceptancePolicy]

    let player: Player

    init(player: Player) {
        self.player = player
    }

    // MARK: - State

    @State private var searchText: String = ""
    @FocusState private var isSearchFocused: Bool

    /// Bet slip manager for persistent selections
    private var betSlipManager = BetSlipManager.shared

    /// Show bet slip sheet
    @State private var showingBetSlipSheet: Bool = false

    /// Event to navigate to for full market view
    @State private var selectedEventForNavigation: Event? = nil

    // MARK: - Computed Properties

    private var lockOffsetMinutes: Int {
        acceptancePolicies.first?.eventLockOffsetMinutes ?? 0
    }

    private var upcomingHorizon: Date {
        Date().addingTimeInterval(14 * 24 * 3600)
    }

    /// Bettable events — same criteria as GamesView
    private var bettableEvents: [Event] {
        let now = Date()
        return events.filter { event in
            guard event.status == .scheduled else { return false }
            guard event.startTime > now else { return false }
            guard event.startTime <= upcomingHorizon else { return false }
            guard !event.isLocked(offsetMinutes: lockOffsetMinutes) else { return false }
            return true
        }.sorted { $0.startTime < $1.startTime }
    }

    /// Events filtered by search text — matches team names
    private var searchResults: [Event] {
        guard !searchText.isEmpty else { return [] }
        let lowercasedSearch = searchText.lowercased()
        return bettableEvents.filter {
            $0.homeTeam.lowercased().contains(lowercasedSearch) ||
            $0.awayTeam.lowercased().contains(lowercasedSearch)
        }
    }

    /// Search results grouped by sport and league
    private var resultsBySportAndLeague: [String: [String: [Event]]] {
        var result: [String: [String: [Event]]] = [:]
        for event in searchResults {
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

    private var sortedSports: [String] {
        resultsBySportAndLeague.keys.sorted()
    }

    /// Player balance summary for bet slip
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
            // Search bar
            searchBar

            // Content
            if searchText.isEmpty {
                emptyPromptView
            } else if searchResults.isEmpty {
                noResultsView
            } else {
                resultsList
            }

            // Floating bet slip indicator
            if !betSlipManager.isEmpty {
                betSlipIndicator
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: Event.self) { event in
            GameDetailView(player: player, event: event)
        }
        .navigationDestination(for: SportCategory.self) { category in
            SportPageView(category: category, player: player)
        }
        .navigationDestination(item: $selectedEventForNavigation) { event in
            GameDetailView(player: player, event: event)
        }
        .sheet(isPresented: $showingBetSlipSheet) {
            BetSlipSheet(availableCredit: balanceSummary.availableCredit, player: player)
                .presentationDetents([.large])
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
        .padding(.vertical, 12)
        .background(Theme.background)
        .overlay(
            Rectangle()
                .fill(Theme.divider)
                .frame(height: 0.5),
            alignment: .bottom
        )
    }

    // MARK: - Empty State (no query)

    @ViewBuilder
    private var emptyPromptView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // SPORTS section header
                Text("SPORTS")
                    .font(Theme.caption)
                    .tracking(1.0)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 12)

                // Sport rows
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

    // MARK: - No Results

    @ViewBuilder
    private var noResultsView: some View {
        VStack(spacing: 12) {
            Spacer()
            ContentUnavailableView(
                "No Results",
                systemImage: "magnifyingglass",
                description: Text("No games found for '\(searchText)'")
            )
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Results List

    @ViewBuilder
    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(sortedSports, id: \.self) { sport in
                    let leaguesByEvent = resultsBySportAndLeague[sport] ?? [:]
                    let sortedLeagues = leaguesByEvent.keys.sorted()

                    ForEach(sortedLeagues, id: \.self) { league in
                        Section(header: stickyHeader(sport: sport, league: league)) {
                            ForEach(Array((leaguesByEvent[league] ?? []).enumerated()), id: \.element.id) { index, event in
                                CompactGameRow(
                                    event: event,
                                    selections: betSlipManager.selectionsSet,
                                    onSelectOdds: { selection in
                                        handleOddsSelection(selection, event: event)
                                    },
                                    onTapCard: {
                                        selectedEventForNavigation = event
                                    },
                                    lockOffsetMinutes: lockOffsetMinutes,
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

    // MARK: - Sticky Header

    @ViewBuilder
    private func stickyHeader(sport: String, league: String) -> some View {
        let sportCategory = SportCategory.allCases.first { $0.displayName == sport }
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                if let category = sportCategory {
                    NavigationLink(value: category) {
                        HStack(spacing: 4) {
                            Text(sport)
                                .fontWeight(.medium)
                            Text("·")
                                .foregroundStyle(Theme.textMuted)
                            Text(league)
                                .foregroundStyle(Theme.textMuted)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.textMuted)
                        }
                    }
                    .buttonStyle(.plain)
                    .font(Theme.font(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                } else {
                    HStack(spacing: 4) {
                        Text(sport)
                            .fontWeight(.medium)
                        Text("·")
                            .foregroundStyle(Theme.textMuted)
                        Text(league)
                            .foregroundStyle(Theme.textMuted)
                    }
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

    // MARK: - Bet Slip Indicator

    @ViewBuilder
    private var betSlipIndicator: some View {
        Button(action: {
            showingBetSlipSheet = true
        }) {
            HStack {
                Image(systemName: "ticket.fill")
                    .foregroundStyle(Theme.background)

                Text("\(betSlipManager.count) Selection\(betSlipManager.count == 1 ? "" : "s")")
                    .font(Theme.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.background)

                Spacer()

                Image(systemName: "chevron.up")
                    .foregroundStyle(Theme.background.opacity(0.7))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Theme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: Theme.accent.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Selection Handling

    private func handleOddsSelection(_ selection: BetSlipSelection, event: Event) {
        let eventDescription = event.awayTeam == "Outright" ? event.homeTeam : "\(event.awayTeam) @ \(event.homeTeam)"
        let marketDescription = buildMarketDescription(selection: selection, event: event)

        withAnimation(.easeInOut(duration: 0.15)) {
            betSlipManager.toggle(
                selection,
                eventDescription: eventDescription,
                marketDescription: marketDescription
            )
        }
    }

    private func buildMarketDescription(selection: BetSlipSelection, event: Event) -> String {
        let market = event.markets?.first { $0.id == selection.marketId }
        guard let market = market else {
            return selection.side
        }

        switch market.type {
        case .spread, .alternateSpread:
            return "Spread"
        case .total, .alternateTotal, .teamTotal:
            return "Total"
        case .moneyline:
            return "Moneyline"
        case .outright:
            return "Outright"
        }
    }
}
