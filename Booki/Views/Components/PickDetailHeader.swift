import SwiftUI

/// Reusable header component for pick detail screens showing expanded summary and financials.
struct PickDetailHeader: View {
    let presenter: PickPresenter

    var body: some View {
        VStack(spacing: 12) {
            pickSummarySection
            financialSection
        }
    }

    // MARK: - Pick Summary

    private var pickSummarySection: some View {
        VStack(spacing: 8) {
            labeledRow(label: "Type", value: presenter.isMultiPick ? "Multi-Pick" : "Single")
            labeledRow(label: "Stake", value: "$\(PickPresenter.formatDecimal(presenter.stake))")
            if presenter.isMultiPick {
                labeledRow(label: "Combined Odds", value: presenter.title.components(separatedBy: " · ").last ?? "")
            } else {
                labeledRow(label: "Odds", value: oddsFromTitle)
            }
            HStack {
                Text("Status")
                    .font(Theme.bodyFont(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                StatusPill(
                    settlementStatus: presenter.settlementStatus,
                    workflowStatus: presenter.workflowStatus
                )
            }
        }
        .padding(12)
        .background(Theme.cardBackground)
        .cornerRadius(10)
    }

    // MARK: - Financials

    private var financialSection: some View {
        VStack(spacing: 8) {
            if isSettled {
                labeledRow(label: "Final Profit", value: formattedProfit, valueColor: presenter.profitColor)
                labeledRow(label: "Final Payout", value: "$\(PickPresenter.formatDecimal(totalReturn))")
            } else {
                labeledRow(label: "Potential Profit", value: "+$\(PickPresenter.formatDecimal(presenter.profit))", valueColor: Theme.accent)
                labeledRow(label: "Total Return", value: "$\(PickPresenter.formatDecimal(totalReturn))")
            }
        }
        .padding(12)
        .background(Theme.cardBackground)
        .cornerRadius(10)
    }

    // MARK: - Helpers

    private var isSettled: Bool {
        switch presenter.settlementStatus {
        case .won, .lost, .push, .void, .cancelled: return true
        case .open: return false
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

    private var formattedProfit: String {
        if presenter.profit > 0 {
            return "+$\(PickPresenter.formatDecimal(presenter.profit))"
        } else if presenter.profit < 0 {
            return "-$\(PickPresenter.formatDecimal(abs(presenter.profit)))"
        } else {
            return "$0.00"
        }
    }

    private var oddsFromTitle: String {
        // Title format: "Selection (odds)" — extract the odds portion
        if let range = presenter.title.range(of: "(", options: .backwards),
           let end = presenter.title.range(of: ")", options: .backwards) {
            return String(presenter.title[range.upperBound..<end.lowerBound])
        }
        return ""
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

    private func abs(_ value: Decimal) -> Decimal {
        value < 0 ? -value : value
    }
}
