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
        let d = Double(truncating: decimal as NSDecimalNumber)
        if d >= 2 {
            return Int((d - 1) * 100)
        } else if d > 1 {
            return Int(-100.0 / (d - 1))
        } else {
            return 0
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

/// Filter options for the Track tab
private enum TrackFilter: String, CaseIterable {
    case all = "All"
    case open = "Open"
    case won = "Won"
    case lost = "Lost"
    case pushed = "Pushed"
}

/// View for players to track their submitted bets and their status
struct TrackView: View {
    @Environment(SyncService.self) private var syncService
    @Query private var allBets: [Bet]
    @Query private var events: [Event]
    @State private var selectedFilter: TrackFilter = .all

    let player: Player

    // MARK: - Computed Properties

    /// All bets for this player, sorted by creation date (newest first)
    private var playerBets: [Bet] {
        return allBets.filter { $0.player?.id == player.id }
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

    // MARK: - Filtering

    private var openStatuses: Set<BetStatus> {
        [.pending, .accepted, .readyToGrade, .graded]
    }

    private func matchesFilter(_ ticket: Ticket) -> Bool {
        switch selectedFilter {
        case .all:
            return true
        case .open:
            return openStatuses.contains(ticket.combinedStatus)
        case .won:
            return ticket.combinedStatus == .settled && ticket.bets.allSatisfy { $0.gradeResult == .win || $0.gradeResult == .push }
                && ticket.bets.contains(where: { $0.gradeResult == .win })
        case .lost:
            return ticket.combinedStatus == .settled && ticket.bets.contains(where: { $0.gradeResult == .loss })
        case .pushed:
            return ticket.combinedStatus == .settled && ticket.bets.allSatisfy { $0.gradeResult == .push }
        }
    }

    private var filteredTickets: [Ticket] {
        tickets.filter { matchesFilter($0) }
    }

    private func countForFilter(_ filter: TrackFilter) -> Int {
        tickets.filter { ticket in
            switch filter {
            case .all: return true
            case .open: return openStatuses.contains(ticket.combinedStatus)
            case .won:
                return ticket.combinedStatus == .settled && ticket.bets.allSatisfy { $0.gradeResult == .win || $0.gradeResult == .push }
                    && ticket.bets.contains(where: { $0.gradeResult == .win })
            case .lost:
                return ticket.combinedStatus == .settled && ticket.bets.contains(where: { $0.gradeResult == .loss })
            case .pushed:
                return ticket.combinedStatus == .settled && ticket.bets.allSatisfy { $0.gradeResult == .push }
            }
        }.count
    }

    // MARK: - Stats

    private var settledBets: [Bet] {
        playerBets.filter { $0.status == .settled }
    }

    private var wins: Int {
        settledBets.filter { $0.gradeResult == .win }.count
    }

    private var losses: Int {
        settledBets.filter { $0.gradeResult == .loss }.count
    }

    private var pushes: Int {
        settledBets.filter { $0.gradeResult == .push }.count
    }

    private var totalStaked: Decimal {
        playerBets.reduce(Decimal.zero) { $0 + $1.stake }
    }

    private var netPerformance: Decimal {
        settledBets.reduce(Decimal.zero) { total, bet in
            guard let result = bet.gradeResult else { return total }
            switch result {
            case .win:
                return total + LiabilityService.calculatePayout(stake: bet.stake, odds: bet.odds)
            case .loss:
                return total - bet.stake
            case .push:
                return total
            }
        }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            if tickets.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "ticket")
                        .font(.system(size: 48))
                        .foregroundStyle(Theme.textMuted)

                    Text("No Picks Yet")
                        .font(Theme.headline)
                        .foregroundStyle(Theme.textPrimary)

                    Text("Your pick history will appear here.")
                        .font(Theme.body)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 120)
            } else {
                VStack(spacing: 12) {
                    TrackSummaryCard(
                        wins: wins,
                        losses: losses,
                        pushes: pushes,
                        totalStaked: totalStaked,
                        netPerformance: netPerformance
                    )

                    TrackFilterChips(
                        selectedFilter: $selectedFilter,
                        countForFilter: countForFilter
                    )

                    ForEach(filteredTickets) { ticket in
                        NavigationLink {
                            TicketDetailView(ticket: ticket)
                        } label: {
                            TicketCardView(
                                presenter: buildPresenter(for: ticket),
                                ticket: ticket,
                                eventNameProvider: eventName,
                                leagueProvider: league
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
        .refreshable {
            await withCheckedContinuation { continuation in
                Task.detached {
                    await syncService.sync()
                    continuation.resume()
                }
            }
        }
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
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

// MARK: - Ticket Card View

/// Unified card that shows the pick header and (for multi-picks) the expanded legs
/// all within a single continuous card background.
struct TicketCardView: View {
    let presenter: PickPresenter
    let ticket: Ticket
    let eventNameProvider: (Bet) -> String
    let leagueProvider: (Bet) -> String?

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
        VStack(alignment: .leading, spacing: 0) {
            // Header section: title, status, stake, profit, chevron
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    // Title + Status Pill
                    HStack(alignment: .top) {
                        Text(presenter.title)
                            .font(Theme.headline)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(2)
                        Spacer()
                        StatusPill(
                            settlementStatus: presenter.settlementStatus,
                            workflowStatus: presenter.workflowStatus
                        )
                    }

                    // Context line
                    if !presenter.contextLine.isEmpty {
                        Text(presenter.contextLine)
                            .font(Theme.bodyFont(size: 13))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }

                    // Stake + Profit
                    HStack(spacing: 8) {
                        Text(presenter.stakeLine)
                            .font(Theme.bodyFont(size: 13))
                            .foregroundStyle(Theme.textSecondary)
                        Text(presenter.profitLine)
                            .font(Theme.bodyFont(size: 13, weight: .medium))
                            .foregroundStyle(presenter.profitColor)
                    }

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
                }

                Image(systemName: "chevron.right")
                    .font(Theme.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.textMuted)
                    .padding(.top, 4)
            }
            .padding(12)

            // Expanded legs for multi-picks only
            if ticket.isParlay {
                ForEach(ticket.bets) { bet in
                    Divider()
                        .background(Theme.divider)

                    VStack(alignment: .leading, spacing: 4) {
                        SelectionRow(
                            selectionLabel: bet.side,
                            odds: bet.odds,
                            eventName: eventNameProvider(bet),
                            league: leagueProvider(bet),
                            gradeResult: bet.gradeResult
                        )

                        if bet.gradeResult == nil && (bet.status == .accepted || bet.status == .readyToGrade) {
                            Text("Awaiting Result")
                                .font(Theme.caption)
                                .foregroundStyle(Theme.textMuted)
                                .italic()
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Theme.cardBackground)
                GeometryReader { geo in
                    Image("WaveBackground")
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .opacity(0.1)
                }
                .allowsHitTesting(false)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Theme.border, lineWidth: 0.5)
            }
        )
        .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Track Summary Card

private struct TrackSummaryCard: View {
    let wins: Int
    let losses: Int
    let pushes: Int
    let totalStaked: Decimal
    let netPerformance: Decimal

    private var performanceColor: Color {
        if netPerformance > 0 { return Theme.accent }
        if netPerformance < 0 { return Theme.danger }
        return Theme.textSecondary
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "$0.00"
    }

    var body: some View {
        VStack(spacing: 12) {
            // Record
            HStack {
                Text("Record")
                    .font(Theme.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("\(wins)-\(losses)-\(pushes)")
                    .font(Theme.headline)
                    .foregroundStyle(Theme.textPrimary)
            }

            Divider().background(Theme.divider)

            // Total Staked
            HStack {
                Text("Total Staked")
                    .font(Theme.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(formatCurrency(totalStaked))
                    .font(Theme.headline)
                    .foregroundStyle(Theme.textPrimary)
            }

            Divider().background(Theme.divider)

            // Net Performance
            HStack {
                Text("Net Performance")
                    .font(Theme.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(formatCurrency(netPerformance))
                    .font(Theme.headline)
                    .foregroundStyle(performanceColor)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.cardBackground)
        )
    }
}

// MARK: - Track Filter Chips

private struct TrackFilterChips: View {
    @Binding var selectedFilter: TrackFilter
    let countForFilter: (TrackFilter) -> Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TrackFilter.allCases, id: \.self) { filter in
                    let count = countForFilter(filter)
                    Button {
                        selectedFilter = filter
                    } label: {
                        Text("\(filter.rawValue) (\(count))")
                            .font(Theme.bodyFont(size: 13, weight: .medium))
                            .foregroundStyle(selectedFilter == filter ? Theme.background : Theme.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(selectedFilter == filter ? Theme.accent : Theme.elevatedBackground)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
        .padding(.horizontal, -16)
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
