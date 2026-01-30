import SwiftUI
import SwiftData

/// US-001: Compact Game Row Component
/// A streamlined row for displaying game info with inline odds buttons
/// Reduced height (~80-90pt) with no decorative card styling
struct CompactGameRow: View {
    let event: Event
    let selections: Set<BetSlipSelection>
    let onSelectOdds: (BetSlipSelection) -> Void
    let onTapCard: () -> Void

    /// Minutes before event start to lock betting (default 0 = lock at start time)
    var lockOffsetMinutes: Int = 0

    /// Computed property to determine if event is locked for betting
    private var isEventLocked: Bool {
        event.isLocked(offsetMinutes: lockOffsetMinutes)
    }

    /// Computed property to determine if event is canceled
    private var isEventCanceled: Bool {
        event.status == .canceled
    }

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
            formatter.dateFormat = "E, MMM d"
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

    /// Check if a specific selection is in the bet slip
    private func isSelected(_ selection: BetSlipSelection) -> Bool {
        selections.contains(selection)
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

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Main row content
            VStack(spacing: 4) {
                // Time header row
                timeHeader

                // Away team row with odds
                teamOddsRow(
                    teamName: event.awayTeam,
                    spreadMarket: isEventCanceled ? nil : spreadMarket,
                    moneylineMarket: isEventCanceled ? nil : moneylineMarket,
                    totalMarket: isEventCanceled ? nil : totalMarket,
                    isAwayTeam: true
                )

                // Home team row with odds
                teamOddsRow(
                    teamName: event.homeTeam,
                    spreadMarket: isEventCanceled ? nil : spreadMarket,
                    moneylineMarket: isEventCanceled ? nil : moneylineMarket,
                    totalMarket: isEventCanceled ? nil : totalMarket,
                    isAwayTeam: false
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.cardBackground)
            .contentShape(Rectangle())
            .onTapGesture {
                onTapCard()
            }

            // Bottom divider
            Rectangle()
                .fill(Theme.border)
                .frame(height: 0.5)
        }
    }

    // MARK: - Time Header

    @ViewBuilder
    private var timeHeader: some View {
        HStack(spacing: 4) {
            // Start time
            Text(formattedStartTime)
                .font(.caption2)
                .foregroundColor(Theme.textSecondary)

            // Lock indicator when event is locked
            if isEventLocked {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundColor(Theme.warning)
            }

            // Live indicator
            if event.status == .live {
                Text("LIVE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Theme.live)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
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

            Spacer()
        }
    }

    // MARK: - Team Row with Odds

    /// Fixed button size for consistent layout
    private let oddsButtonWidth: CGFloat = 52
    private let oddsButtonHeight: CGFloat = 44

    /// Single row with team name and aligned odds buttons
    @ViewBuilder
    private func teamOddsRow(
        teamName: String,
        spreadMarket: Market?,
        moneylineMarket: Market?,
        totalMarket: Market?,
        isAwayTeam: Bool
    ) -> some View {
        HStack(spacing: 8) {
            // Team name
            Text(teamName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Spread button
            if let spread = spreadMarket {
                let side = isAwayTeam ? spread.sideA : spread.sideB
                let odds = isAwayTeam ? spread.oddsA : spread.oddsB
                let sideIndicator = isAwayTeam ? "a" : "b"
                let selection = makeSelection(market: spread, side: side, odds: odds, sideIndicator: sideIndicator)

                compactOddsButton(
                    topText: formatSpreadValue(side),
                    odds: odds,
                    isSelected: isSelected(selection),
                    isDisabled: isEventLocked,
                    action: { if !isEventLocked { onSelectOdds(selection) } }
                )
            } else if moneylineMarket != nil || totalMarket != nil {
                // Placeholder to maintain alignment
                Color.clear
                    .frame(width: oddsButtonWidth, height: oddsButtonHeight)
            }

            // Moneyline button
            if let ml = moneylineMarket {
                let odds = isAwayTeam ? ml.oddsA : ml.oddsB
                let side = isAwayTeam ? ml.sideA : ml.sideB
                let sideIndicator = isAwayTeam ? "a" : "b"
                let selection = makeSelection(market: ml, side: side, odds: odds, sideIndicator: sideIndicator)

                compactOddsButton(
                    topText: nil,
                    odds: odds,
                    isSelected: isSelected(selection),
                    isDisabled: isEventLocked,
                    action: { if !isEventLocked { onSelectOdds(selection) } }
                )
            } else if spreadMarket != nil || totalMarket != nil {
                // Placeholder to maintain alignment
                Color.clear
                    .frame(width: oddsButtonWidth, height: oddsButtonHeight)
            }

            // Total button (Over for away/top row, Under for home/bottom row)
            if let total = totalMarket {
                let side = isAwayTeam ? total.sideA : total.sideB
                let odds = isAwayTeam ? total.oddsA : total.oddsB
                let sideIndicator = isAwayTeam ? "a" : "b"
                let selection = makeSelection(market: total, side: side, odds: odds, sideIndicator: sideIndicator)

                compactOddsButton(
                    topText: formatTotalValue(side),
                    odds: odds,
                    isSelected: isSelected(selection),
                    isDisabled: isEventLocked,
                    action: { if !isEventLocked { onSelectOdds(selection) } }
                )
            } else if spreadMarket != nil || moneylineMarket != nil {
                // Placeholder to maintain alignment
                Color.clear
                    .frame(width: oddsButtonWidth, height: oddsButtonHeight)
            }
        }
        .frame(height: 36)
    }

    // MARK: - Compact Odds Button

    @ViewBuilder
    private func compactOddsButton(
        topText: String?,
        odds: Int,
        isSelected: Bool,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            // Display value and odds on single line if topText exists
            if let text = topText {
                Text("\(text) \(formatOdds(odds))")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isSelected ? Theme.background : Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                Text(formatOdds(odds))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isSelected ? Theme.background : Theme.textPrimary)
            }
        }
        .frame(width: oddsButtonWidth, height: oddsButtonHeight)
        .background(isSelected ? Theme.accent : Theme.elevatedBackground)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Theme.accent : Theme.border, lineWidth: 1)
        )
        .opacity(isDisabled ? 0.5 : 1.0)
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isSelected)
    }

    // MARK: - Helpers

    private func formatOdds(_ odds: Int) -> String {
        odds >= 0 ? "+\(odds)" : "\(odds)"
    }

    /// Extract spread number from label (e.g., "Lakers -3.5" -> "-3.5")
    private func formatSpreadValue(_ label: String) -> String {
        let components = label.components(separatedBy: " ")
        if let last = components.last, (last.hasPrefix("+") || last.hasPrefix("-")) {
            return last
        }
        return label
    }

    /// Extract total value from label (e.g., "Over 220.5" -> "o220.5", "Under 220.5" -> "u220.5")
    private func formatTotalValue(_ label: String) -> String {
        let components = label.components(separatedBy: " ")
        guard components.count >= 2 else { return label }

        let direction = components[0].lowercased()
        let value = components[1]

        if direction == "over" {
            return "o\(value)"
        } else if direction == "under" {
            return "u\(value)"
        }
        return label
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
        marketType: .moneyline,
        sideIndicator: "b"
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

    return VStack(spacing: 0) {
        // Row with selection (live game)
        CompactGameRow(
            event: event,
            selections: [sampleSelection],
            onSelectOdds: { _ in },
            onTapCard: { }
        )

        // Row without selection (scheduled game)
        CompactGameRow(
            event: scheduledEvent,
            selections: [],
            onSelectOdds: { _ in },
            onTapCard: { }
        )
    }
    .background(Theme.background)
    .preferredColorScheme(.dark)
}
