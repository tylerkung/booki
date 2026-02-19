import SwiftUI
import SwiftData

struct PlayerAnalyticsDetailView: View {
    let summary: PlayerAnalyticsSummary
    let playerBets: [Bet]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerSection
                ctaButtons
                todaySection
                performanceSection
                behaviorSection
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

    // MARK: - Performance Section

    private var performanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PERFORMANCE")
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
                .tracking(1.0)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                PerformanceMetricCard(label: "7d P/L", value: formatSignedCurrency(summary.sevenDayPL), color: plColor(summary.sevenDayPL))
                PerformanceMetricCard(label: "30d P/L", value: formatSignedCurrency(summary.thirtyDayPL), color: plColor(summary.thirtyDayPL))
                PerformanceMetricCard(label: "All-time P/L", value: formatSignedCurrency(summary.allTimePL), color: plColor(summary.allTimePL))
                PerformanceMetricCard(label: "Win Rate", value: "\(Int(summary.winRate * 100))%", color: Theme.textPrimary)
            }
        }
        .padding(16)
        .cardStyle()
    }

    // MARK: - Behavior Section

    private var recentBets: [Bet] {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        return playerBets.filter { $0.createdAt >= thirtyDaysAgo }
    }

    private var behaviorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("BEHAVIOR")
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
                .tracking(1.0)

            if recentBets.isEmpty {
                Text("No recent activity")
                    .font(Theme.bodyFont(size: 15))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                behaviorMetrics
                MarketMixBar(bets: recentBets)
            }
        }
        .padding(16)
        .cardStyle()
    }

    private var behaviorMetrics: some View {
        VStack(spacing: 8) {
            todayMetricRow(label: "Avg Bet Size (30d)", value: formatCurrency(summary.avgBetSize30d))
            todayMetricRow(label: "Bets Per Week (30d)", value: String(format: "%.1f", Double(recentBets.count) / 4.3))
        }
    }

    private func plColor(_ value: Decimal) -> Color {
        if value > 0 { return Theme.accent }
        if value < 0 { return Theme.danger }
        return Theme.textSecondary
    }

    private func formatSignedCurrency(_ value: Decimal) -> String {
        let formatted = formatCurrency(abs(value))
        if value > 0 { return "+\(formatted)" }
        if value < 0 { return "-\(formatted)" }
        return formatted
    }

    private func abs(_ value: Decimal) -> Decimal {
        return value < 0 ? -value : value
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

// MARK: - Performance Metric Card

private struct PerformanceMetricCard: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(Theme.font(size: 17, weight: .bold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.elevatedBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
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

// MARK: - Market Mix Bar

private struct MarketMixBar: View {
    let bets: [Bet]

    private struct MarketSegment: Identifiable {
        let id = UUID()
        let label: String
        let percentage: Double
        let color: Color
    }

    private var segments: [MarketSegment] {
        var counts: [String: Int] = ["Spread": 0, "Moneyline": 0, "Total": 0, "Parlay": 0]
        for bet in bets {
            if bet.isParlay {
                counts["Parlay", default: 0] += 1
            } else {
                let market = bet.market.lowercased()
                if market.contains("spread") {
                    counts["Spread", default: 0] += 1
                } else if market.contains("moneyline") {
                    counts["Moneyline", default: 0] += 1
                } else if market.contains("total") {
                    counts["Total", default: 0] += 1
                }
            }
        }

        let total = Double(counts.values.reduce(0, +))
        guard total > 0 else { return [] }

        let colorMap: [String: Color] = [
            "Spread": Theme.accent,
            "Moneyline": Theme.accentSecondary,
            "Total": Theme.gold,
            "Parlay": Theme.accentTertiary
        ]

        let order = ["Spread", "Moneyline", "Total", "Parlay"]
        return order.compactMap { key in
            let count = counts[key] ?? 0
            guard count > 0 else { return nil }
            return MarketSegment(label: key, percentage: Double(count) / total, color: colorMap[key] ?? Theme.textMuted)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Market Mix")
                .font(Theme.bodyFont(size: 13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)

            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(segments) { segment in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(segment.color)
                            .frame(width: max(geometry.size.width * segment.percentage - 2, 4))
                    }
                }
            }
            .frame(height: 12)

            // Legend
            HStack(spacing: 12) {
                ForEach(segments) { segment in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(segment.color)
                            .frame(width: 8, height: 8)
                        Text("\(segment.label) \(Int(segment.percentage * 100))%")
                            .font(Theme.bodyFont(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
    }
}
