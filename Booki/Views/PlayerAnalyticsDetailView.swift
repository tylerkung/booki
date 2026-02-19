import SwiftUI
import SwiftData

struct PlayerAnalyticsDetailView: View {
    let summary: PlayerAnalyticsSummary

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerSection
                ctaButtons
                todaySection
            }
            .padding(16)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(summary.player.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(summary.player.name)
                .font(Theme.title1)
                .foregroundStyle(Theme.textPrimary)

            // Balance + PAS badge
            HStack(alignment: .center) {
                Text(formatCurrency(summary.balanceOwed))
                    .font(Theme.font(size: 22, weight: .bold))
                    .foregroundStyle(balanceColor)

                Spacer()

                Text(summary.pas.label)
                    .font(Theme.bodyFont(size: 11, weight: .semibold))
                    .foregroundStyle(pasLabelColor == Theme.textMuted ? Theme.textPrimary : .black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(pasLabelColor)
                    .clipShape(Capsule())
            }

            // Reason chips
            if !summary.pas.reasonChips.isEmpty {
                DetailReasonChips(chips: summary.pas.reasonChips)
            }
        }
        .padding(16)
        .cardStyle()
    }

    // MARK: - CTA Buttons

    private var ctaButtons: some View {
        HStack(spacing: 12) {
            Button {
                print("Add Bet tapped for \(summary.player.name)")
            } label: {
                Text("ADD BET")
                    .font(Theme.headline)
                    .textCase(.uppercase)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
            }

            Button {
                print("Settle Up tapped for \(summary.player.name)")
            } label: {
                Text("SETTLE UP")
                    .font(Theme.headline)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.elevatedBackground)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
            }
        }
    }

    // MARK: - Today Section

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TODAY")
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
                .tracking(1.0)

            todayMetricRow(label: "Open Exposure", value: formatCurrency(summary.exposure.grossExposure))
            todayMetricRow(label: "Open Bets", value: "\(summary.exposure.pendingBetCount)")
            todayMetricRow(label: "Largest Open Bet", value: formatCurrency(summary.exposure.largestPendingBet))
        }
        .padding(16)
        .cardStyle()
    }

    private func todayMetricRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(Theme.bodyFont(size: 15))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(Theme.font(size: 17, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    // MARK: - Helpers

    private var balanceColor: Color {
        // Positive balanceOwed = player owes bookie (good for bookie, green)
        // Negative = bookie owes player (bad, red)
        if summary.balanceOwed > 0 { return Theme.accent }
        if summary.balanceOwed < 0 { return Theme.danger }
        return Theme.textSecondary
    }

    private var pasLabelColor: Color {
        switch summary.pas.label {
        case "High": return Theme.danger
        case "Medium": return Theme.warning
        default: return Theme.textMuted
        }
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }
}

// MARK: - Detail Reason Chips

private struct DetailReasonChips: View {
    let chips: [String]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(chips.prefix(3)), id: \.self) { chip in
                Text(chip)
                    .font(Theme.bodyFont(size: 10, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(chipColor(for: chip).opacity(0.25))
                    .clipShape(Capsule())
            }
        }
    }

    private func chipColor(for chip: String) -> Color {
        switch chip {
        case "Overdue": return Theme.danger
        case "On heater": return Theme.gold
        case "Cold streak": return Theme.accentTertiary
        case "High roller": return Theme.accentSecondary
        case "Parlay heavy": return Theme.scheduled
        case "High volatility": return Theme.warning
        case "Large pending": return Theme.accent
        default: return Theme.textMuted
        }
    }
}
