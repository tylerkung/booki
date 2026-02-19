import SwiftUI
import SwiftData

/// Represents a grouped ticket containing multiple bets placed together
struct Ticket: Identifiable {
    let id: UUID  // ticketId
    let bets: [Bet]

    /// Earliest bet creation date (used for sorting)
    var createdAt: Date {
        bets.map(\.createdAt).min() ?? Date()
    }

    /// Total stake for the ticket
    /// For parlays: all legs share the same stake, so use first leg's stake
    /// For singles: sum individual stakes (though typically only one bet)
    var totalStake: Decimal {
        // Check if this is a parlay (either by bet count or explicit isParlay flag)
        if isParlay || (bets.first?.isParlay == true) {
            return bets.first?.stake ?? 0
        }
        return bets.reduce(0) { $0 + $1.stake }
    }

    /// Whether this is a parlay (multiple bets) or singles
    var isParlay: Bool {
        bets.count > 1
    }

    /// Display label for ticket type
    var typeLabel: String {
        if isParlay {
            return "Multi-Pick (\(bets.count) legs)"
        } else {
            return "Single"
        }
    }

    /// Display name for the ticket
    /// - Single bets: "Lakers ML -150" or "OKC -6.5 (-110)"
    /// - Parlays: "3-leg parlay +450"
    var displayName: String {
        if isParlay {
            let combinedOdds = combinedAmericanOdds
            let oddsString = combinedOdds > 0 ? "+\(combinedOdds)" : "\(combinedOdds)"
            return "\(bets.count)-leg multi-pick \(oddsString)"
        } else if let bet = bets.first {
            let oddsString = bet.odds > 0 ? "+\(bet.odds)" : "\(bet.odds)"
            return "\(bet.side) \(oddsString)"
        } else {
            return "Single"
        }
    }

    /// Combined American odds for parlays
    var combinedAmericanOdds: Int {
        let combinedDecimal = bets.reduce(Decimal(1)) { result, bet in
            result * americanToDecimal(bet.odds)
        }
        return decimalToAmerican(combinedDecimal)
    }

    private func decimalToAmerican(_ decimal: Decimal) -> Int {
        if decimal >= 2 {
            return Int(truncating: ((decimal - 1) * 100) as NSDecimalNumber)
        } else {
            return Int(truncating: (-100 / (decimal - 1)) as NSDecimalNumber)
        }
    }

    /// Combined status for the ticket
    var combinedStatus: BetStatus {
        // If any bet is void, ticket is void
        if bets.contains(where: { $0.status == .void }) {
            return .void
        }
        // If any bet is declined, ticket is declined
        if bets.contains(where: { $0.status == .declined }) {
            return .declined
        }
        // If any bet is pending, ticket is pending
        if bets.contains(where: { $0.status == .pending }) {
            return .pending
        }
        // If any bet is accepted (not yet ready to grade), ticket is accepted
        if bets.contains(where: { $0.status == .accepted }) {
            return .accepted
        }
        // If any bet is readyToGrade, ticket is readyToGrade
        if bets.contains(where: { $0.status == .readyToGrade }) {
            return .readyToGrade
        }
        // If any bet is graded (not yet settled), ticket is graded
        if bets.contains(where: { $0.status == .graded }) {
            return .graded
        }
        // All bets are settled
        return .settled
    }

    /// Calculate total potential payout for the ticket
    var potentialPayout: Decimal {
        if isParlay {
            // For parlays, multiply all decimal odds together then apply to total stake
            // But since we have American odds, we need to convert
            var combinedMultiplier: Decimal = 1.0
            for bet in bets {
                let decimalOdds = americanToDecimal(bet.odds)
                combinedMultiplier *= decimalOdds
            }
            // Use the first bet's stake (all legs share the stake in a parlay)
            let stake = bets.first?.stake ?? 0
            return stake * combinedMultiplier - stake  // profit only
        } else {
            // For singles, sum individual potential payouts
            return bets.reduce(Decimal.zero) { total, bet in
                total + LiabilityService.calculatePayout(stake: bet.stake, odds: bet.odds)
            }
        }
    }

    /// Convert American odds to decimal odds
    private func americanToDecimal(_ odds: Int) -> Decimal {
        if odds > 0 {
            return 1 + Decimal(odds) / 100
        } else {
            return 1 + 100 / Decimal(abs(odds))
        }
    }
}

/// View for players to track their submitted bets and their status
struct TrackView: View {
    @Query private var allBets: [Bet]
    @Query private var events: [Event]

    let player: Player

    // MARK: - Computed Properties

    /// All bets for this player, sorted by creation date (newest first)
    private var playerBets: [Bet] {
        allBets.filter { $0.player?.id == player.id }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Group bets by ticketId and sort by most recent first
    private var tickets: [Ticket] {
        let grouped = Dictionary(grouping: playerBets) { $0.ticketId }
        return grouped.map { ticketId, bets in
            Ticket(id: ticketId, bets: bets.sorted { $0.createdAt < $1.createdAt })
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Body

    var body: some View {
        List {
            // Tickets Section
            ticketsSection
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationBarHidden(true)
    }

    // MARK: - Section Views

    @ViewBuilder
    private var ticketsSection: some View {
        if tickets.isEmpty {
            Section {
                ContentUnavailableView(
                    "No Picks Yet",
                    systemImage: "list.bullet.clipboard",
                    description: Text("Your pick requests will appear here.")
                )
                .listRowBackground(Theme.cardBackground)
            }
        } else {
            ForEach(tickets) { ticket in
                Section {
                    // Individual bets within the ticket
                    ForEach(ticket.bets) { bet in
                        TicketBetRowView(
                            bet: bet,
                            eventName: eventName(for: bet),
                            league: league(for: bet)
                        )
                    }
                } header: {
                    NavigationLink {
                        TicketDetailView(ticket: ticket)
                    } label: {
                        HStack {
                            TicketHeaderView(
                                presenter: buildPresenter(for: ticket),
                                ticket: ticket
                            )
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(Theme.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.textMuted)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Helpers

    private func findEvent(for bet: Bet) -> Event? {
        events.first(where: { $0.id.uuidString.lowercased() == bet.eventId.lowercased() })
    }

    private func eventName(for bet: Bet) -> String {
        if let event = findEvent(for: bet) {
            return "\(event.awayTeam) @ \(event.homeTeam)"
        }
        if let desc = bet.eventDescription, !desc.isEmpty {
            return desc
        }
        return "Event \(bet.eventId.prefix(8))"
    }

    private func league(for bet: Bet) -> String? {
        if let event = findEvent(for: bet) {
            return event.league
        }
        return bet.sportLeague
    }

    private func buildPresenter(for ticket: Ticket) -> PickPresenter {
        if ticket.isParlay {
            return PickPresenter.multiPick(bets: ticket.bets, events: Array(events))
        } else if let bet = ticket.bets.first {
            return PickPresenter(bet: bet, event: findEvent(for: bet))
        } else {
            // Fallback — shouldn't happen
            return PickPresenter(bet: ticket.bets[0])
        }
    }
}

// MARK: - Ticket Header View

/// Header view displaying ticket summary information using PickCardCompact
struct TicketHeaderView: View {
    let presenter: PickPresenter
    let ticket: Ticket

    /// Count of graded legs in a parlay
    private var gradedLegsCount: Int {
        ticket.bets.filter { $0.gradeResult != nil }.count
    }

    /// Whether to show leg grading progress (only for parlays with some graded legs)
    private var showGradingProgress: Bool {
        ticket.isParlay && gradedLegsCount > 0 && gradedLegsCount < ticket.bets.count
    }

    /// Color for leg status dot
    private func legStatusColor(for bet: Bet) -> Color {
        if let result = bet.gradeResult {
            switch result {
            case .win: return Theme.accent
            case .loss: return Theme.danger
            case .push: return Theme.warning
            }
        }
        if bet.status == .void {
            return Theme.textMuted
        }
        return Theme.textMuted.opacity(0.5)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PickCardCompact(presenter: presenter)

            // Mini status dots for parlay legs
            if ticket.isParlay {
                HStack(spacing: 4) {
                    ForEach(ticket.bets) { bet in
                        Circle()
                            .fill(legStatusColor(for: bet))
                            .frame(width: 8, height: 8)
                    }
                }
            }

            // Show leg grading progress for parlays
            if showGradingProgress {
                Text("\(gradedLegsCount)/\(ticket.bets.count) legs graded")
                    .font(Theme.caption2)
                    .foregroundStyle(Theme.accentSecondary)
            }
        }
        .textCase(nil)
        .padding(.vertical, 4)
    }
}

// MARK: - Ticket Bet Row View

/// Row view for displaying a single bet within a ticket using SelectionRow
struct TicketBetRowView: View {
    let bet: Bet
    let eventName: String
    var league: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SelectionRow(
                selectionLabel: bet.side,
                odds: bet.odds,
                eventName: eventName,
                league: league,
                gradeResult: bet.gradeResult
            )

            // Show pending indicator for legs awaiting result
            if bet.gradeResult == nil && (bet.status == .accepted || bet.status == .readyToGrade) {
                Text("Awaiting Result")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textMuted)
                    .italic()
            }
        }
        .padding(.vertical, 2)
        .listRowBackground(Theme.cardBackground)
    }
}

#Preview {
    NavigationStack {
        TrackView(player: Player(
            name: "Test Player",
            email: "test@example.com",
            creditLimit: 1000
        ))
    }
    .modelContainer(for: [Player.self, Bet.self, LedgerEntry.self, Event.self], inMemory: true)
}
