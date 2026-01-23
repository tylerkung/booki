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
        .background(
            // Subtle gradient background for premium feel
            LinearGradient(
                colors: [Theme.cardBackground, Color(hex: 0x151515)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    // Subtle accent-tinted border for depth
                    LinearGradient(
                        colors: [Theme.border.opacity(0.8), Theme.border.opacity(0.4)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        // Subtle shadow for depth
        .shadow(color: Color.black.opacity(0.4), radius: 8, x: 0, y: 4)
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
                    .foregroundColor(Theme.textSecondary)
                Text(formattedStartTime)
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
            }

            Spacer()

            // Live indicator
            if event.status == .live {
                liveIndicator
            }

            // Sport badge
            Text(event.sport)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(Theme.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.elevatedBackground)
                .clipShape(Capsule())
        }
    }

    // MARK: - Live Indicator

    /// Pulsing animation state for live indicator
    @State private var isPulsing: Bool = false

    @ViewBuilder
    private var liveIndicator: some View {
        HStack(spacing: 4) {
            // Pulsing dot with glow effect
            ZStack {
                // Outer glow
                Circle()
                    .fill(Theme.live.opacity(0.4))
                    .frame(width: 12, height: 12)
                    .scaleEffect(isPulsing ? 1.3 : 0.8)
                    .opacity(isPulsing ? 0 : 0.8)

                // Inner solid dot
                Circle()
                    .fill(Theme.live)
                    .frame(width: 6, height: 6)
                    .shadow(color: Theme.live.opacity(0.8), radius: 4, x: 0, y: 0)
            }
            Text("LIVE")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(Theme.live)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Theme.live.opacity(0.15))
                .overlay(
                    Capsule()
                        .stroke(Theme.live.opacity(0.3), lineWidth: 1)
                )
        )
        .shadow(color: Theme.live.opacity(0.3), radius: 6, x: 0, y: 0)
        .onAppear {
            // Start continuous pulsing animation
            withAnimation(
                Animation
                    .easeInOut(duration: 1.2)
                    .repeatForever(autoreverses: false)
            ) {
                isPulsing = true
            }
        }
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
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(Theme.textPrimary)
                .shadow(color: Color.black.opacity(0.3), radius: 1, x: 0, y: 1)

            Spacer()

            // Favorite star button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    favoritesManager.toggleFavorite(teamName)
                }
            }) {
                Image(systemName: favoritesManager.isFavorite(teamName) ? "star.fill" : "star")
                    .font(.system(size: 18))
                    .foregroundColor(favoritesManager.isFavorite(teamName) ? Theme.gold : Theme.textMuted)
                    .shadow(color: favoritesManager.isFavorite(teamName) ? Theme.gold.opacity(0.5) : Color.clear, radius: 4, x: 0, y: 0)
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
                    Text("SPREAD")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Theme.textMuted)
                        .tracking(0.5)
                        .frame(width: 70)
                }

                if moneylineMarket != nil {
                    Text("ML")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Theme.textMuted)
                        .tracking(0.5)
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
            HStack(spacing: 4) {
                Text(isExpanded ? "Show Less" : "All Markets")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.accent)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Theme.accent)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(Theme.accent.opacity(0.1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Expanded Markets Section

    @ViewBuilder
    private var expandedMarketsSection: some View {
        VStack(spacing: 12) {
            // Styled divider
            Rectangle()
                .fill(Theme.divider)
                .frame(height: 1)
                .padding(.horizontal, -12)

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
            Text(marketTypeName(market.type).uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Theme.textMuted)
                .tracking(0.5)

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

/// Reusable odds button with pill/capsule shape, selection state, and tap feedback
/// US-050: Premium sportsbook styling with bright accent for selected state
/// US-053: Enhanced animations for tap and selection highlight
struct OddsButton: View {
    let topLabel: String?
    let odds: Int
    let isSelected: Bool
    let action: () -> Void

    @State private var isPressed: Bool = false
    /// US-053: Track when selection state changes to show highlight pulse
    @State private var showSelectionHighlight: Bool = false

    private var formattedOdds: String {
        odds >= 0 ? "+\(odds)" : "\(odds)"
    }

    var body: some View {
        Button(action: {
            // US-053: Trigger tap animation with spring
            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                    isPressed = false
                }
            }
            // US-053: Show selection highlight pulse when adding to slip
            if !isSelected {
                showSelectionHighlight = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showSelectionHighlight = false
                }
            }
            action()
        }) {
            VStack(spacing: 2) {
                if let label = topLabel {
                    Text(label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(isSelected ? Theme.cardBackground : Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Text(formattedOdds)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(isSelected ? Theme.cardBackground : Theme.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .background(
                Group {
                    if isSelected {
                        // Bright accent background with subtle gradient for selected state
                        LinearGradient(
                            colors: [Theme.accent, Theme.accent.opacity(0.85)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    } else {
                        // Dark elevated background for unselected state
                        Theme.elevatedBackground
                    }
                }
            )
            // Pill/capsule shape
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        isSelected ? Theme.accent.opacity(0.5) : Theme.border,
                        lineWidth: isSelected ? 2 : 0.5
                    )
            )
            // US-053: Selection highlight pulse overlay
            .overlay(
                Capsule()
                    .fill(Theme.accent.opacity(showSelectionHighlight ? 0.4 : 0))
                    .animation(.easeOut(duration: 0.3), value: showSelectionHighlight)
            )
            // Glow effect for selected state
            .shadow(
                color: isSelected ? Theme.accent.opacity(0.4) : Color.clear,
                radius: isSelected ? 8 : 0,
                x: 0,
                y: 0
            )
            .scaleEffect(isPressed ? 0.92 : 1.0)
            // US-053: Animate selection state changes
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
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

    // Create a sample selection to show selected state
    let sampleSelection = BetSlipSelection(
        eventId: event.id,
        marketId: ml.id,
        side: ml.sideB,
        odds: ml.oddsB,
        marketType: .moneyline
    )

    // Second event for preview (scheduled game)
    let scheduledEvent = Event(
        sport: "NFL",
        league: "NFL",
        homeTeam: "Chiefs",
        awayTeam: "Bills",
        startTime: Date().addingTimeInterval(86400),
        status: .scheduled
    )
    let nflSpread = Market(
        type: .spread,
        sideA: "Bills +3",
        sideB: "Chiefs -3",
        oddsA: -110,
        oddsB: -110,
        event: scheduledEvent
    )
    let nflMl = Market(
        type: .moneyline,
        sideA: "Bills",
        sideB: "Chiefs",
        oddsA: 140,
        oddsB: -160,
        event: scheduledEvent
    )
    scheduledEvent.markets = [nflSpread, nflMl]

    return VStack(spacing: 16) {
        // Card with selection (live game)
        GameCardView(
            event: event,
            selections: [sampleSelection],
            onSelectOdds: { _ in },
            onTapCard: { }
        )

        // Card without selection (scheduled game)
        GameCardView(
            event: scheduledEvent,
            selections: [],
            onSelectOdds: { _ in },
            onTapCard: { }
        )
    }
    .padding()
    .background(Theme.background)
    .preferredColorScheme(.dark)
}
