import SwiftUI
import SwiftData

/// Detail view for displaying comprehensive ticket information
struct TicketDetailView: View {
    @Query private var events: [Event]
    @AppStorage("playerOddsFormat") private var oddsFormat: String = OddsFormat.american.rawValue

    let ticket: Ticket

    // MARK: - Computed Properties

    private var selectedOddsFormat: OddsFormat {
        OddsFormat(rawValue: oddsFormat) ?? .american
    }

    private var presenter: PickPresenter {
        if ticket.isParlay {
            return PickPresenter.multiPick(bets: ticket.bets, events: Array(events))
        } else if let bet = ticket.bets.first {
            let event = events.first(where: { $0.id.uuidString.lowercased() == bet.eventId.lowercased() })
            return PickPresenter(bet: bet, event: event)
        } else {
            return PickPresenter(bet: ticket.bets[0])
        }
    }

    private var isSettled: Bool {
        switch presenter.settlementStatus {
        case .won, .lost, .push, .void, .cancelled: return true
        case .open: return false
        }
    }

    private var combinedDecimalOdds: Decimal {
        ticket.bets.reduce(Decimal(1)) { result, bet in
            result * PickPresenter.americanToDecimal(bet.odds)
        }
    }

    private var voidedLegsCount: Int {
        ticket.bets.filter { $0.status == .void }.count
    }

    private var pushedLegsCount: Int {
        ticket.bets.filter { $0.gradeResult == .push }.count
    }

    private var hasAdjustedOdds: Bool {
        ticket.isParlay && (voidedLegsCount > 0 || pushedLegsCount > 0)
    }

    private var adjustedDecimalOdds: Decimal? {
        guard hasAdjustedOdds else { return nil }
        let validBets = ticket.bets.filter { $0.status != .void && $0.gradeResult != .push }
        guard !validBets.isEmpty else { return nil }
        return validBets.reduce(Decimal(1)) { result, bet in
            result * PickPresenter.americanToDecimal(bet.odds)
        }
    }

    private var totalReturn: Decimal {
        switch presenter.settlementStatus {
        case .won: return presenter.stake + presenter.profit
        case .lost: return .zero
        case .push, .void, .cancelled: return presenter.stake
        case .open: return presenter.stake + presenter.profit
        }
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: ticket.createdAt)
    }

    private var isTicketSettled: Bool {
        ticket.combinedStatus == .settled
    }

    // MARK: - Odds Formatting

    /// Format odds for a single leg based on user preference
    private func formatOddsForLeg(_ americanOdds: Int) -> String {
        let decimal = PickPresenter.americanToDecimal(americanOdds)
        return formatOddsValue(american: americanOdds, decimal: decimal)
    }

    /// Format combined odds (from decimal) based on user preference
    private func formatCombinedOdds(_ decimal: Decimal) -> String {
        let american = PickPresenter.decimalToAmerican(decimal)
        return formatOddsValue(american: american, decimal: decimal)
    }

    private func formatOddsValue(american: Int, decimal: Decimal) -> String {
        switch selectedOddsFormat {
        case .american:
            return american > 0 ? "+\(american)" : "\(american)"
        case .decimal:
            return String(format: "%.2f", Double(truncating: decimal as NSDecimalNumber))
        case .fractional:
            return decimalToFractional(decimal)
        }
    }

    private func decimalToFractional(_ decimal: Decimal) -> String {
        let profit = Double(truncating: (decimal - 1) as NSDecimalNumber)
        guard profit > 0 else { return "0/1" }
        // Find closest simple fraction
        let denominators = [1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 15, 20, 25, 33, 40, 50, 100]
        var bestNum = Int(round(profit))
        var bestDen = 1
        var bestError = Swift.abs(profit - Double(bestNum))
        for den in denominators {
            let num = Int(round(profit * Double(den)))
            let error = Swift.abs(profit - Double(num) / Double(den))
            if error < bestError {
                bestNum = num
                bestDen = den
                bestError = error
            }
            if bestError < 0.001 { break }
        }
        // Simplify
        let g = gcd(bestNum, bestDen)
        return "\(bestNum / g)/\(bestDen / g)"
    }

    private func gcd(_ a: Int, _ b: Int) -> Int {
        b == 0 ? a : gcd(b, a % b)
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                heroCard
                financialsCard
                if ticket.isParlay {
                    oddsBreakdownCard
                }
                activityCard
            }
            .padding(16)
        }
        .background(Theme.background)
        .navigationTitle(ticket.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 1. Hero Card

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            heroHeader
                .padding(12)

            if ticket.isParlay {
                ForEach(ticket.bets) { bet in
                    Divider().background(Theme.divider)
                    heroLegRow(bet: bet)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
            }
        }
        .background(cardBackground)
    }

    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
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

            if !presenter.contextLine.isEmpty {
                Text(presenter.contextLine)
                    .font(Theme.bodyFont(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                Text(presenter.stakeLine)
                    .font(Theme.bodyFont(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                Text(presenter.profitLine)
                    .font(Theme.bodyFont(size: 13, weight: .medium))
                    .foregroundStyle(presenter.profitColor)
            }

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
    }

    private func heroLegRow(bet: Bet) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SelectionRow(
                selectionLabel: bet.side,
                odds: bet.odds,
                eventName: eventName(for: bet),
                league: eventLeague(for: bet),
                gradeResult: bet.gradeResult
            )

            if bet.gradeResult == nil && (bet.status == .accepted || bet.status == .readyToGrade) {
                Text("Awaiting Result")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textMuted)
                    .italic()
            }
        }
    }

    // MARK: - 2. Financials Card

    private var financialsCard: some View {
        VStack(spacing: 0) {
            sectionHeader("FINANCIALS")

            VStack(spacing: 10) {
                labeledRow(label: "Stake", value: formatCurrency(presenter.stake))

                // Combined odds in user's preferred format
                let oddsLabel = ticket.isParlay ? "Combined Odds" : "Odds"
                if ticket.isParlay {
                    labeledRow(label: oddsLabel, value: formatCombinedOdds(combinedDecimalOdds), valueColor: Theme.gold)
                } else {
                    labeledRow(label: oddsLabel, value: formatOddsForLeg(ticket.bets.first?.odds ?? 0), valueColor: Theme.gold)
                }

                if hasAdjustedOdds, let adjDec = adjustedDecimalOdds {
                    labeledRow(label: "Adjusted Odds", value: formatCombinedOdds(adjDec), valueColor: Theme.accentSecondary)
                }

                Divider().background(Theme.divider)

                if isSettled {
                    labeledRow(label: "Profit", value: formattedProfit, valueColor: presenter.profitColor)
                    labeledRow(label: "Total Return", value: formatCurrency(totalReturn))
                } else {
                    labeledRow(label: "Potential", value: "+\(formatCurrency(presenter.profit))", valueColor: Theme.accent)
                    labeledRow(label: "Total Return", value: formatCurrency(totalReturn))
                }
            }
            .padding(12)
        }
        .background(cardBackground)
    }

    // MARK: - 3. Odds Breakdown (multi-pick only)

    private var oddsBreakdownCard: some View {
        VStack(spacing: 0) {
            sectionHeader("ODDS BREAKDOWN")

            VStack(spacing: 8) {
                ForEach(ticket.bets) { bet in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(bet.side)
                                .font(Theme.subheadline)
                                .foregroundStyle(Theme.textPrimary)
                            Text(eventName(for: bet))
                                .font(Theme.caption)
                                .foregroundStyle(Theme.textMuted)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(formatOddsForLeg(bet.odds))
                            .font(Theme.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.scheduled)
                    }
                }

                Divider().background(Theme.divider)

                HStack {
                    Text("Combined")
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text(formatCombinedOdds(combinedDecimalOdds))
                        .font(Theme.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.gold)
                }
            }
            .padding(12)
        }
        .background(cardBackground)
    }

    // MARK: - 4. Activity Card

    private var activityCard: some View {
        VStack(spacing: 0) {
            sectionHeader("ACTIVITY")

            VStack(spacing: 10) {
                labeledRow(label: "Placed", value: formattedDate, valueColor: Theme.textSecondary)

                labeledRow(
                    label: "Ticket ID",
                    value: String(ticket.id.uuidString.prefix(8)) + "...",
                    valueColor: Theme.textMuted
                )

                if isTicketSettled {
                    labeledRow(label: "Status", value: "Reconciled", valueColor: Theme.accent)
                }
            }
            .padding(12)
        }
        .background(cardBackground)
    }

    // MARK: - Shared Components

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.cardBackground)
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.border, lineWidth: 0.5)
        }
        .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(Theme.caption)
                .fontWeight(.semibold)
                .tracking(1)
                .foregroundStyle(Theme.textMuted)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func labeledRow(label: String, value: String, valueColor: Color = Theme.textPrimary) -> some View {
        HStack {
            Text(label)
                .font(Theme.bodyFont(size: 14))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(Theme.bodyFont(size: 14, weight: .medium))
                .foregroundStyle(valueColor)
        }
    }

    // MARK: - Helpers

    private var formattedProfit: String {
        if presenter.profit > 0 {
            return "+\(formatCurrency(presenter.profit))"
        } else if presenter.profit < 0 {
            return "-\(formatCurrency(abs(presenter.profit)))"
        } else {
            return formatCurrency(0)
        }
    }

    private func abs(_ value: Decimal) -> Decimal {
        value < 0 ? -value : value
    }

    private func legStatusColor(for bet: Bet) -> Color {
        if let result = bet.gradeResult {
            switch result {
            case .win: return Theme.accent
            case .loss: return Theme.danger
            case .push: return Theme.warning
            }
        }
        if bet.status == .void { return Theme.textMuted }
        return Theme.textMuted.opacity(0.5)
    }

    private func eventName(for bet: Bet) -> String {
        if let event = events.first(where: { $0.id.uuidString.lowercased() == bet.eventId.lowercased() }) {
            return "\(event.awayTeam) @ \(event.homeTeam)"
        }
        if let desc = bet.eventDescription, !desc.isEmpty {
            return desc
        }
        return "Event \(bet.eventId.prefix(8))"
    }

    private func eventLeague(for bet: Bet) -> String? {
        if let event = events.first(where: { $0.id.uuidString.lowercased() == bet.eventId.lowercased() }) {
            return event.league
        }
        return bet.sportLeague
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }
}

#Preview {
    NavigationStack {
        TicketDetailView(ticket: Ticket(
            id: UUID(),
            bets: [
                Bet(
                    eventId: "123",
                    market: "Spread",
                    side: "Lakers -5.5",
                    odds: -110,
                    stake: 100,
                    status: .settled,
                    gradeResult: .win
                ),
                Bet(
                    eventId: "456",
                    market: "Moneyline",
                    side: "Celtics",
                    odds: 150,
                    stake: 100,
                    status: .settled,
                    gradeResult: .win
                )
            ]
        ))
    }
    .modelContainer(for: [Event.self], inMemory: true)
}
