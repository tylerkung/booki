import SwiftUI
import SwiftData

struct PlayerAnalyticsDetailView: View {
    let summary: PlayerAnalyticsSummary
    let playerBets: [Bet]
    let playerLedgerEntries: [LedgerEntry]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerSection
                ctaButtons
                todaySection
                performanceSection
                behaviorSection
                reliabilitySection
                RecentActivitySection(playerBets: playerBets)
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
                print("Settle Up tapped for \(summary.player.name)")
            } label: {
                Text("RECONCILE")
                    .font(Theme.headline)
                    .textCase(.uppercase)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
            }

            Button {
                print("Adjust Balance tapped for \(summary.player.name)")
            } label: {
                Text("ADJUST BALANCE")
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

    // MARK: - Reliability Section

    private var paymentStatus: (label: String, color: Color) {
        if playerLedgerEntries.isEmpty {
            return ("New", Theme.textSecondary)
        } else if summary.isOverdue {
            return ("Overdue", Theme.danger)
        } else {
            return ("Current", Theme.accent)
        }
    }

    private var daysSinceLastPayment: String {
        guard let mostRecent = playerLedgerEntries.max(by: { $0.createdAt < $1.createdAt }) else {
            return "No payments yet"
        }
        let days = Calendar.current.dateComponents([.day], from: mostRecent.createdAt, to: Date()).day ?? 0
        if days == 0 { return "Today" }
        if days == 1 { return "1 day ago" }
        return "\(days) days ago"
    }

    private var reliabilitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RELIABILITY")
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
                .tracking(1.0)

            HStack {
                Text("Payment Status")
                    .font(Theme.bodyFont(size: 15))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(paymentStatus.label)
                    .font(Theme.bodyFont(size: 11, weight: .semibold))
                    .foregroundStyle(paymentStatus.color == Theme.textSecondary ? Theme.textPrimary : .black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(paymentStatus.color)
                    .clipShape(Capsule())
            }

            todayMetricRow(label: "Last Payment", value: daysSinceLastPayment)

            if summary.isOverdue && summary.overdueAmount > 0 {
                HStack {
                    Text("Overdue Amount")
                        .font(Theme.bodyFont(size: 15))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text(formatCurrency(summary.overdueAmount))
                        .font(Theme.font(size: 17, weight: .bold))
                        .foregroundStyle(Theme.danger)
                }
            }
        }
        .padding(16)
        .cardStyle()
    }

    // MARK: - Helpers (P/L)

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
        case "Multi-Pick heavy": return Theme.scheduled
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
        var counts: [String: Int] = ["Spread": 0, "Moneyline": 0, "Total": 0, "Multi-Pick": 0]
        for bet in bets {
            if bet.isParlay {
                counts["Multi-Pick", default: 0] += 1
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
            "Multi-Pick": Theme.accentTertiary
        ]

        let order = ["Spread", "Moneyline", "Total", "Multi-Pick"]
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

// MARK: - Recent Activity Section

private struct RecentActivitySection: View {
    let playerBets: [Bet]

    private var sortedBets: [Bet] {
        playerBets.sorted { $0.createdAt > $1.createdAt }
    }

    private var displayBets: [Bet] {
        Array(sortedBets.prefix(10))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RECENT ACTIVITY")
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
                .tracking(1.0)

            if playerBets.isEmpty {
                Text("No betting history")
                    .font(Theme.bodyFont(size: 15))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ForEach(displayBets, id: \.id) { bet in
                    BetHistoryRow(bet: bet)
                    if bet.id != displayBets.last?.id {
                        Divider().overlay(Theme.elevatedBackground)
                    }
                }

                if sortedBets.count > 10 {
                    HStack {
                        Spacer()
                        Text("View All (\(sortedBets.count))")
                            .font(Theme.bodyFont(size: 13, weight: .medium))
                            .foregroundStyle(Theme.accent)
                        Spacer()
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(16)
        .cardStyle()
    }
}

// MARK: - Bet History Row

private struct BetHistoryRow: View {
    let bet: Bet

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(formatDate(bet.createdAt))
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                resultBadge
            }

            Text(bet.eventDescription ?? "Unknown Event")
                .font(Theme.bodyFont(size: 14, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)

            HStack {
                Text("\(bet.side) \(formatOdds(bet.odds))")
                    .font(Theme.bodyFont(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(formatCurrency(bet.stake))
                    .font(Theme.bodyFont(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .padding(.vertical, 4)
    }

    private var resultBadge: some View {
        Group {
            switch bet.gradeResult {
            case .win:
                Text("W")
                    .font(Theme.bodyFont(size: 11, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.accent)
                    .clipShape(Capsule())
            case .loss:
                Text("L")
                    .font(Theme.bodyFont(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.danger)
                    .clipShape(Capsule())
            case .push:
                Text("P")
                    .font(Theme.bodyFont(size: 11, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.textMuted)
                    .clipShape(Capsule())
            case nil:
                Text("Pending")
                    .font(Theme.bodyFont(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.elevatedBackground)
                    .clipShape(Capsule())
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: date)
    }

    private func formatOdds(_ odds: Int) -> String {
        odds > 0 ? "+\(odds)" : "\(odds)"
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }
}
