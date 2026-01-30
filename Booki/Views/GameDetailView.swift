import SwiftUI
import SwiftData

/// US-012: Market category for filtering
enum MarketCategory: String, CaseIterable, Identifiable {
    case allMarkets = "All Markets"
    case alternateLines = "Alternate Lines"
    case playerProps = "Player Props"
    case gameProps = "Game Props"

    var id: String { rawValue }
}

/// US-010: Game Detail View
/// US-011: Main Markets Section
/// US-012: Market Categories
/// Displays comprehensive game info with all available betting markets
/// Replaces MarketSelectionView for players with a more compact, sports-app style layout
struct GameDetailView: View {
    let player: Player
    let event: Event

    /// Bet slip manager for persistent selections
    @ObservedObject private var betSlipManager = BetSlipManager.shared

    /// Show bet slip sheet
    @State private var showingBetSlipSheet: Bool = false

    /// US-012: Selected market category
    @State private var selectedCategory: MarketCategory = .allMarkets

    /// Query bets and ledger for balance calculation
    @Query private var bets: [Bet]
    @Query private var ledgerEntries: [LedgerEntry]

    // MARK: - Computed Properties

    /// Formatted start time for display
    private var formattedStartTime: String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(event.startTime) {
            formatter.dateFormat = "h:mm a"
            return "Today \(formatter.string(from: event.startTime))"
        } else if Calendar.current.isDateInTomorrow(event.startTime) {
            formatter.dateFormat = "h:mm a"
            return "Tomorrow \(formatter.string(from: event.startTime))"
        } else {
            formatter.dateFormat = "E, MMM d • h:mm a"
            return formatter.string(from: event.startTime)
        }
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

    /// Get spread market if available
    private var spreadMarket: Market? {
        event.markets?.first { $0.type == .spread }
    }

    /// Get moneyline market if available
    private var moneylineMarket: Market? {
        event.markets?.first { $0.type == .moneyline }
    }

    /// Get total market if available
    private var totalMarket: Market? {
        event.markets?.first { $0.type == .total }
    }

    /// Check if event is locked for betting
    private var isEventLocked: Bool {
        event.isLocked(offsetMinutes: 0)
    }

    /// US-012: Check if category has any markets
    private func hasMarketsForCategory(_ category: MarketCategory) -> Bool {
        guard let markets = event.markets else { return false }

        switch category {
        case .allMarkets:
            return !markets.isEmpty
        case .alternateLines:
            // Future: filter for alternate spread/total markets
            // Currently no alternate lines support in model
            return false
        case .playerProps:
            // Future: filter for player prop markets
            // Currently no player props support in model
            return false
        case .gameProps:
            // Future: filter for game prop markets
            // Currently no game props support in model
            return false
        }
    }

    /// US-013: Get markets for the selected category
    private var marketsForSelectedCategory: [Market] {
        guard let markets = event.markets else { return [] }

        switch selectedCategory {
        case .allMarkets:
            return markets
        case .alternateLines:
            // Future: filter for alternate spread/total markets
            return []
        case .playerProps:
            // Future: filter for player prop markets
            return []
        case .gameProps:
            // Future: filter for game prop markets
            return []
        }
    }

    /// US-013: Group markets by type for display
    private var spreadMarkets: [Market] {
        marketsForSelectedCategory.filter { $0.type == .spread }
    }

    private var moneylineMarkets: [Market] {
        marketsForSelectedCategory.filter { $0.type == .moneyline }
    }

    private var totalMarkets: [Market] {
        marketsForSelectedCategory.filter { $0.type == .total }
    }

    /// US-012: Description for empty state based on category
    private var emptyStateDescription: String {
        switch selectedCategory {
        case .allMarkets:
            return "No markets available for this game."
        case .alternateLines:
            return "No alternate lines available for this game."
        case .playerProps:
            return "No player props available for this game."
        case .gameProps:
            return "No game props available for this game."
        }
    }

    /// Check if a specific selection is in the bet slip
    private func isSelected(_ selection: BetSlipSelection) -> Bool {
        betSlipManager.contains(selection)
    }

    /// Create a selection for a given market and side
    private func makeSelection(market: Market, side: String, odds: Int, sideIndicator: String) -> BetSlipSelection {
        BetSlipSelection(
            eventId: event.id,
            marketId: market.id,
            side: side,
            odds: odds,
            marketType: market.type,
            sideIndicator: sideIndicator
        )
    }

    /// Handle odds button tap
    private func handleOddsSelection(_ selection: BetSlipSelection, marketDescription: String) {
        let eventDescription = "\(event.awayTeam) vs \(event.homeTeam)"
        betSlipManager.toggle(selection, eventDescription: eventDescription, marketDescription: marketDescription)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Game header
            gameHeader

            // Markets content
            ScrollView {
                LazyVStack(spacing: 16) {
                    // US-011: Main Lines section (always visible at top)
                    mainLinesSection

                    // US-012: Category tabs
                    marketCategoryTabs

                    // US-012/US-013: Filtered market content or empty state
                    if hasMarketsForCategory(selectedCategory) {
                        // US-013: Market list grouped by type
                        marketListSection
                    } else {
                        // US-012: Empty state for category
                        marketCategoryEmptyState
                    }
                }
                .padding(.top, 16)
            }
            .background(Theme.background)

            // US-014: Floating bet slip indicator
            if !betSlipManager.isEmpty {
                betSlipIndicator
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingBetSlipSheet) {
            BetSlipSheet(availableCredit: balanceSummary.availableCredit, player: player)
                .presentationDetents([.large])
        }
    }

    // MARK: - Game Header

    @ViewBuilder
    private var gameHeader: some View {
        VStack(spacing: 12) {
            // Time and status row
            HStack {
                Text(formattedStartTime)
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)

                Spacer()

                // Live indicator
                if event.status == .live {
                    Text("LIVE")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Theme.live)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Theme.live.opacity(0.15))
                        )
                }

                // Postponed indicator
                if event.status == .postponed {
                    Text("PPD")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Theme.warning)
                }

                // Canceled indicator
                if event.status == .canceled {
                    Text("CANCELED")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Theme.danger)
                }
            }

            // Matchup - Away vs Home
            HStack {
                Text(event.awayTeam)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(Theme.textPrimary)

                Text("vs")
                    .font(.subheadline)
                    .foregroundColor(Theme.textSecondary)
                    .padding(.horizontal, 8)

                Text(event.homeTeam)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(Theme.textPrimary)
            }

            // Sport and league
            HStack {
                Text(event.sport)
                Text("•")
                    .foregroundColor(Theme.textSecondary)
                Text(event.league)
                    .foregroundColor(Theme.textSecondary)
            }
            .font(.caption)
            .foregroundColor(Theme.textSecondary)
        }
        .padding(16)
        .background(Theme.cardBackground)
    }

    // MARK: - Main Lines Section (US-011)

    /// Fixed button dimensions for consistent layout
    private let oddsButtonWidth: CGFloat = 80
    private let oddsButtonHeight: CGFloat = 44

    @ViewBuilder
    private var mainLinesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            Text("Main Lines")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
                .padding(.horizontal, 16)

            // Market rows
            VStack(spacing: 8) {
                // Spread market - show team name with spread (e.g., "OKC -6.5")
                if let spread = spreadMarket {
                    mainMarketRow(
                        market: spread,
                        label: "Spread",
                        sideALabel: spread.sideA,
                        sideBLabel: spread.sideB
                    )
                }

                // Moneyline market
                if let ml = moneylineMarket {
                    mainMarketRow(
                        market: ml,
                        label: "Moneyline",
                        sideALabel: event.awayTeam,
                        sideBLabel: event.homeTeam
                    )
                }

                // Total market
                if let total = totalMarket {
                    mainMarketRow(
                        market: total,
                        label: "Total",
                        sideALabel: formatTotalLabel(total.sideA),
                        sideBLabel: formatTotalLabel(total.sideB)
                    )
                }
            }
            .padding(.horizontal, 16)
        }
    }

    /// Single market row with both sides
    /// US-005: showOddsAsSecondary=true for spread/total to de-emphasize payout odds
    @ViewBuilder
    private func mainMarketRow(
        market: Market,
        label: String,
        sideALabel: String,
        sideBLabel: String
    ) -> some View {
        // US-005: Spread and Total show line value prominently, odds as secondary
        // Moneyline shows odds prominently (the odds ARE the key value)
        let useSecondaryOdds = market.type == .spread || market.type == .total

        VStack(spacing: 4) {
            // Market type label
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                Spacer()
            }

            // Both sides
            HStack(spacing: 8) {
                // Side A (away team / over)
                let selectionA = makeSelection(market: market, side: market.sideA, odds: market.oddsA, sideIndicator: "a")
                let descriptionA = "\(label): \(sideALabel)"

                CompactOddsButton(
                    topText: sideALabel,
                    odds: market.oddsA,
                    isSelected: isSelected(selectionA),
                    isDisabled: isEventLocked,
                    showOddsAsSecondary: useSecondaryOdds,
                    action: { handleOddsSelection(selectionA, marketDescription: descriptionA) }
                )
                .frame(maxWidth: .infinity)
                .frame(height: oddsButtonHeight)

                // Side B (home team / under)
                let selectionB = makeSelection(market: market, side: market.sideB, odds: market.oddsB, sideIndicator: "b")
                let descriptionB = "\(label): \(sideBLabel)"

                CompactOddsButton(
                    topText: sideBLabel,
                    odds: market.oddsB,
                    isSelected: isSelected(selectionB),
                    isDisabled: isEventLocked,
                    showOddsAsSecondary: useSecondaryOdds,
                    action: { handleOddsSelection(selectionB, marketDescription: descriptionB) }
                )
                .frame(maxWidth: .infinity)
                .frame(height: oddsButtonHeight)
            }
        }
        .padding(12)
        .background(Theme.cardBackground)
        .cornerRadius(8)
    }

    // MARK: - Market Category Tabs (US-012)

    @ViewBuilder
    private var marketCategoryTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(MarketCategory.allCases) { category in
                    MarketCategoryTabButton(
                        title: category.rawValue,
                        isSelected: selectedCategory == category,
                        action: { selectedCategory = category }
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

    // MARK: - Market List Section (US-013)

    @ViewBuilder
    private var marketListSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Spread markets section - show team name with spread (e.g., "OKC -6.5")
            if !spreadMarkets.isEmpty {
                marketTypeSection(
                    title: "Spread",
                    markets: spreadMarkets,
                    formatSideA: { $0 },  // Pass through full team + spread
                    formatSideB: { $0 }   // Pass through full team + spread
                )
            }

            // Moneyline markets section
            if !moneylineMarkets.isEmpty {
                marketTypeSection(
                    title: "Moneyline",
                    markets: moneylineMarkets,
                    formatSideA: { _ in event.awayTeam },
                    formatSideB: { _ in event.homeTeam }
                )
            }

            // Total markets section
            if !totalMarkets.isEmpty {
                marketTypeSection(
                    title: "Total",
                    markets: totalMarkets,
                    formatSideA: formatTotalLabel,
                    formatSideB: formatTotalLabel
                )
            }
        }
        .padding(.horizontal, 16)
    }

    /// US-013: Section for a specific market type
    @ViewBuilder
    private func marketTypeSection(
        title: String,
        markets: [Market],
        formatSideA: @escaping (String) -> String,
        formatSideB: @escaping (String) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.textSecondary)
                .textCase(.uppercase)

            // Market rows
            VStack(spacing: 0) {
                ForEach(Array(markets.enumerated()), id: \.element.id) { index, market in
                    marketRow(
                        market: market,
                        marketTypeLabel: title,
                        sideALabel: formatSideA(market.sideA),
                        sideBLabel: formatSideB(market.sideB),
                        showAlternatePrefix: markets.count > 1 && index > 0
                    )

                    // Divider between rows (not after last)
                    if index < markets.count - 1 {
                        Rectangle()
                            .fill(Theme.divider)
                            .frame(height: 0.5)
                    }
                }
            }
            .background(Theme.cardBackground)
            .cornerRadius(8)
        }
    }

    /// US-013: Single market row with both sides
    /// US-005: showOddsAsSecondary=true for spread/total to de-emphasize payout odds
    @ViewBuilder
    private func marketRow(
        market: Market,
        marketTypeLabel: String,
        sideALabel: String,
        sideBLabel: String,
        showAlternatePrefix: Bool
    ) -> some View {
        // US-005: Spread and Total show line value prominently, odds as secondary
        // Moneyline shows odds prominently (the odds ARE the key value)
        let useSecondaryOdds = market.type == .spread || market.type == .total

        VStack(spacing: 4) {
            // Market label (for alternate lines, show "Alt Spread -5.5" style)
            if showAlternatePrefix {
                HStack {
                    Text("Alt \(marketTypeLabel) \(extractLineValue(from: market))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.textMuted)
                    Spacer()
                }
            }

            // Both sides
            HStack(spacing: 8) {
                // Side A (away team / over)
                let selectionA = makeSelection(market: market, side: market.sideA, odds: market.oddsA, sideIndicator: "a")
                let descriptionA = "\(marketTypeLabel): \(sideALabel)"

                CompactOddsButton(
                    topText: sideALabel,
                    odds: market.oddsA,
                    isSelected: isSelected(selectionA),
                    isDisabled: isEventLocked,
                    showOddsAsSecondary: useSecondaryOdds,
                    action: { handleOddsSelection(selectionA, marketDescription: descriptionA) }
                )
                .frame(maxWidth: .infinity)
                .frame(height: oddsButtonHeight)

                // Side B (home team / under)
                let selectionB = makeSelection(market: market, side: market.sideB, odds: market.oddsB, sideIndicator: "b")
                let descriptionB = "\(marketTypeLabel): \(sideBLabel)"

                CompactOddsButton(
                    topText: sideBLabel,
                    odds: market.oddsB,
                    isSelected: isSelected(selectionB),
                    isDisabled: isEventLocked,
                    showOddsAsSecondary: useSecondaryOdds,
                    action: { handleOddsSelection(selectionB, marketDescription: descriptionB) }
                )
                .frame(maxWidth: .infinity)
                .frame(height: oddsButtonHeight)
            }
        }
        .padding(12)
    }

    /// US-013: Extract line value from market for alternate line display
    /// For spread: extracts the spread value (e.g., "-3.5" from "Lakers -3.5")
    /// For total: extracts the total value (e.g., "220.5" from "Over 220.5")
    private func extractLineValue(from market: Market) -> String {
        switch market.type {
        case .spread:
            // Extract spread value from sideB (home team line)
            let components = market.sideB.components(separatedBy: " ")
            if let last = components.last, (last.hasPrefix("+") || last.hasPrefix("-")) {
                return last
            }
            return ""
        case .total:
            // Extract total value from sideA
            let components = market.sideA.components(separatedBy: " ")
            if components.count >= 2 {
                return components[1]
            }
            return ""
        case .moneyline:
            return ""
        }
    }

    // MARK: - Market Category Empty State (US-012)

    @ViewBuilder
    private var marketCategoryEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(Theme.textMuted)

            Text(emptyStateDescription)
                .font(.subheadline)
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 16)
    }

    // MARK: - Helpers

    /// Extract spread number from label (e.g., "Lakers -3.5" -> "-3.5")
    private func formatSpreadValue(_ label: String) -> String {
        let components = label.components(separatedBy: " ")
        if let last = components.last, (last.hasPrefix("+") || last.hasPrefix("-")) {
            return last
        }
        return label
    }

    /// Format total label (e.g., "Over 220.5" -> "O 220.5")
    private func formatTotalLabel(_ label: String) -> String {
        let components = label.components(separatedBy: " ")
        guard components.count >= 2 else { return label }

        let direction = components[0].lowercased()
        let value = components[1]

        if direction == "over" {
            return "O \(value)"
        } else if direction == "under" {
            return "U \(value)"
        }
        return label
    }

    /// Format odds for display
    private func formatOdds(_ odds: Int) -> String {
        odds >= 0 ? "+\(odds)" : "\(odds)"
    }

    // MARK: - Bet Slip Indicator (US-014)

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
}

// MARK: - Preview

#Preview {
    let event = Event(
        sport: "NBA",
        league: "NBA",
        homeTeam: "Lakers",
        awayTeam: "Celtics",
        startTime: Date(),
        status: .live
    )

    // Add sample markets for preview
    let spread = Market(
        type: .spread,
        sideA: "Celtics +3.5",
        sideB: "Lakers -3.5",
        oddsA: -110,
        oddsB: -110,
        event: event
    )

    let ml = Market(
        type: .moneyline,
        sideA: "Celtics",
        sideB: "Lakers",
        oddsA: 150,
        oddsB: -170,
        event: event
    )

    let total = Market(
        type: .total,
        sideA: "Over 220.5",
        sideB: "Under 220.5",
        oddsA: -110,
        oddsB: -110,
        event: event
    )

    event.markets = [spread, ml, total]

    return NavigationStack {
        GameDetailView(
            player: Player(name: "Test", email: "test@test.com", creditLimit: 1000),
            event: event
        )
    }
    .modelContainer(for: [Player.self, Event.self, Bet.self, LedgerEntry.self], inMemory: true)
    .preferredColorScheme(.dark)
}

// MARK: - Market Category Tab Button (US-012)

/// Button for market category filter tabs with selected state styling
/// Matches SportTabButton styling from GamesView for consistency
struct MarketCategoryTabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    /// Press state for scale animation
    @State private var isPressed: Bool = false

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                action()
            }
        }) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .medium)
                .foregroundStyle(isSelected ? Theme.background : Theme.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Theme.accent : Theme.cardBackground)
                .clipShape(Capsule())
                .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        .buttonStyle(.plain)
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
