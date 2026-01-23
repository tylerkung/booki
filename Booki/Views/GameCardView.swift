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
/// Displays game info with quick-pick odds buttons
/// Team names aligned with spread and ML boxes in a clean grid layout
/// US-008: Lock status indicator for events approaching lock time
struct GameCardView: View {
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
        }
        .background(Theme.cardGradient)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .stroke(
                    // Exciting gradient border with accent hints
                    LinearGradient(
                        colors: [
                            Theme.accent.opacity(0.4),
                            Theme.border.opacity(0.6),
                            Theme.accentSecondary.opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        // Layered shadows for depth and glow
        .shadow(color: Theme.accent.opacity(0.08), radius: 16, x: 0, y: 0)
        .shadow(color: Color.black.opacity(0.5), radius: 10, x: 0, y: 6)
    }

    // MARK: - Card Content

    @ViewBuilder
    private var cardContent: some View {
        VStack(spacing: 12) {
            // Header: Time and Live indicator
            cardHeader

            // Combined teams + odds section (aligned)
            teamsWithOddsSection
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

                // US-008: Lock indicator when event is locked
                if isEventLocked {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundColor(Theme.warning)
                }
            }

            Spacer()

            // Live indicator
            if event.status == .live {
                liveIndicator
            }

            // Postponed indicator
            if event.status == .postponed {
                postponedBadge
            }

            // Canceled indicator
            if event.status == .canceled {
                canceledBadge
            }

            // Sport badge with gradient accent
            Text(event.sport)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Theme.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Theme.accentSecondary.opacity(0.2))
                        .overlay(
                            Capsule()
                                .stroke(Theme.accentSecondary.opacity(0.4), lineWidth: 1)
                        )
                )
        }
    }

    // MARK: - Live Indicator

    /// Pulsing animation state for live indicator
    @State private var isPulsing: Bool = false

    @ViewBuilder
    private var liveIndicator: some View {
        HStack(spacing: 4) {
            // Pulsing dot with enhanced glow effect
            ZStack {
                // Outer expanding glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Theme.live.opacity(0.6), Theme.live.opacity(0)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 10
                        )
                    )
                    .frame(width: 16, height: 16)
                    .scaleEffect(isPulsing ? 1.5 : 0.8)
                    .opacity(isPulsing ? 0 : 1)

                // Inner solid dot with gradient
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Theme.live, Theme.accentTertiary],
                            center: .center,
                            startRadius: 0,
                            endRadius: 4
                        )
                    )
                    .frame(width: 8, height: 8)
                    .shadow(color: Theme.live, radius: 6, x: 0, y: 0)
            }
            Text("LIVE")
                .font(.system(size: 10, weight: .black))
                .foregroundColor(Theme.live)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Theme.live.opacity(0.2), Theme.accentTertiary.opacity(0.1)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay(
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: [Theme.live.opacity(0.6), Theme.accentTertiary.opacity(0.4)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 1.5
                        )
                )
        )
        .shadow(color: Theme.live.opacity(0.4), radius: 8, x: 0, y: 0)
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

    // MARK: - Postponed Badge

    @ViewBuilder
    private var postponedBadge: some View {
        Text("POSTPONED")
            .font(.system(size: 10, weight: .black))
            .foregroundColor(Theme.warning)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Theme.warning.opacity(0.2))
                    .overlay(
                        Capsule()
                            .stroke(Theme.warning.opacity(0.6), lineWidth: 1.5)
                    )
            )
    }

    // MARK: - Canceled Badge

    @ViewBuilder
    private var canceledBadge: some View {
        Text("CANCELED")
            .font(.system(size: 10, weight: .black))
            .foregroundColor(Theme.danger)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Theme.danger.opacity(0.2))
                    .overlay(
                        Capsule()
                            .stroke(Theme.danger.opacity(0.6), lineWidth: 1.5)
                    )
            )
    }

    // MARK: - Combined Teams + Odds Section

    /// Fixed button size for consistent layout
    private let oddsButtonSize: CGFloat = 60

    @ViewBuilder
    private var teamsWithOddsSection: some View {
        VStack(spacing: 8) {
            // Column headers - hide for canceled events
            if !isEventCanceled {
                HStack(spacing: 8) {
                    // Team column header (empty)
                    Text("")
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if spreadMarket != nil {
                        Text("SPREAD")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Theme.textMuted)
                            .tracking(0.8)
                            .frame(width: oddsButtonSize)
                    }

                    if moneylineMarket != nil {
                        Text("ML")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Theme.textMuted)
                            .tracking(0.8)
                            .frame(width: oddsButtonSize)
                    }

                    if totalMarket != nil {
                        Text("TOTAL")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Theme.textMuted)
                            .tracking(0.8)
                            .frame(width: oddsButtonSize)
                    }
                }
            }

            // Away team row with odds (pass nil markets if canceled to hide buttons)
            teamOddsRow(
                teamName: event.awayTeam,
                spreadMarket: isEventCanceled ? nil : spreadMarket,
                moneylineMarket: isEventCanceled ? nil : moneylineMarket,
                totalMarket: isEventCanceled ? nil : totalMarket,
                isAwayTeam: true
            )

            // Home team row with odds (pass nil markets if canceled to hide buttons)
            teamOddsRow(
                teamName: event.homeTeam,
                spreadMarket: isEventCanceled ? nil : spreadMarket,
                moneylineMarket: isEventCanceled ? nil : moneylineMarket,
                totalMarket: isEventCanceled ? nil : totalMarket,
                isAwayTeam: false
            )
        }
    }

    /// Single row with team name and aligned odds buttons
    /// US-008: Buttons are disabled and dimmed when event is locked
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
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Spread button
            if let spread = spreadMarket {
                let side = isAwayTeam ? spread.sideA : spread.sideB
                let odds = isAwayTeam ? spread.oddsA : spread.oddsB
                let selection = makeSelection(market: spread, side: side, odds: odds)

                SpreadButton(
                    spreadValue: formatSpreadValue(side),
                    odds: odds,
                    isSelected: isSelected(selection),
                    isDisabled: isEventLocked,
                    action: { if !isEventLocked { onSelectOdds(selection) } }
                )
                .frame(width: oddsButtonSize, height: oddsButtonSize)
                .opacity(isEventLocked ? 0.5 : 1.0)
            }

            // Moneyline button
            if let ml = moneylineMarket {
                let odds = isAwayTeam ? ml.oddsA : ml.oddsB
                let side = isAwayTeam ? ml.sideA : ml.sideB
                let selection = makeSelection(market: ml, side: side, odds: odds)

                MLButton(
                    odds: odds,
                    isSelected: isSelected(selection),
                    isDisabled: isEventLocked,
                    action: { if !isEventLocked { onSelectOdds(selection) } }
                )
                .frame(width: oddsButtonSize, height: oddsButtonSize)
                .opacity(isEventLocked ? 0.5 : 1.0)
            }

            // Total button (Over for away/top row, Under for home/bottom row)
            if let total = totalMarket {
                let side = isAwayTeam ? total.sideA : total.sideB  // sideA = Over, sideB = Under
                let odds = isAwayTeam ? total.oddsA : total.oddsB
                let selection = makeSelection(market: total, side: side, odds: odds)

                TotalButton(
                    totalValue: formatTotalValue(side),
                    odds: odds,
                    isSelected: isSelected(selection),
                    isDisabled: isEventLocked,
                    action: { if !isEventLocked { onSelectOdds(selection) } }
                )
                .frame(width: oddsButtonSize, height: oddsButtonSize)
                .opacity(isEventLocked ? 0.5 : 1.0)
            }
        }
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
    func formatTotalValue(_ label: String) -> String {
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

// MARK: - Spread Button Component

/// Spread button showing spread value as main text, odds as secondary
/// US-008: Added isDisabled parameter for locked events
struct SpreadButton: View {
    let spreadValue: String
    let odds: Int
    let isSelected: Bool
    var isDisabled: Bool = false
    let action: () -> Void

    @State private var isPressed: Bool = false
    @State private var showSelectionHighlight: Bool = false

    private var formattedOdds: String {
        odds >= 0 ? "+\(odds)" : "\(odds)"
    }

    var body: some View {
        Button(action: {
            guard !isDisabled else { return }
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                    isPressed = false
                }
            }
            if !isSelected {
                showSelectionHighlight = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    showSelectionHighlight = false
                }
            }
            action()
        }) {
            VStack(spacing: 2) {
                // Spread value as main text
                Text(spreadValue)
                    .font(.system(size: 14, weight: .black))
                    .foregroundColor(isSelected ? Theme.background : Theme.textPrimary)
                // Odds as smaller secondary text
                Text(formattedOdds)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(isSelected ? Theme.background.opacity(0.8) : Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Group {
                    if isSelected {
                        LinearGradient(
                            colors: [Theme.accent, Theme.accentSecondary.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    } else {
                        LinearGradient(
                            colors: [Theme.elevatedBackground, Theme.elevatedBackground.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall)
                    .stroke(
                        isSelected
                            ? LinearGradient(
                                colors: [Theme.accent, Theme.accentSecondary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(
                                colors: [Theme.border.opacity(0.6), Theme.border.opacity(0.3)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall)
                    .fill(
                        RadialGradient(
                            colors: [Theme.accent.opacity(showSelectionHighlight ? 0.6 : 0), Theme.accent.opacity(0)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 50
                        )
                    )
                    .animation(.easeOut(duration: 0.4), value: showSelectionHighlight)
            )
            .shadow(
                color: isSelected ? Theme.accent.opacity(0.5) : Color.clear,
                radius: isSelected ? 10 : 0,
                x: 0,
                y: 0
            )
            .scaleEffect(isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

// MARK: - ML Button Component

/// Moneyline button showing just the odds
/// US-008: Added isDisabled parameter for locked events
struct MLButton: View {
    let odds: Int
    let isSelected: Bool
    var isDisabled: Bool = false
    let action: () -> Void

    @State private var isPressed: Bool = false
    @State private var showSelectionHighlight: Bool = false

    private var formattedOdds: String {
        odds >= 0 ? "+\(odds)" : "\(odds)"
    }

    var body: some View {
        Button(action: {
            guard !isDisabled else { return }
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                    isPressed = false
                }
            }
            if !isSelected {
                showSelectionHighlight = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    showSelectionHighlight = false
                }
            }
            action()
        }) {
            Text(formattedOdds)
                .font(.system(size: 14, weight: .black))
                .foregroundColor(isSelected ? Theme.background : Theme.textPrimary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    Group {
                        if isSelected {
                            LinearGradient(
                                colors: [Theme.accent, Theme.accentSecondary.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        } else {
                            LinearGradient(
                                colors: [Theme.elevatedBackground, Theme.elevatedBackground.opacity(0.8)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall)
                        .stroke(
                            isSelected
                                ? LinearGradient(
                                    colors: [Theme.accent, Theme.accentSecondary],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                : LinearGradient(
                                    colors: [Theme.border.opacity(0.6), Theme.border.opacity(0.3)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                            lineWidth: isSelected ? 2 : 1
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall)
                        .fill(
                            RadialGradient(
                                colors: [Theme.accent.opacity(showSelectionHighlight ? 0.6 : 0), Theme.accent.opacity(0)],
                                center: .center,
                                startRadius: 0,
                                endRadius: 50
                            )
                        )
                        .animation(.easeOut(duration: 0.4), value: showSelectionHighlight)
                )
                .shadow(
                    color: isSelected ? Theme.accent.opacity(0.5) : Color.clear,
                    radius: isSelected ? 10 : 0,
                    x: 0,
                    y: 0
                )
                .scaleEffect(isPressed ? 0.92 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

// MARK: - Total Button Component

/// Total button showing total value (o220.5/u220.5) as main text, odds as secondary
/// US-008: Added isDisabled parameter for locked events
struct TotalButton: View {
    let totalValue: String
    let odds: Int
    let isSelected: Bool
    var isDisabled: Bool = false
    let action: () -> Void

    @State private var isPressed: Bool = false
    @State private var showSelectionHighlight: Bool = false

    private var formattedOdds: String {
        odds >= 0 ? "+\(odds)" : "\(odds)"
    }

    var body: some View {
        Button(action: {
            guard !isDisabled else { return }
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                    isPressed = false
                }
            }
            if !isSelected {
                showSelectionHighlight = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    showSelectionHighlight = false
                }
            }
            action()
        }) {
            VStack(spacing: 2) {
                // Total value as main text
                Text(totalValue)
                    .font(.system(size: 14, weight: .black))
                    .foregroundColor(isSelected ? Theme.background : Theme.textPrimary)
                // Odds as smaller secondary text
                Text(formattedOdds)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(isSelected ? Theme.background.opacity(0.8) : Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Group {
                    if isSelected {
                        LinearGradient(
                            colors: [Theme.accent, Theme.accentSecondary.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    } else {
                        LinearGradient(
                            colors: [Theme.elevatedBackground, Theme.elevatedBackground.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall)
                    .stroke(
                        isSelected
                            ? LinearGradient(
                                colors: [Theme.accent, Theme.accentSecondary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(
                                colors: [Theme.border.opacity(0.6), Theme.border.opacity(0.3)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall)
                    .fill(
                        RadialGradient(
                            colors: [Theme.accent.opacity(showSelectionHighlight ? 0.6 : 0), Theme.accent.opacity(0)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 50
                        )
                    )
                    .animation(.easeOut(duration: 0.4), value: showSelectionHighlight)
            )
            .shadow(
                color: isSelected ? Theme.accent.opacity(0.5) : Color.clear,
                radius: isSelected ? 10 : 0,
                x: 0,
                y: 0
            )
            .scaleEffect(isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

// MARK: - Legacy Odds Button (for expanded markets)

/// Generic odds button for expanded market section
struct OddsButton: View {
    let topLabel: String?
    let odds: Int
    let isSelected: Bool
    let action: () -> Void

    @State private var isPressed: Bool = false
    @State private var showSelectionHighlight: Bool = false

    private var formattedOdds: String {
        odds >= 0 ? "+\(odds)" : "\(odds)"
    }

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                    isPressed = false
                }
            }
            if !isSelected {
                showSelectionHighlight = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    showSelectionHighlight = false
                }
            }
            action()
        }) {
            VStack(spacing: 2) {
                if let label = topLabel {
                    Text(label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(isSelected ? Theme.background : Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Text(formattedOdds)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(isSelected ? Theme.background : Theme.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .background(
                Group {
                    if isSelected {
                        LinearGradient(
                            colors: [Theme.accent, Theme.accentSecondary.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    } else {
                        LinearGradient(
                            colors: [Theme.elevatedBackground, Theme.elevatedBackground.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall)
                    .stroke(
                        isSelected
                            ? LinearGradient(
                                colors: [Theme.accent, Theme.accentSecondary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(
                                colors: [Theme.border.opacity(0.6), Theme.border.opacity(0.3)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall)
                    .fill(
                        RadialGradient(
                            colors: [Theme.accent.opacity(showSelectionHighlight ? 0.6 : 0), Theme.accent.opacity(0)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 50
                        )
                    )
                    .animation(.easeOut(duration: 0.4), value: showSelectionHighlight)
            )
            .shadow(
                color: isSelected ? Theme.accent.opacity(0.5) : Color.clear,
                radius: isSelected ? 8 : 0,
                x: 0,
                y: 0
            )
            .scaleEffect(isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
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
