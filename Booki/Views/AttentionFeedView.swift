import SwiftUI
import SwiftData

/// Represents an attention feed item type with severity
enum AttentionItemType {
    case overdueSettlement(Player)
    case nearCreditLimit(Player, usagePercent: Int)
    case highExposureGame(Event, exposure: Decimal)

    var severity: AttentionSeverity {
        switch self {
        case .overdueSettlement:
            return .urgent
        case .nearCreditLimit:
            return .urgent
        case .highExposureGame:
            return .warning
        }
    }

    var icon: String {
        switch self {
        case .overdueSettlement:
            return "exclamationmark.circle.fill"
        case .nearCreditLimit:
            return "creditcard.trianglebadge.exclamationmark"
        case .highExposureGame:
            return "chart.line.uptrend.xyaxis"
        }
    }

    var description: String {
        switch self {
        case .overdueSettlement(let player):
            return "\(player.name) has overdue reconciliation"
        case .nearCreditLimit(let player, let percent):
            return "\(player.name) at \(percent)% of credit limit"
        case .highExposureGame(let event, let exposure):
            let formatted = Self.formatCurrency(exposure)
            return "\(event.awayTeam) @ \(event.homeTeam) — \(formatted) activity"
        }
    }

    private static func formatCurrency(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: amount as NSDecimalNumber) ?? "$\(amount)"
    }
}

enum AttentionSeverity {
    case urgent
    case warning

    var color: Color {
        switch self {
        case .urgent: return Theme.danger
        case .warning: return Theme.warning
        }
    }
}

/// Aggregates urgent items at the top of the bookie dashboard
struct AttentionFeedView: View {
    @Query private var players: [Player]
    @Query private var bets: [Bet]
    @Query private var events: [Event]
    @Query private var ledgerEntries: [LedgerEntry]
    @Query private var playerSettlements: [PlayerSettlement]

    /// High exposure threshold for flagging games
    private let highExposureThreshold: Decimal = 1000

    private var attentionItems: [AttentionItemType] {
        var items: [AttentionItemType] = []

        let activePlayers = players.filter { $0.status == .active }

        // Overdue settlements
        for player in activePlayers where player.collectionStatus == .overdue {
            items.append(.overdueSettlement(player))
        }

        // Players near credit limit (>= 75%)
        for player in activePlayers where player.creditLimit > 0 {
            let playerLedger = ledgerEntries.filter { $0.player?.id == player.id }
            let playerBets = bets.filter { $0.player?.id == player.id }
            let balanceOwed = BalanceService.balanceOwed(from: playerLedger)
            let liability = BalanceService.openLiability(from: playerBets)
            let used = balanceOwed + liability
            let threshold = player.creditLimit * Decimal(string: "0.75")!
            if used >= threshold {
                let percent = Int(truncating: ((used / player.creditLimit) * 100) as NSDecimalNumber)
                items.append(.nearCreditLimit(player, usagePercent: min(percent, 999)))
            }
        }

        // High exposure games (non-final, non-canceled events)
        let activeEvents = events.filter { $0.status == .scheduled || $0.status == .live }
        let eventExposures = ExposureService.calculateAllEventExposures(from: bets)

        for eventExposure in eventExposures where eventExposure.maxExposure >= highExposureThreshold {
            if let event = activeEvents.first(where: { $0.id.uuidString.lowercased() == eventExposure.eventId.lowercased() }) {
                items.append(.highExposureGame(event, exposure: eventExposure.maxExposure))
            }
        }

        // Sort: urgent items first, then warnings
        return items.sorted { $0.severity.sortOrder < $1.severity.sortOrder }
    }

    var body: some View {
        if attentionItems.isEmpty {
            // Empty state
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.accent)

                Text("All clear")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)

                Spacer()
            }
            .padding(.vertical, 8)
        } else {
            ForEach(Array(attentionItems.enumerated()), id: \.offset) { _, item in
                attentionRow(for: item)
            }
        }
    }

    @ViewBuilder
    private func attentionRow(for item: AttentionItemType) -> some View {
        switch item {
        case .overdueSettlement(let player):
            NavigationLink(value: player) {
                AttentionRowContent(
                    icon: item.icon,
                    description: item.description,
                    severity: item.severity
                )
            }
        case .nearCreditLimit(let player, _):
            NavigationLink(value: player) {
                AttentionRowContent(
                    icon: item.icon,
                    description: item.description,
                    severity: item.severity
                )
            }
        case .highExposureGame(let event, _):
            NavigationLink(value: event) {
                AttentionRowContent(
                    icon: item.icon,
                    description: item.description,
                    severity: item.severity
                )
            }
        }
    }
}

// MARK: - Attention Row Content

private struct AttentionRowContent: View {
    let icon: String
    let description: String
    let severity: AttentionSeverity

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(severity.color)
                .frame(width: 28)

            Text(description)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Theme.textMuted)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - AttentionSeverity Sort Order

private extension AttentionSeverity {
    var sortOrder: Int {
        switch self {
        case .urgent: return 0
        case .warning: return 1
        }
    }
}
