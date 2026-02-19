import SwiftUI

/// Reusable compact pick card for list views, following the canonical display hierarchy.
struct PickCardCompact: View {
    let presenter: PickPresenter

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Line 1: Title + StatusPill
            HStack(alignment: .top) {
                Text(presenter.title)
                    .font(Theme.bodyFont(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)

                Spacer()

                StatusPill(
                    settlementStatus: presenter.settlementStatus,
                    workflowStatus: presenter.workflowStatus
                )
            }

            // Line 2: Context line
            if !presenter.contextLine.isEmpty {
                Text(presenter.contextLine)
                    .font(Theme.bodyFont(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }

            // Line 3: Stake + Profit
            HStack(spacing: 8) {
                Text(presenter.stakeLine)
                    .font(Theme.bodyFont(size: 13))
                    .foregroundStyle(Theme.textSecondary)

                Text(presenter.profitLine)
                    .font(Theme.bodyFont(size: 13, weight: .medium))
                    .foregroundStyle(presenter.profitColor)
            }
        }
        .padding(12)
        .background(Theme.cardBackground)
        .cornerRadius(10)
    }
}
