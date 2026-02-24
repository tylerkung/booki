import SwiftUI
import SwiftData

/// Dedicated sport page with league sub-tabs and filtered games
/// US-002: Sport hub destination page navigable from Search and Games tabs
struct SportPageView: View {
    let category: SportCategory
    var isViewOnly: Bool = false
    var player: Player? = nil

    @Query(sort: \Event.startTime) private var events: [Event]
    @Query private var acceptancePolicies: [AcceptancePolicy]

    /// Bet slip manager for persistent selections
    private var betSlipManager = BetSlipManager.shared

    /// Selected league tab ID (or "futures" for the futures placeholder)
    @State private var selectedLeagueId: String

    /// Event to navigate to for full market view
    @State private var selectedEventForNavigation: Event? = nil

    init(category: SportCategory, isViewOnly: Bool = false, player: Player? = nil) {
        self.category = category
        self.isViewOnly = isViewOnly
        self.player = player
        self._selectedLeagueId = State(initialValue: category.leagues.first?.id ?? "futures")
    }

    // MARK: - Computed Properties

    /// Lock offset from acceptance policy
    private var lockOffsetMinutes: Int {
        acceptancePolicies.first?.eventLockOffsetMinutes ?? 0
    }

    /// The currently selected league info (nil if Futures tab selected)
    private var selectedLeague: LeagueInfo? {
        category.leagues.first { $0.id == selectedLeagueId }
    }

    /// Events filtered for the selected league
    private var leagueEvents: [Event] {
        guard let league = selectedLeague else { return [] }
        let now = Date()
        return events.filter { event in
            guard league.matchesEvent(event) else { return false }
            if isViewOnly {
                // Bookie view: show all non-canceled events
                return event.status != .canceled
            } else {
                // Player view: only bettable events
                guard event.status == .scheduled else { return false }
                guard event.startTime > now else { return false }
                guard !event.isLocked(offsetMinutes: lockOffsetMinutes) else { return false }
                return true
            }
        }
        .sorted { $0.startTime < $1.startTime }
    }

    /// Events grouped by date for section headers
    private var eventsByDate: [(date: String, events: [Event])] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"

        var groups: [String: [Event]] = [:]
        var dateOrder: [String] = []

        for event in leagueEvents {
            let dateKey: String
            if calendar.isDateInToday(event.startTime) {
                dateKey = "Today"
            } else if calendar.isDateInTomorrow(event.startTime) {
                dateKey = "Tomorrow"
            } else {
                dateKey = formatter.string(from: event.startTime)
            }

            if groups[dateKey] == nil {
                dateOrder.append(dateKey)
            }
            groups[dateKey, default: []].append(event)
        }

        return dateOrder.map { (date: $0, events: groups[$0]!) }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // League sub-tabs
            leaguePicker

            // Content
            if selectedLeagueId == "futures" {
                futuresPlaceholder
            } else if leagueEvents.isEmpty {
                emptyLeagueState
            } else {
                leagueGamesList
            }
        }
        .background(Theme.background)
        .navigationTitle(category.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedEventForNavigation) { event in
            if let player = player {
                GameDetailView(player: player, event: event)
            }
        }
    }

    // MARK: - League Picker

    @ViewBuilder
    private var leaguePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(category.leagues) { league in
                    leagueTab(id: league.id, title: league.displayName)
                }
                leagueTab(id: "futures", title: "Futures")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Theme.background)
        .overlay(
            Rectangle()
                .fill(Theme.divider)
                .frame(height: 0.5),
            alignment: .bottom
        )
    }

    @ViewBuilder
    private func leagueTab(id: String, title: String) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedLeagueId = id
            }
        }) {
            Text(title)
                .font(Theme.subheadline)
                .fontWeight(selectedLeagueId == id ? .semibold : .medium)
                .foregroundStyle(selectedLeagueId == id ? Theme.background : Theme.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(selectedLeagueId == id ? Theme.accent : Theme.cardBackground)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: selectedLeagueId)
    }

    // MARK: - League Games List

    @ViewBuilder
    private var leagueGamesList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(eventsByDate, id: \.date) { group in
                    Section(header: dateStickyHeader(group.date)) {
                        ForEach(Array(group.events.enumerated()), id: \.element.id) { index, event in
                            CompactGameRow(
                                event: event,
                                selections: isViewOnly ? [] : betSlipManager.selectionsSet,
                                onSelectOdds: { selection in
                                    guard !isViewOnly else { return }
                                    handleOddsSelection(selection, event: event)
                                },
                                onTapCard: {
                                    if !isViewOnly {
                                        selectedEventForNavigation = event
                                    }
                                },
                                lockOffsetMinutes: lockOffsetMinutes,
                                isViewOnly: isViewOnly,
                                isAlternate: index.isMultiple(of: 2)
                            )
                        }
                    }
                }
            }
        }
        .background(Theme.background)
    }

    // MARK: - Date Sticky Header

    @ViewBuilder
    private func dateStickyHeader(_ dateString: String) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(dateString.uppercased())
                    .font(Theme.font(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .tracking(0.5)
                Spacer()

                // Column headers for odds
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

    // MARK: - Futures Placeholder (US-003)

    @ViewBuilder
    private var futuresPlaceholder: some View {
        Spacer()
        VStack(spacing: 16) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 48))
                .foregroundStyle(Theme.textMuted)

            Text("Futures Coming Soon")
                .font(Theme.headline)
                .foregroundStyle(Theme.textPrimary)

            Text("Season-long and tournament markets will appear here.")
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        Spacer()
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyLeagueState: some View {
        Spacer()
        VStack(spacing: 12) {
            Image(systemName: "sportscourt")
                .font(.system(size: 36))
                .foregroundStyle(Theme.textMuted)

            Text("No games available")
                .font(Theme.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
        Spacer()
    }

    // MARK: - Selection Handling

    private func handleOddsSelection(_ selection: BetSlipSelection, event: Event) {
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

    private func buildMarketDescription(selection: BetSlipSelection, event: Event) -> String {
        let market = event.markets?.first { $0.id == selection.marketId }
        guard let market = market else { return selection.side }

        switch market.type {
        case .spread, .alternateSpread:
            return "Spread"
        case .total, .alternateTotal, .teamTotal:
            return "Total"
        case .moneyline:
            return "Moneyline"
        }
    }

}
