import SwiftUI

/// Reusable compact pick card for list views, following the canonical display hierarchy.
/// Visually matches the player-side TicketCardView: 16px corners, border stroke, shadow.
struct PickCardCompact: View {
    let presenter: PickPresenter
    /// Optional player name shown with emphasis (for bookie views)
    var playerName: String? = nil
    /// Whether to show the chevron disclosure indicator (default: true)
    var showChevron: Bool = true

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                // Line 1: Title + StatusPill
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

                // Line 2: Context line (with optional bold player name prefix)
                if playerName != nil || !presenter.contextLine.isEmpty {
                    contextLineView
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

            if showChevron {
                Image(systemName: "chevron.right")
                    .font(Theme.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.textMuted)
                    .padding(.top, 4)
            }
        }
        .padding(12)
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

    @ViewBuilder
    private var contextLineView: some View {
        if let name = playerName {
            // Bold player name + regular context
            let context = presenter.contextLine
            if context.isEmpty {
                Text(name)
                    .font(Theme.bodyFont(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
            } else {
                (Text(name)
                    .font(Theme.bodyFont(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                 + Text(" · \(context)")
                    .font(Theme.bodyFont(size: 13))
                    .foregroundStyle(Theme.textSecondary))
                .lineLimit(1)
            }
        } else {
            Text(presenter.contextLine)
                .font(Theme.bodyFont(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
    }
}
