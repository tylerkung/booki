import SwiftUI
import SwiftData

/// Detail view for displaying comprehensive ticket information
struct TicketDetailView: View {
    @Query private var events: [Event]

    let ticket: Ticket

    // MARK: - Computed Properties

    /// Status color based on ticket combined status
    private var statusColor: Color {
        switch ticket.combinedStatus {
        case .pending: return Theme.warning
        case .accepted: return Theme.scheduled
        case .declined: return Theme.danger
        case .readyToGrade: return Theme.accentSecondary
        case .graded: return Theme.accentSecondary
        case .settled: return Theme.accent
        case .void: return Theme.textMuted
        }
    }

    /// Status display text
    private var statusText: String {
        switch ticket.combinedStatus {
        case .pending: return "Pending Approval"
        case .accepted: return "Open"
        case .readyToGrade: return "Awaiting Results"
        case .graded: return "Graded"
        case .settled: return "Settled"
        case .declined: return "Declined"
        case .void: return "Void"
        }
    }

    /// Formatted date when ticket was placed
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: ticket.createdAt)
    }

    /// Combined odds display for parlays
    private var combinedOddsDisplay: String {
        if ticket.isParlay {
            let combinedDecimal = ticket.bets.reduce(Decimal(1)) { result, bet in
                result * americanToDecimal(bet.odds)
            }
            // Convert back to American odds
            let americanOdds = decimalToAmerican(combinedDecimal)
            return americanOdds > 0 ? "+\(americanOdds)" : "\(americanOdds)"
        } else {
            let odds = ticket.bets.first?.odds ?? 0
            return odds > 0 ? "+\(odds)" : "\(odds)"
        }
    }

    /// Total return (stake + profit) if all bets win
    private var totalReturn: Decimal {
        ticket.totalStake + ticket.potentialPayout
    }

    /// Count of voided legs in this parlay
    private var voidedLegsCount: Int {
        ticket.bets.filter { $0.status == .void }.count
    }

    /// Count of pushed legs in this parlay
    private var pushedLegsCount: Int {
        ticket.bets.filter { $0.gradeResult == .push }.count
    }

    /// Whether this parlay has voided or pushed legs that affected the odds
    private var hasAdjustedOdds: Bool {
        ticket.isParlay && (voidedLegsCount > 0 || pushedLegsCount > 0)
    }

    /// Adjusted combined odds (excluding voided/pushed legs)
    private var adjustedCombinedOddsDisplay: String? {
        guard hasAdjustedOdds else { return nil }

        let validBets = ticket.bets.filter { bet in
            bet.status != .void && bet.gradeResult != .push
        }

        guard !validBets.isEmpty else { return nil }

        let combinedDecimal = validBets.reduce(Decimal(1)) { result, bet in
            result * americanToDecimal(bet.odds)
        }
        let americanOdds = decimalToAmerican(combinedDecimal)
        return americanOdds > 0 ? "+\(americanOdds)" : "\(americanOdds)"
    }

    /// Actual payout for settled tickets
    private var actualPayout: Decimal? {
        guard ticket.combinedStatus == .settled else { return nil }

        if ticket.isParlay {
            // For parlay, all bets must win to get payout
            let allWin = ticket.bets.allSatisfy { $0.gradeResult == .win }
            let anyPush = ticket.bets.contains { $0.gradeResult == .push }

            if allWin {
                return ticket.potentialPayout
            } else if anyPush && ticket.bets.filter({ $0.gradeResult != .push }).allSatisfy({ $0.gradeResult == .win }) {
                // Recalculate parlay odds excluding pushed legs
                let activeBets = ticket.bets.filter { $0.gradeResult != .push }
                if activeBets.isEmpty {
                    return Decimal.zero // All pushed, return stake (net zero profit)
                }
                var combinedMultiplier: Decimal = 1.0
                for bet in activeBets {
                    combinedMultiplier *= americanToDecimal(bet.odds)
                }
                return ticket.totalStake * combinedMultiplier - ticket.totalStake
            } else {
                return -ticket.totalStake // Lost
            }
        } else {
            // For singles, sum individual results
            return ticket.bets.reduce(Decimal.zero) { total, bet in
                guard let result = bet.gradeResult else { return total }
                switch result {
                case .win:
                    return total + LiabilityService.calculatePayout(stake: bet.stake, odds: bet.odds)
                case .loss:
                    return total - bet.stake
                case .push:
                    return total // No change
                }
            }
        }
    }

    // MARK: - Parlay Outcome Properties

    /// Whether this parlay is settled and should show outcome summary
    private var showParlayOutcome: Bool {
        ticket.isParlay && ticket.combinedStatus == .settled
    }

    /// Original combined decimal odds (all legs)
    private var originalCombinedDecimalOdds: Decimal {
        ticket.bets.reduce(Decimal(1)) { result, bet in
            result * americanToDecimal(bet.odds)
        }
    }

    /// Number of legs that were voided or pushed
    private var voidedOrPushedLegsCount: Int {
        voidedLegsCount + pushedLegsCount
    }

    /// Number of valid legs remaining after removing voided/pushed
    private var validLegsCount: Int {
        ticket.bets.count - voidedOrPushedLegsCount
    }

    /// Adjusted combined decimal odds (excluding voided/pushed legs)
    private var adjustedCombinedDecimalOdds: Decimal? {
        guard hasAdjustedOdds else { return nil }

        let validBets = ticket.bets.filter { bet in
            bet.status != .void && bet.gradeResult != .push
        }

        guard !validBets.isEmpty else { return nil }

        return validBets.reduce(Decimal(1)) { result, bet in
            result * americanToDecimal(bet.odds)
        }
    }

    /// Determine parlay outcome type for display
    private var parlayOutcomeType: ParlayOutcomeType? {
        guard showParlayOutcome else { return nil }

        // Check if any leg lost
        if ticket.bets.contains(where: { $0.gradeResult == .loss }) {
            return .loss
        }

        // Check if all non-voided/pushed legs won
        let validBets = ticket.bets.filter { bet in
            bet.status != .void && bet.gradeResult != .push
        }

        // If no valid legs remain, it's a push
        if validBets.isEmpty {
            return .push
        }

        // If all valid legs won, it's a win
        if validBets.allSatisfy({ $0.gradeResult == .win }) {
            return .win
        }

        // Otherwise it's a push (this shouldn't happen but handle edge case)
        return .push
    }

    /// The actual profit/loss amount for settled parlays
    private var parlaySettledAmount: Decimal {
        guard let outcomeType = parlayOutcomeType else { return Decimal.zero }
        let stake = ticket.bets.first?.stake ?? Decimal.zero

        switch outcomeType {
        case .win:
            // Calculate payout with adjusted odds if applicable
            let effectiveOdds = adjustedCombinedDecimalOdds ?? originalCombinedDecimalOdds
            return stake * effectiveOdds - stake
        case .loss:
            return -stake
        case .push:
            return Decimal.zero
        }
    }

    /// Enum for parlay outcome types
    private enum ParlayOutcomeType {
        case win
        case loss
        case push
    }

    // MARK: - Body

    var body: some View {
        List {
            // Parlay Outcome Section (for settled parlays - show prominently at top)
            if showParlayOutcome {
                parlayOutcomeSection
            }

            // Ticket Summary Section
            ticketSummarySection

            // Odds Breakdown Section (for parlays)
            if ticket.isParlay {
                oddsBreakdownSection
            }

            // Bets Section
            betsSection

            // Payout Section
            payoutSection

            // Details Section
            detailsSection
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(ticket.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections

    private var ticketSummarySection: some View {
        Section {
            // Ticket Type
            HStack {
                Text("Type")
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(ticket.typeLabel)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.textPrimary)
            }

            // Status
            HStack {
                Text("Status")
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(statusText)
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.background)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(statusColor)
                    .clipShape(Capsule())
            }

            // Total Stake
            HStack {
                Text("Total Stake")
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(formatCurrency(ticket.totalStake))
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.textPrimary)
            }

            // Combined Odds
            HStack {
                Text("Combined Odds")
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(combinedOddsDisplay)
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.gold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Theme.gold.opacity(0.15))
                    )
            }
        } header: {
            Text("TICKET SUMMARY")
                .font(Theme.caption)
                .fontWeight(.semibold)
                .tracking(1)
                .foregroundStyle(Theme.textMuted)
        }
        .listRowBackground(Theme.cardBackground)
    }

    private var oddsBreakdownSection: some View {
        Section {
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

                    let decimalOdds = americanToDecimal(bet.odds)
                    Text(String(format: "×%.3f", Double(truncating: decimalOdds as NSDecimalNumber)))
                        .font(Theme.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.scheduled)
                }
            }

            // Combined multiplier
            HStack {
                Text("Combined Multiplier")
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.textPrimary)

                Spacer()

                let combinedDecimal = ticket.bets.reduce(Decimal(1)) { result, bet in
                    result * americanToDecimal(bet.odds)
                }
                Text(String(format: "×%.3f", Double(truncating: combinedDecimal as NSDecimalNumber)))
                    .font(Theme.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.gold)
            }
            .padding(.top, 4)

            // Voided/Pushed legs indicator - shows when odds have been adjusted
            if hasAdjustedOdds {
                VStack(alignment: .leading, spacing: 6) {
                    // Voided legs info
                    if voidedLegsCount > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "nosign")
                                .foregroundStyle(Theme.textMuted)
                                .font(Theme.caption)
                            Text("\(voidedLegsCount) leg\(voidedLegsCount == 1 ? "" : "s") voided - odds adjusted")
                                .font(Theme.caption)
                                .foregroundStyle(Theme.textMuted)
                        }
                    }

                    // Pushed legs info
                    if pushedLegsCount > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "equal.circle")
                                .foregroundStyle(Theme.warning)
                                .font(Theme.caption)
                            Text("\(pushedLegsCount) leg\(pushedLegsCount == 1 ? "" : "s") pushed - odds adjusted")
                                .font(Theme.caption)
                                .foregroundStyle(Theme.warning)
                        }
                    }

                    // Adjusted odds display
                    if let adjustedOdds = adjustedCombinedOddsDisplay {
                        HStack {
                            Text("Adjusted Odds")
                                .font(Theme.caption)
                                .foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Text(adjustedOdds)
                                .font(Theme.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.accentSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Theme.accentSecondary.opacity(0.15))
                                )
                        }
                    }
                }
                .padding(.top, 8)
            }
        } header: {
            Text("ODDS BREAKDOWN")
                .font(Theme.caption)
                .fontWeight(.semibold)
                .tracking(1)
                .foregroundStyle(Theme.textMuted)
        }
        .listRowBackground(Theme.cardBackground)
    }

    private var betsSection: some View {
        Section {
            ForEach(ticket.bets) { bet in
                TicketDetailBetRowView(
                    bet: bet,
                    eventName: eventName(for: bet),
                    event: events.first(where: { $0.id.uuidString.lowercased() == bet.eventId.lowercased() })
                )
            }
        } header: {
            Text("BETS (\(ticket.bets.count))")
                .font(Theme.caption)
                .fontWeight(.semibold)
                .tracking(1)
                .foregroundStyle(Theme.textMuted)
        }
        .listRowBackground(Theme.cardBackground)
    }

    private var payoutSection: some View {
        Section {
            // Potential profit
            HStack {
                Text("Potential Profit")
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(formatCurrency(ticket.potentialPayout))
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.accent)
            }

            // Total return
            HStack {
                Text("Total Return if Win")
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(formatCurrency(totalReturn))
                    .font(Theme.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.accent)
            }

            // Actual payout (for settled tickets)
            if let payout = actualPayout {
                Divider()
                    .background(Theme.divider)

                HStack {
                    Text("Actual Result")
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text(formatProfitLoss(payout))
                        .font(Theme.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(payout >= 0 ? Theme.accent : Theme.danger)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill((payout >= 0 ? Theme.accent : Theme.danger).opacity(0.15))
                        )
                }
            }
        } header: {
            Text("PAYOUT")
                .font(Theme.caption)
                .fontWeight(.semibold)
                .tracking(1)
                .foregroundStyle(Theme.textMuted)
        }
        .listRowBackground(Theme.cardBackground)
    }

    private var detailsSection: some View {
        Section {
            // Placed date
            HStack {
                Text("Placed")
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(formattedDate)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.textSecondary)
            }

            // Ticket ID
            HStack {
                Text("Ticket ID")
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(String(ticket.id.uuidString.prefix(8)) + "...")
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.textMuted)
                    .font(Theme.footnote)
            }
        } header: {
            Text("DETAILS")
                .font(Theme.caption)
                .fontWeight(.semibold)
                .tracking(1)
                .foregroundStyle(Theme.textMuted)
        }
        .listRowBackground(Theme.cardBackground)
    }

    // MARK: - Parlay Outcome Section

    private var parlayOutcomeSection: some View {
        Section {
            VStack(spacing: 16) {
                // Large outcome badge
                parlayOutcomeBadge

                Divider()
                    .background(Theme.divider)

                // Calculation breakdown
                parlayCalculationBreakdown

                // Reduced parlay info (if applicable)
                if hasAdjustedOdds {
                    Divider()
                        .background(Theme.divider)
                    reducedParlayInfo
                }
            }
            .padding(.vertical, 8)
        } header: {
            Text("PARLAY OUTCOME")
                .font(Theme.caption)
                .fontWeight(.semibold)
                .tracking(1)
                .foregroundStyle(Theme.textMuted)
        }
        .listRowBackground(Theme.cardBackground)
    }

    /// Large outcome badge showing win/loss/push result
    private var parlayOutcomeBadge: some View {
        Group {
            if let outcomeType = parlayOutcomeType {
                HStack {
                    Spacer()

                    VStack(spacing: 4) {
                        // Outcome icon
                        Image(systemName: outcomeIcon(for: outcomeType))
                            .font(Theme.font(size: 28, weight: .bold))
                            .foregroundStyle(outcomeColor(for: outcomeType))

                        // Outcome label and amount
                        Text(outcomeLabel(for: outcomeType))
                            .font(Theme.title2)
                            .fontWeight(.black)
                            .foregroundStyle(outcomeColor(for: outcomeType))

                        // Amount
                        Text(formatProfitLoss(parlaySettledAmount))
                            .font(Theme.title1)
                            .fontWeight(.bold)
                            .foregroundStyle(outcomeColor(for: outcomeType))
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(outcomeColor(for: outcomeType).opacity(0.15))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(outcomeColor(for: outcomeType).opacity(0.3), lineWidth: 2)
                    )

                    Spacer()
                }
            }
        }
    }

    /// Calculation breakdown showing stake × odds = payout
    private var parlayCalculationBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Original odds row
            HStack {
                Text("Original Odds")
                    .font(Theme.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                let originalAmerican = decimalToAmerican(originalCombinedDecimalOdds)
                Text(originalAmerican > 0 ? "+\(originalAmerican)" : "\(originalAmerican)")
                    .font(Theme.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(hasAdjustedOdds ? Theme.textMuted : Theme.gold)
                    .strikethrough(hasAdjustedOdds, color: Theme.textMuted)
            }

            // Adjusted odds row (if applicable)
            if hasAdjustedOdds, let adjustedOdds = adjustedCombinedDecimalOdds {
                HStack {
                    Text("Adjusted Odds")
                        .font(Theme.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    let adjustedAmerican = decimalToAmerican(adjustedOdds)
                    Text(adjustedAmerican > 0 ? "+\(adjustedAmerican)" : "\(adjustedAmerican)")
                        .font(Theme.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.accentSecondary)
                }
            }

            Divider()
                .background(Theme.divider)

            // Calculation formula
            let stake = ticket.bets.first?.stake ?? Decimal.zero
            let effectiveOdds = adjustedCombinedDecimalOdds ?? originalCombinedDecimalOdds

            if parlayOutcomeType == .win {
                // Show calculation for wins
                VStack(alignment: .leading, spacing: 8) {
                    Text("Calculation")
                        .font(Theme.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.textMuted)

                    HStack(spacing: 4) {
                        Text("Stake")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textMuted)
                        Text(formatCurrency(stake))
                            .font(Theme.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.textPrimary)

                        Text("×")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textMuted)

                        Text(String(format: "%.3f", Double(truncating: effectiveOdds as NSDecimalNumber)))
                            .font(Theme.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.gold)

                        Text("=")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textMuted)

                        let totalReturn = stake * effectiveOdds
                        Text(formatCurrency(totalReturn))
                            .font(Theme.subheadline)
                            .fontWeight(.bold)
                            .foregroundStyle(Theme.accent)
                    }

                    HStack {
                        Text("Profit:")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textMuted)
                        Text(formatProfitLoss(parlaySettledAmount))
                            .font(Theme.subheadline)
                            .fontWeight(.bold)
                            .foregroundStyle(Theme.accent)
                    }
                }
            } else if parlayOutcomeType == .loss {
                // Show stake lost
                HStack {
                    Text("Stake Lost")
                        .font(Theme.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text(formatCurrency(stake))
                        .font(Theme.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.danger)
                }
            } else {
                // Push - stake returned
                HStack {
                    Text("Stake Returned")
                        .font(Theme.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text(formatCurrency(stake))
                        .font(Theme.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.warning)
                }
            }
        }
    }

    /// Info about reduced parlay when legs were voided/pushed
    private var reducedParlayInfo: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(Theme.accentSecondary)
                    .font(Theme.caption)
                Text("Parlay Adjusted")
                    .font(Theme.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.accentSecondary)
            }

            Text("Originally \(ticket.bets.count) legs, \(voidedOrPushedLegsCount) \(voidedOrPushedLegsCount == 1 ? "was" : "were") \(reducedLegDescription), settled as \(validLegsCount)-leg parlay")
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    /// Description of what happened to removed legs
    private var reducedLegDescription: String {
        if voidedLegsCount > 0 && pushedLegsCount > 0 {
            return "voided/pushed"
        } else if voidedLegsCount > 0 {
            return "voided"
        } else {
            return "pushed"
        }
    }

    // MARK: - Outcome Helpers

    private func outcomeIcon(for outcome: ParlayOutcomeType) -> String {
        switch outcome {
        case .win: return "checkmark.circle.fill"
        case .loss: return "xmark.circle.fill"
        case .push: return "equal.circle.fill"
        }
    }

    private func outcomeColor(for outcome: ParlayOutcomeType) -> Color {
        switch outcome {
        case .win: return Theme.accent
        case .loss: return Theme.danger
        case .push: return Theme.warning
        }
    }

    private func outcomeLabel(for outcome: ParlayOutcomeType) -> String {
        switch outcome {
        case .win: return "WON"
        case .loss: return "LOST"
        case .push: return "PUSHED"
        }
    }

    // MARK: - Helpers

    private func eventName(for bet: Bet) -> String {
        if let event = events.first(where: { $0.id.uuidString.lowercased() == bet.eventId.lowercased() }) {
            return "\(event.awayTeam) @ \(event.homeTeam)"
        }
        return "Event \(bet.eventId.prefix(8))"
    }

    private func americanToDecimal(_ odds: Int) -> Decimal {
        if odds > 0 {
            return 1 + Decimal(odds) / 100
        } else {
            return 1 + 100 / Decimal(abs(odds))
        }
    }

    private func decimalToAmerican(_ decimal: Decimal) -> Int {
        if decimal >= 2 {
            return Int(truncating: ((decimal - 1) * 100) as NSDecimalNumber)
        } else {
            return Int(truncating: (-100 / (decimal - 1)) as NSDecimalNumber)
        }
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }

    private func formatProfitLoss(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        let absValue = abs(value)
        let formatted = formatter.string(from: absValue as NSDecimalNumber) ?? "$\(absValue)"
        if value > 0 {
            return "+\(formatted)"
        } else if value < 0 {
            return "-\(formatted)"
        } else {
            return formatted
        }
    }
}

// MARK: - Ticket Detail Bet Row View

/// Row view for displaying a single bet with comprehensive details in TicketDetailView
struct TicketDetailBetRowView: View {
    let bet: Bet
    let eventName: String
    let event: Event?

    // MARK: - Computed Properties

    private var formattedOdds: String {
        bet.odds > 0 ? "+\(bet.odds)" : "\(bet.odds)"
    }

    private var formattedStake: String {
        formatCurrency(bet.stake)
    }

    private var statusColor: Color {
        switch bet.status {
        case .pending: return Theme.warning
        case .accepted, .readyToGrade: return Theme.scheduled
        case .declined: return Theme.danger
        case .graded, .settled:
            if let result = bet.gradeResult {
                switch result {
                case .win: return Theme.accent
                case .loss: return Theme.danger
                case .push: return Theme.warning
                }
            }
            return Theme.accent
        case .void: return Theme.textMuted
        }
    }

    private var statusText: String {
        // Show grade result if available (even for graded but not settled)
        if let result = bet.gradeResult {
            return result.rawValue.capitalized
        }
        switch bet.status {
        case .pending: return "Pending"
        case .accepted: return "Open"
        case .readyToGrade: return "Awaiting Result"
        case .graded, .settled:
            return bet.status.rawValue.capitalized
        case .declined: return "Declined"
        case .void: return "Void"
        }
    }

    /// Whether this leg is pending grading result
    private var isPendingResult: Bool {
        bet.gradeResult == nil && (bet.status == .accepted || bet.status == .readyToGrade)
    }

    private var formattedBetDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: bet.createdAt)
    }

    /// Potential payout for this individual bet
    private var potentialPayout: Decimal {
        LiabilityService.calculatePayout(stake: bet.stake, odds: bet.odds)
    }

    /// Actual payout for settled bets
    private var actualPayout: Decimal? {
        guard bet.status == .settled, let result = bet.gradeResult else { return nil }
        switch result {
        case .win:
            return potentialPayout
        case .loss:
            return -bet.stake
        case .push:
            return Decimal.zero
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Row 1: Event name and status
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(eventName)
                        .font(Theme.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.textPrimary)

                    if let event = event {
                        Text("\(event.sport) • \(event.league)")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textMuted)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    // Grade status badge
                    Text(statusText)
                        .font(Theme.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.background)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(statusColor)
                        .clipShape(Capsule())

                    // Show muted text for pending legs
                    if isPendingResult {
                        Text("Awaiting Result")
                            .font(Theme.caption2)
                            .foregroundStyle(Theme.textMuted)
                            .italic()
                    }
                }
            }

            // Row 2: Market and Selection
            HStack(spacing: 8) {
                Text(bet.market)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textMuted)

                Text("•")
                    .foregroundStyle(Theme.textMuted)

                Text(bet.side)
                    .font(Theme.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.textSecondary)

                Text(formattedOdds)
                    .font(Theme.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.gold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Theme.gold.opacity(0.15))
                    )
            }

            // Row 3: Stake and Payout
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Stake")
                        .font(Theme.caption2)
                        .foregroundStyle(Theme.textMuted)
                    Text(formattedStake)
                        .font(Theme.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.textPrimary)
                }

                Spacer()

                if let payout = actualPayout {
                    // Settled - show actual result
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Result")
                            .font(Theme.caption2)
                            .foregroundStyle(Theme.textMuted)
                        Text(formatProfitLoss(payout))
                            .font(Theme.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(payout >= 0 ? Theme.accent : Theme.danger)
                    }
                } else {
                    // Not settled - show potential
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("To Win")
                            .font(Theme.caption2)
                            .foregroundStyle(Theme.textMuted)
                        Text(formatCurrency(potentialPayout))
                            .font(Theme.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.accent)
                    }
                }
            }

            // Row 4: Event details (if available)
            if let event = event {
                Divider()
                    .background(Theme.divider)

                HStack {
                    // Event start time
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Event Time")
                            .font(Theme.caption2)
                            .foregroundStyle(Theme.textMuted)
                        Text(formatEventDate(event.startTime))
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    Spacer()

                    // Event status and score
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(event.status.rawValue.capitalized)
                            .font(Theme.caption2)
                            .foregroundStyle(eventStatusColor(event.status))

                        if let score = event.finalScore {
                            Text(score)
                                .font(Theme.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.gold)
                        }
                    }
                }
            }

            // Row 5: Timestamps
            Divider()
                .background(Theme.divider)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Placed")
                        .font(Theme.caption2)
                        .foregroundStyle(Theme.textMuted)
                    Text(formattedBetDate)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer()

                if bet.status == .graded || bet.status == .settled {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(bet.status == .settled ? "Settled" : "Graded")
                            .font(Theme.caption2)
                            .foregroundStyle(Theme.textMuted)
                        // Note: We don't have graded/settled timestamps in the model
                        // so we show the status instead
                        if let result = bet.gradeResult {
                            Text(result.rawValue.capitalized)
                                .font(Theme.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(statusColor)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }

    private func formatProfitLoss(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        let absValue = abs(value)
        let formatted = formatter.string(from: absValue as NSDecimalNumber) ?? "$\(absValue)"
        if value > 0 {
            return "+\(formatted)"
        } else if value < 0 {
            return "-\(formatted)"
        } else {
            return formatted
        }
    }

    private func formatEventDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func eventStatusColor(_ status: EventStatus) -> Color {
        switch status {
        case .scheduled: return Theme.scheduled
        case .live: return Theme.accent
        case .final: return Theme.finalStatus
        case .postponed: return Theme.warning
        case .canceled: return Theme.danger
        }
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
