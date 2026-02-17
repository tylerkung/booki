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
                .font(Theme.caption2)
                .foregroundColor(Theme.textSecondary)

            // Lock indicator when event is locked
            if isEventLocked {
                Image(systemName: "lock.fill")
                    .font(Theme.caption2)
                    .foregroundColor(Theme.warning)
            }

            // Live indicator
            if event.status == .live {
                Text("LIVE")
                    .font(Theme.font(size: 10, weight: .bold))
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
                    .font(Theme.font(size: 10, weight: .bold))
                    .foregroundColor(Theme.warning)
            }

            // Canceled indicator
            if event.status == .canceled {
                Text("CANCELED")
                    .font(Theme.font(size: 10, weight: .bold))
                    .foregroundColor(Theme.danger)
            }

            Spacer()
        }
    }

    // MARK: - Team Row with Odds

    /// Fixed button size for consistent layout
    private let oddsButtonWidth: CGFloat = 65
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
            // Team abbreviation badge + name
            teamBadge(teamName)

            Text(teamName)
                .font(Theme.font(size: 13, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Spread button - US-005: line value prominent, odds secondary
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
                    showOddsAsSecondary: true,
                    action: { if !isEventLocked { onSelectOdds(selection) } }
                )
            } else if moneylineMarket != nil || totalMarket != nil {
                // Placeholder to maintain alignment
                Color.clear
                    .frame(width: oddsButtonWidth, height: oddsButtonHeight)
            }

            // Moneyline button - odds is the key value, displayed prominently
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
                    showOddsAsSecondary: false,
                    action: { if !isEventLocked { onSelectOdds(selection) } }
                )
            } else if spreadMarket != nil || totalMarket != nil {
                // Placeholder to maintain alignment
                Color.clear
                    .frame(width: oddsButtonWidth, height: oddsButtonHeight)
            }

            // Total button (Over for away/top row, Under for home/bottom row) - US-005: line value prominent, odds secondary
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
                    showOddsAsSecondary: true,
                    action: { if !isEventLocked { onSelectOdds(selection) } }
                )
            } else if spreadMarket != nil || moneylineMarket != nil {
                // Placeholder to maintain alignment
                Color.clear
                    .frame(width: oddsButtonWidth, height: oddsButtonHeight)
            }
        }
        .frame(height: oddsButtonHeight)
    }

    // MARK: - Compact Odds Button

    /// US-005: Updated to show line value prominently with payout odds de-emphasized
    /// - showOddsAsSecondary: true for spread/total (line value primary), false for moneyline (odds primary)
    @ViewBuilder
    private func compactOddsButton(
        topText: String?,
        odds: Int,
        isSelected: Bool,
        isDisabled: Bool,
        showOddsAsSecondary: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            if showOddsAsSecondary {
                // US-005: Spread/Total - line value prominent on top, odds small and gray below
                VStack(spacing: 1) {
                    if let text = topText {
                        Text(text)
                            .font(Theme.font(size: 11, weight: .bold))
                            .foregroundColor(isSelected ? Theme.background : Theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Text(formatOdds(odds))
                        .font(Theme.font(size: 9, weight: .medium))
                        .foregroundColor(isSelected ? Theme.background.opacity(0.7) : Theme.textMuted)
                }
            } else {
                // Moneyline - just show odds prominently
                Text(formatOdds(odds))
                    .font(Theme.font(size: 12, weight: .semibold))
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

    // MARK: - Team Abbreviation

    /// Derives a 2-3 letter abbreviation from a team name
    /// e.g., "Los Angeles Lakers" → "LAL", "Boston Celtics" → "CEL", "Golden State Warriors" → "GWA"
    private func teamAbbreviation(_ teamName: String) -> String {
        let words = teamName.components(separatedBy: " ").filter { !$0.isEmpty }
        guard !words.isEmpty else { return "?" }

        // Single word: take first 3 letters
        if words.count == 1 {
            return String(words[0].prefix(3)).uppercased()
        }

        // Team name is the last word
        let teamWord = words.last!

        // Two-word cities (3+ words total): first letter of city + first 2 letters of team name
        if words.count >= 3 {
            let cityInitial = String(words[0].prefix(1))
            let teamPrefix = String(teamWord.prefix(2))
            return (cityInitial + teamPrefix).uppercased()
        }

        // Two words: take first 3 letters of last word
        return String(teamWord.prefix(3)).uppercased()
    }

    /// Small circle badge showing team abbreviation
    @ViewBuilder
    private func teamBadge(_ teamName: String) -> some View {
        Text(teamAbbreviation(teamName))
            .font(Theme.font(size: 9, weight: .bold))
            .foregroundColor(Theme.textSecondary)
            .frame(width: 24, height: 24)
            .background(Theme.elevatedBackground)
            .clipShape(Circle())
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
