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
    @Query private var bets: [Bet]
    @Query private var ledgerEntries: [LedgerEntry]

    /// Bet slip manager for persistent selections
    private var betSlipManager = BetSlipManager.shared

    /// Selected league tab ID (or "futures" for the futures placeholder)
    @State private var selectedLeagueId: String

    /// Show bet slip sheet
    @State private var showingBetSlipSheet: Bool = false

    /// Event to navigate to for full market view
    @State private var selectedEventForNavigation: Event? = nil

    /// Futures sections that have been expanded to show all outcomes
    @State private var expandedFuturesSections: Set<String> = []

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

    /// Player balance summary for bet slip
    private var balanceSummary: PlayerBalanceSummary {
        guard let player = player else {
            return PlayerBalanceSummary(creditLimit: 0, openStakes: 0, openLiability: 0, balanceOwed: 0, availableCredit: 0)
        }
        let playerBets = bets.filter { $0.player?.id == player.id }
        let playerLedgerEntries = ledgerEntries.filter { $0.player?.id == player.id }
        return BalanceService.playerSummary(
            for: player,
            bets: playerBets,
            ledgerEntries: playerLedgerEntries
        )
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
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"

        var groups: [String: [Event]] = [:]
        var dateOrder: [String] = []

        for event in leagueEvents {
            let dateKey = formatter.string(from: event.startTime)

            if groups[dateKey] == nil {
                dateOrder.append(dateKey)
            }
            groups[dateKey, default: []].append(event)
        }

        return dateOrder.map { (date: $0, events: groups[$0]!) }
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // League sub-tabs
                leaguePicker

                // Content
                if selectedLeagueId == "futures" {
                    futuresContent
                } else if leagueEvents.isEmpty {
                    emptyLeagueState
                } else {
                    leagueGamesList
                }
            }

            // Floating bet slip indicator (player mode only)
            if !isViewOnly && !betSlipManager.isEmpty {
                betSlipIndicator
                    .transition(.move(edge: .bottom).combined(with: .opacity))
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
        .sheet(isPresented: $showingBetSlipSheet) {
            if let player = player {
                BetSlipSheet(availableCredit: balanceSummary.availableCredit, player: player)
                    .presentationDetents([.large])
            }
        }
    }

    // MARK: - League Picker

    @ViewBuilder
    private var leaguePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 24) {
                ForEach(category.leagues) { league in
                    leagueTab(id: league.id, title: league.displayName)
                }
                leagueTab(id: "futures", title: "Futures")
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 14)
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
        let isSelected = selectedLeagueId == id
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                selectedLeagueId = id
            }
        }) {
            VStack(spacing: 10) {
                Text(title.uppercased())
                    .font(Theme.font(size: 13, weight: isSelected ? .bold : .medium))
                    .tracking(1.2)
                    .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textMuted)

                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isSelected ? Theme.accent : Color.clear)
                    .frame(height: 3)
            }
        }
        .buttonStyle(.plain)
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
            HStack(spacing: 4) {
                Text(dateString.uppercased())
                    .font(Theme.font(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .tracking(0.5)
                Spacer()

                // Column headers for odds — spacing matches CompactGameRow HStack(spacing: 4)
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

    // MARK: - Futures View

    /// Events that are outright/futures for this sport category
    private var futuresEvents: [Event] {
        events.filter { event in
            event.awayTeam == "Outright" && category.displayName == event.sport
        }
    }

    /// Outright markets grouped by event (tournament name)
    private var futuresGrouped: [(eventName: String, event: Event, markets: [Market])] {
        futuresEvents.compactMap { event in
            let outrightMarkets = (event.markets ?? []).filter { $0.type == .outright }
            guard !outrightMarkets.isEmpty else { return nil }
            let name = event.homeTeam // e.g., "NBA Championship Winner"
            return (eventName: name, event: event, markets: outrightMarkets.sorted { $0.oddsA < $1.oddsA })
        }
    }

    @ViewBuilder
    private var futuresContent: some View {
        if futuresGrouped.isEmpty {
            futuresEmptyState
        } else {
            futuresList
        }
    }

    @ViewBuilder
    private var futuresEmptyState: some View {
        Spacer()
        VStack(spacing: 16) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 48))
                .foregroundStyle(Theme.textMuted)

            Text("No Futures Available")
                .font(Theme.headline)
                .foregroundStyle(Theme.textPrimary)

            Text("Championship and tournament futures will appear here once synced.")
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        Spacer()
    }

    private let futuresPreviewLimit = 8

    @ViewBuilder
    private var futuresList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(futuresGrouped, id: \.eventName) { group in
                    let isExpanded = expandedFuturesSections.contains(group.eventName)
                    let visibleMarkets = isExpanded ? group.markets : Array(group.markets.prefix(futuresPreviewLimit))

                    Section(header: futuresSectionHeader(group.eventName)) {
                        ForEach(Array(visibleMarkets.enumerated()), id: \.element.id) { index, market in
                            futuresRow(market: market, event: group.event, isAlternate: index.isMultiple(of: 2))
                        }

                        if group.markets.count > futuresPreviewLimit {
                            futuresShowMoreButton(
                                eventName: group.eventName,
                                isExpanded: isExpanded,
                                remainingCount: group.markets.count - futuresPreviewLimit
                            )
                        }
                    }
                }
            }
        }
        .background(Theme.background)
    }

    @ViewBuilder
    private func futuresShowMoreButton(eventName: String, isExpanded: Bool, remainingCount: Int) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.25)) {
                if isExpanded {
                    expandedFuturesSections.remove(eventName)
                } else {
                    expandedFuturesSections.insert(eventName)
                }
            }
        }) {
            HStack(spacing: 6) {
                Text(isExpanded ? "Show Less" : "Show More (\(remainingCount))")
                    .font(Theme.font(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Theme.accent.opacity(0.06))
        }
        .buttonStyle(.plain)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private func futuresSectionHeader(_ title: String) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title.uppercased())
                    .font(Theme.font(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.background)

            Rectangle()
                .fill(Theme.divider)
                .frame(height: 0.5)
        }
    }

    @ViewBuilder
    private func futuresRow(market: Market, event: Event, isAlternate: Bool) -> some View {
        let isSelected = betSlipManager.selectionsSet.contains(
            BetSlipSelection(
                eventId: event.id,
                marketId: market.id,
                side: market.sideA,
                odds: market.oddsA,
                marketType: .outright,
                sideIndicator: "a"
            )
        )

        Button(action: {
            guard !isViewOnly else { return }
            let selection = BetSlipSelection(
                eventId: event.id,
                marketId: market.id,
                side: market.sideA,
                odds: market.oddsA,
                marketType: .outright,
                sideIndicator: "a"
            )
            let eventDescription = event.homeTeam // e.g. "NBA Championship Winner"
            let marketDescription = "Outright"
            withAnimation(.easeInOut(duration: 0.15)) {
                betSlipManager.toggle(
                    selection,
                    eventDescription: eventDescription,
                    marketDescription: marketDescription
                )
            }
        }) {
            HStack(spacing: 12) {
                Text(market.sideA)
                    .font(Theme.font(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                Spacer()

                Text(formatFuturesOdds(market.oddsA))
                    .font(Theme.font(size: 13, weight: .bold))
                    .foregroundStyle(isSelected ? Theme.background : Theme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isSelected ? Theme.accent : Theme.accent.opacity(0.12))
                    )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isAlternate ? Theme.cardBackground.opacity(0.5) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    private func formatFuturesOdds(_ odds: Int) -> String {
        odds >= 0 ? "+\(odds)" : "\(odds)"
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
        guard let market = market else { return selection.side }

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
