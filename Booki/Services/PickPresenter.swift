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
            let matchup = "\(event.awayTeam) @ \(event.homeTeam)"
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
        self.stakeLine = "$\(PickPresenter.formatDecimal(bet.stake)) Stake"

        switch settlement {
        case .won:
            self.profit = payout
            self.profitLine = "+$\(PickPresenter.formatDecimal(payout)) Profit"
            self.profitColor = Theme.accent
        case .lost:
            self.profit = -bet.stake
            self.profitLine = "-$\(PickPresenter.formatDecimal(bet.stake))"
            self.profitColor = Theme.danger
        case .push, .void, .cancelled:
            self.profit = .zero
            self.profitLine = "$0.00"
            self.profitColor = Theme.textSecondary
        case .open:
            self.profit = payout
            self.profitLine = "Potential: +$\(PickPresenter.formatDecimal(payout))"
            self.profitColor = Theme.accent
        }
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
        if odds > 0 {
            return 1 + Decimal(odds) / 100
        } else {
            return 1 + 100 / Decimal(abs(odds))
        }
    }

    static func decimalToAmerican(_ decimal: Decimal) -> Int {
        if decimal >= 2 {
            return Int(truncating: ((decimal - 1) * 100) as NSDecimalNumber)
        } else {
            return Int(truncating: (-100 / (decimal - 1)) as NSDecimalNumber)
        }
    }
}
