import SwiftUI
import SwiftData

/// Selection model for bet slip integration
/// Used to track which odds buttons are selected across game cards
struct BetSlipSelection: Equatable, Hashable {
    let eventId: UUID
    let marketId: UUID
    let side: String
    let odds: Int
    let marketType: MarketType

    func hash(into hasher: inout Hasher) {
        hasher.combine(eventId)
        hasher.combine(marketId)
        hasher.combine(side)
    }

    static func == (lhs: BetSlipSelection, rhs: BetSlipSelection) -> Bool {
        lhs.eventId == rhs.eventId && lhs.marketId == rhs.marketId && lhs.side == rhs.side
    }
}

/// US-037: Game Card Component
/// Displays game info with quick-pick odds buttons and expandable markets
/// US-039: Added favorite toggle functionality
struct GameCardView: View {
    let event: Event
    let selections: Set<BetSlipSelection>
    let onSelectOdds: (BetSlipSelection) -> Void
    let onTapCard: () -> Void

    /// Whether the card is expanded to show all markets
    @State private var isExpanded: Bool = false

    /// Favorites manager for star toggle (US-039)
    @ObservedObject private var favoritesManager = FavoritesManager.shared

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
            formatter.dateFormat = "E, MMM d h:mm a"
            return formatter.string(from: event.startTime)
        }
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

    /// All markets for expanded view
    private var allMarkets: [Market] {
        event.markets ?? []
    }

    /// Check if a specific selection is in the bet slip
    private func isSelected(_ selection: BetSlipSelection) -> Bool {
        selections.contains(selection)
    }

    /// Create a selection for a given market and side
    private func makeSelection(market: Market, side: String, odds: Int) -> BetSlipSelection {
        BetSlipSelection(
            eventId: event.id,
            marketId: market.id,
            side: side,
            odds: odds,
            marketType: market.type
        )
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Main card content
            cardContent

            // Expanded markets section
            if isExpanded {
                expandedMarketsSection
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
    }

    // MARK: - Card Content

    @ViewBuilder
    private var cardContent: some View {
        VStack(spacing: 12) {
            // Header: Time and Live indicator
            cardHeader

            // Teams display
            teamsSection

            // Quick-pick odds section
            quickPickOddsSection

            // Expand/collapse button
            expandButton
        }
        .padding(12)
        .contentShape(Rectangle())
        .onTapGesture {
            onTapCard()
        }
    }

    // MARK: - Card Header

    @ViewBuilder
    private var cardHeader: some View {
        HStack {
            // Start time
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(formattedStartTime)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Live indicator
            if event.status == .live {
                liveIndicator
            }

            // Sport badge
            Text(event.sport)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.systemGray5))
                .clipShape(Capsule())
        }
    }

    // MARK: - Live Indicator

    @ViewBuilder
    private var liveIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
            Text("LIVE")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(.green)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.green.opacity(0.15))
        .clipShape(Capsule())
    }

    // MARK: - Teams Section

    @ViewBuilder
    private var teamsSection: some View {
        VStack(spacing: 8) {
            // Away team row
            teamRow(teamName: event.awayTeam)

            // Home team row
            teamRow(teamName: event.homeTeam)
        }
    }

    /// Team row with favorite star (US-039)
    @ViewBuilder
    private func teamRow(teamName: String) -> some View {
        HStack {
            Text(teamName)
                .font(.headline)
                .fontWeight(.semibold)

            Spacer()

            // Favorite star button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    favoritesManager.toggleFavorite(teamName)
                }
            }) {
                Image(systemName: favoritesManager.isFavorite(teamName) ? "star.fill" : "star")
                    .font(.system(size: 18))
                    .foregroundStyle(favoritesManager.isFavorite(teamName) ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Quick-Pick Odds Section

    @ViewBuilder
    private var quickPickOddsSection: some View {
        VStack(spacing: 8) {
            // Headers
            HStack(spacing: 8) {
                Text("")
                    .frame(maxWidth: .infinity, alignment: .leading)

                if spreadMarket != nil {
                    Text("Spread")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 70)
                }

                if moneylineMarket != nil {
                    Text("ML")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 70)
                }
            }

            // Away team odds row
            if let spread = spreadMarket, let ml = moneylineMarket {
                oddsRow(
                    teamName: event.awayTeam,
                    spreadSelection: makeSelection(market: spread, side: spread.sideA, odds: spread.oddsA),
                    spreadLabel: spread.sideA,
                    spreadOdds: spread.oddsA,
                    mlSelection: makeSelection(market: ml, side: ml.sideA, odds: ml.oddsA),
                    mlOdds: ml.oddsA
                )
            } else if let spread = spreadMarket {
                oddsRowSpreadOnly(
                    teamName: event.awayTeam,
                    selection: makeSelection(market: spread, side: spread.sideA, odds: spread.oddsA),
                    spreadLabel: spread.sideA,
                    spreadOdds: spread.oddsA
                )
            } else if let ml = moneylineMarket {
                oddsRowMLOnly(
                    teamName: event.awayTeam,
                    selection: makeSelection(market: ml, side: ml.sideA, odds: ml.oddsA),
                    mlOdds: ml.oddsA
                )
            }

            // Home team odds row
            if let spread = spreadMarket, let ml = moneylineMarket {
                oddsRow(
                    teamName: event.homeTeam,
                    spreadSelection: makeSelection(market: spread, side: spread.sideB, odds: spread.oddsB),
                    spreadLabel: spread.sideB,
                    spreadOdds: spread.oddsB,
                    mlSelection: makeSelection(market: ml, side: ml.sideB, odds: ml.oddsB),
                    mlOdds: ml.oddsB
                )
            } else if let spread = spreadMarket {
                oddsRowSpreadOnly(
                    teamName: event.homeTeam,
                    selection: makeSelection(market: spread, side: spread.sideB, odds: spread.oddsB),
                    spreadLabel: spread.sideB,
                    spreadOdds: spread.oddsB
                )
            } else if let ml = moneylineMarket {
                oddsRowMLOnly(
                    teamName: event.homeTeam,
                    selection: makeSelection(market: ml, side: ml.sideB, odds: ml.oddsB),
                    mlOdds: ml.oddsB
                )
            }
        }
    }

    // MARK: - Odds Row Variants

    @ViewBuilder
    private func oddsRow(
        teamName: String,
        spreadSelection: BetSlipSelection,
        spreadLabel: String,
        spreadOdds: Int,
        mlSelection: BetSlipSelection,
        mlOdds: Int
    ) -> some View {
        HStack(spacing: 8) {
            // Team name placeholder (invisible - teams shown above)
            Color.clear
                .frame(maxWidth: .infinity, alignment: .leading)

            // Spread button
            OddsButton(
                topLabel: formatSpreadLabel(spreadLabel),
                odds: spreadOdds,
                isSelected: isSelected(spreadSelection),
                action: { onSelectOdds(spreadSelection) }
            )
            .frame(width: 70)

            // Moneyline button
            OddsButton(
                topLabel: nil,
                odds: mlOdds,
                isSelected: isSelected(mlSelection),
                action: { onSelectOdds(mlSelection) }
            )
            .frame(width: 70)
        }
    }

    @ViewBuilder
    private func oddsRowSpreadOnly(
        teamName: String,
        selection: BetSlipSelection,
        spreadLabel: String,
        spreadOdds: Int
    ) -> some View {
        HStack(spacing: 8) {
            Color.clear
                .frame(maxWidth: .infinity, alignment: .leading)

            OddsButton(
                topLabel: formatSpreadLabel(spreadLabel),
                odds: spreadOdds,
                isSelected: isSelected(selection),
                action: { onSelectOdds(selection) }
            )
            .frame(width: 70)
        }
    }

    @ViewBuilder
    private func oddsRowMLOnly(
        teamName: String,
        selection: BetSlipSelection,
        mlOdds: Int
    ) -> some View {
        HStack(spacing: 8) {
            Color.clear
                .frame(maxWidth: .infinity, alignment: .leading)

            OddsButton(
                topLabel: nil,
                odds: mlOdds,
                isSelected: isSelected(selection),
                action: { onSelectOdds(selection) }
            )
            .frame(width: 70)
        }
    }

    /// Extract spread number from label (e.g., "Lakers -3.5" -> "-3.5")
    private func formatSpreadLabel(_ label: String) -> String {
        // Try to extract the spread number from the label
        let components = label.components(separatedBy: " ")
        if let last = components.last, (last.hasPrefix("+") || last.hasPrefix("-")) {
            return last
        }
        return label
    }

    // MARK: - Expand Button

    @ViewBuilder
    private var expandButton: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }) {
            HStack {
                Text(isExpanded ? "Show Less" : "All Markets")
                    .font(.caption)
                    .foregroundStyle(.blue)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Expanded Markets Section

    @ViewBuilder
    private var expandedMarketsSection: some View {
        VStack(spacing: 12) {
            Divider()

            ForEach(allMarkets, id: \.id) { market in
                expandedMarketRow(market: market)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private func expandedMarketRow(market: Market) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Market type header
            Text(marketTypeName(market.type))
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            // Market options
            HStack(spacing: 8) {
                // Side A
                let selectionA = makeSelection(market: market, side: market.sideA, odds: market.oddsA)
                OddsButton(
                    topLabel: market.sideA,
                    odds: market.oddsA,
                    isSelected: isSelected(selectionA),
                    action: { onSelectOdds(selectionA) }
                )

                // Side B
                let selectionB = makeSelection(market: market, side: market.sideB, odds: market.oddsB)
                OddsButton(
                    topLabel: market.sideB,
                    odds: market.oddsB,
                    isSelected: isSelected(selectionB),
                    action: { onSelectOdds(selectionB) }
                )
            }
        }
    }

    private func marketTypeName(_ type: MarketType) -> String {
        switch type {
        case .spread: return "Spread"
        case .total: return "Total"
        case .moneyline: return "Moneyline"
        }
    }
}

// MARK: - Odds Button Component

/// Reusable odds button with selection state and tap feedback
struct OddsButton: View {
    let topLabel: String?
    let odds: Int
    let isSelected: Bool
    let action: () -> Void

    @State private var isPressed: Bool = false

    private var formattedOdds: String {
        odds >= 0 ? "+\(odds)" : "\(odds)"
    }

    var body: some View {
        Button(action: {
            // Trigger tap animation
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = false
                }
            }
            action()
        }) {
            VStack(spacing: 2) {
                if let label = topLabel {
                    Text(label)
                        .font(.caption2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Text(formattedOdds)
                    .font(.subheadline)
                    .fontWeight(.bold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .background(isSelected ? Color.blue : Color(.systemGray5))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    let event = Event(
        sport: "NBA",
        league: "NBA",
        homeTeam: "Lakers",
        awayTeam: "Celtics",
        startTime: Date(),
        status: .live
    )

    // Add sample markets
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

    return VStack {
        GameCardView(
            event: event,
            selections: [],
            onSelectOdds: { _ in },
            onTapCard: { }
        )
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}
