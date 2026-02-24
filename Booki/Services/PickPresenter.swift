import SwiftUI

/// Canonical presentation model for displaying picks (bets) consistently across all views.
struct PickPresenter {

    // MARK: - Status Enums

    enum SettlementStatus: String {
        case open, won, lost, push, void, cancelled

        var label: String { rawValue.capitalized }
    }

    enum WorkflowStatus: String {
        case pending, approved, rejected
    }

    // MARK: - Selection Info (for multi-pick legs)

    struct SelectionInfo {
        let label: String
        let odds: Int
        let eventName: String
        let league: String?
        let gradeResult: GradeResult?
    }

    // MARK: - Properties

    let title: String
    let contextLine: String
    let stakeLine: String
    let profitLine: String
    let profitColor: Color
    let settlementStatus: SettlementStatus
    let workflowStatus: WorkflowStatus
    let isMultiPick: Bool
    let selections: [SelectionInfo]
    let stake: Decimal
    let profit: Decimal

    // MARK: - Private memberwise init (used by factory methods)

    private init(title: String, contextLine: String, stakeLine: String, profitLine: String,
                 profitColor: Color, settlementStatus: SettlementStatus, workflowStatus: WorkflowStatus,
                 isMultiPick: Bool, selections: [SelectionInfo], stake: Decimal, profit: Decimal) {
        self.title = title
        self.contextLine = contextLine
        self.stakeLine = stakeLine
        self.profitLine = profitLine
        self.profitColor = profitColor
        self.settlementStatus = settlementStatus
        self.workflowStatus = workflowStatus
        self.isMultiPick = isMultiPick
        self.selections = selections
        self.stake = stake
        self.profit = profit
    }

    // MARK: - Single Pick Init

    init(bet: Bet, event: Event? = nil, playerName: String? = nil) {
        self.isMultiPick = false
        self.stake = bet.stake
        self.selections = []

        // Title: "Houston Rockets -2.5 (-110)"
        let oddsStr = PickPresenter.formatOdds(bet.odds)
        self.title = "\(bet.side) (\(oddsStr))"

        // Context: "NBA · Houston @ Charlotte"
        var context = ""
        if let event = event {
            let league = event.league
            let matchup = event.awayTeam == "Outright" ? event.homeTeam : "\(event.awayTeam) @ \(event.homeTeam)"
            context = "\(league) · \(matchup)"
        } else if let desc = bet.eventDescription {
            if let league = bet.sportLeague {
                context = "\(league) · \(desc)"
            } else {
                context = desc
            }
        }
        if let name = playerName {
            context = context.isEmpty ? name : "\(name) · \(context)"
        }
        self.contextLine = context

        // Status mapping
        let (settlement, workflow) = PickPresenter.mapStatus(betStatus: bet.status, gradeResult: bet.gradeResult)
        self.settlementStatus = settlement
        self.workflowStatus = workflow

        // Financial
        let payout = LiabilityService.calculatePayout(stake: bet.stake, odds: bet.odds)
        self.stakeLine = "Stake: $\(PickPresenter.formatDecimal(bet.stake))"

        switch settlement {
        case .won:
            self.profit = payout
            self.profitLine = "Profit: +$\(PickPresenter.formatDecimal(payout))"
            self.profitColor = Theme.accent
        case .lost:
            self.profit = -bet.stake
            self.profitLine = "Loss: -$\(PickPresenter.formatDecimal(bet.stake))"
            self.profitColor = Theme.danger
        case .push, .void, .cancelled:
            self.profit = .zero
            self.profitLine = "Returned: $\(PickPresenter.formatDecimal(bet.stake))"
            self.profitColor = Theme.textSecondary
        case .open:
            self.profit = payout
            self.profitLine = "Potential: +$\(PickPresenter.formatDecimal(payout))"
            self.profitColor = Theme.accent
        }
    }

    // MARK: - Multi-Pick Factory

    static func multiPick(bets: [Bet], events: [Event], playerName: String? = nil) -> PickPresenter {
        let sortedBets = bets.sorted { $0.createdAt < $1.createdAt }
        let eventMap = Dictionary(uniqueKeysWithValues: events.map { ($0.id.uuidString.lowercased(), $0) })

        // Combined odds: multiply decimal odds of all legs
        let combinedDecimal = sortedBets.reduce(Decimal(1)) { result, bet in
            result * americanToDecimal(bet.odds)
        }
        let combinedAmerican = decimalToAmerican(combinedDecimal)
        let combinedOddsStr = formatOdds(combinedAmerican)

        // Title — parentheses around odds to match single pick format
        let title = "Multi-Pick · \(sortedBets.count) Selections (\(combinedOddsStr))"

        // Context — only show player name prefix for bookie views, no "Multi-Pick" redundancy
        let context = playerName ?? ""

        // Stake from first bet (parlay stake is identical on all legs)
        let stake = sortedBets.first?.stake ?? .zero

        // Settlement status from all legs
        let legStatuses = sortedBets.map { mapStatus(betStatus: $0.status, gradeResult: $0.gradeResult) }
        let settlement: SettlementStatus
        let workflow: WorkflowStatus

        if legStatuses.contains(where: { $0.1 == .rejected }) {
            settlement = .open; workflow = .rejected
        } else if legStatuses.contains(where: { $0.0 == .lost }) {
            settlement = .lost; workflow = .approved
        } else if legStatuses.allSatisfy({ $0.0 == .won }) {
            settlement = .won; workflow = .approved
        } else if legStatuses.allSatisfy({ $0.0 == .push || $0.0 == .void || $0.0 == .cancelled }) {
            // All non-active: push if all push, void otherwise
            if legStatuses.allSatisfy({ $0.0 == .push }) {
                settlement = .push; workflow = .approved
            } else {
                settlement = .void; workflow = .approved
            }
        } else if legStatuses.contains(where: { $0.1 == .pending }) {
            settlement = .open; workflow = .pending
        } else {
            settlement = .open; workflow = .approved
        }

        // Profit calculation
        let profit: Decimal
        let profitLine: String
        let profitColor: Color

        switch settlement {
        case .won:
            profit = stake * combinedDecimal - stake
            profitLine = "Profit: +$\(formatDecimal(profit))"
            profitColor = Theme.accent
        case .lost:
            profit = -stake
            profitLine = "Loss: -$\(formatDecimal(stake))"
            profitColor = Theme.danger
        case .push, .void, .cancelled:
            profit = .zero
            profitLine = "Returned: $\(formatDecimal(stake))"
            profitColor = Theme.textSecondary
        case .open:
            profit = stake * combinedDecimal - stake
            profitLine = "Potential: +$\(formatDecimal(profit))"
            profitColor = Theme.accent
        }

        // Build selections array
        let selections: [SelectionInfo] = sortedBets.map { bet in
            let event = eventMap[bet.eventId.lowercased()]
            let eventName: String
            let league: String?
            if let event = event {
                eventName = event.awayTeam == "Outright" ? event.homeTeam : "\(event.awayTeam) @ \(event.homeTeam)"
                league = event.league
            } else {
                eventName = bet.eventDescription ?? "Unknown"
                league = bet.sportLeague
            }
            return SelectionInfo(
                label: bet.side,
                odds: bet.odds,
                eventName: eventName,
                league: league,
                gradeResult: bet.gradeResult
            )
        }

        return PickPresenter(
            title: title,
            contextLine: context,
            stakeLine: "Stake: $\(formatDecimal(stake))",
            profitLine: profitLine,
            profitColor: profitColor,
            settlementStatus: settlement,
            workflowStatus: workflow,
            isMultiPick: true,
            selections: selections,
            stake: stake,
            profit: profit
        )
    }

    // MARK: - Status Mapping

    static func mapStatus(betStatus: BetStatus, gradeResult: GradeResult?) -> (SettlementStatus, WorkflowStatus) {
        switch betStatus {
        case .pending:
            return (.open, .pending)
        case .accepted, .readyToGrade:
            return (.open, .approved)
        case .graded, .settled:
            switch gradeResult {
            case .win:  return (.won, .approved)
            case .loss: return (.lost, .approved)
            case .push: return (.push, .approved)
            case .none: return (.open, .approved)
            }
        case .declined:
            return (.open, .rejected)
        case .void:
            return (.void, .approved)
        }
    }

    // MARK: - Helpers

    static func formatOdds(_ odds: Int) -> String {
        odds > 0 ? "+\(odds)" : "\(odds)"
    }

    static func formatDecimal(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "0.00"
    }

    static func americanToDecimal(_ odds: Int) -> Decimal {
        guard odds != 0 else { return Decimal(1) } // safety: treat 0 odds as even money
        if odds > 0 {
            return 1 + Decimal(odds) / 100
        } else {
            return 1 + 100 / Decimal(abs(odds))
        }
    }

    static func decimalToAmerican(_ decimal: Decimal) -> Int {
        let d = Double(truncating: decimal as NSDecimalNumber)
        if d >= 2 {
            return Int((d - 1) * 100)
        } else if d > 1 {
            return Int(-100.0 / (d - 1))
        } else {
            return 0
        }
    }
}
