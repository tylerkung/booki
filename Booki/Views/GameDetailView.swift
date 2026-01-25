import SwiftUI
import SwiftData

/// US-010: Game Detail View
/// US-011: Main Markets Section
/// Displays comprehensive game info with all available betting markets
/// Replaces MarketSelectionView for players with a more compact, sports-app style layout
struct GameDetailView: View {
    let player: Player
    let event: Event

    /// Bet slip manager for persistent selections
    @ObservedObject private var betSlipManager = BetSlipManager.shared

    /// Show bet slip sheet
    @State private var showingBetSlipSheet: Bool = false

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

    /// Check if a specific selection is in the bet slip
    private func isSelected(_ selection: BetSlipSelection) -> Bool {
        betSlipManager.contains(selection)
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
                    // US-011: Main Lines section
                    mainLinesSection

                    // Placeholder for US-012, US-013 content
                    // (Market categories and additional markets)
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
                // Spread market
                if let spread = spreadMarket {
                    mainMarketRow(
                        market: spread,
                        label: "Spread",
                        sideALabel: formatSpreadValue(spread.sideA),
                        sideBLabel: formatSpreadValue(spread.sideB)
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
    @ViewBuilder
    private func mainMarketRow(
        market: Market,
        label: String,
        sideALabel: String,
        sideBLabel: String
    ) -> some View {
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
                let selectionA = makeSelection(market: market, side: market.sideA, odds: market.oddsA)
                let descriptionA = "\(label): \(sideALabel)"

                CompactOddsButton(
                    topText: sideALabel,
                    odds: market.oddsA,
                    isSelected: isSelected(selectionA),
                    isDisabled: isEventLocked,
                    action: { handleOddsSelection(selectionA, marketDescription: descriptionA) }
                )
                .frame(maxWidth: .infinity)
                .frame(height: oddsButtonHeight)

                // Side B (home team / under)
                let selectionB = makeSelection(market: market, side: market.sideB, odds: market.oddsB)
                let descriptionB = "\(label): \(sideBLabel)"

                CompactOddsButton(
                    topText: sideBLabel,
                    odds: market.oddsB,
                    isSelected: isSelected(selectionB),
                    isDisabled: isEventLocked,
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
