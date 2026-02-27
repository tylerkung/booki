import SwiftUI
import SwiftData

/// Full pick history for a specific player — all bets and ledger entries in reverse chronological order.
/// Bets and settlement ledger entries are consolidated: each bet appears once, showing its latest state.
/// Non-bet ledger entries (adjustments, settle ups, reversals) appear as separate items.
struct PlayerPickHistoryView: View {
    let player: Player

    @Query private var allBets: [Bet]
    @Query private var allLedgerEntries: [LedgerEntry]
    @Query private var events: [Event]

    private enum ActivityItem: Identifiable {
        case bet(Bet, settlementDate: Date?)
        case ledger(LedgerEntry)

        var id: String {
            switch self {
            case .bet(let bet, _): return "bet-\(bet.id)"
            case .ledger(let entry): return "ledger-\(entry.id)"
            }
        }

        /// Sort date: graded bets use settlement date, otherwise use created date
        var date: Date {
            switch self {
            case .bet(let bet, let settlementDate):
                return settlementDate ?? bet.createdAt
            case .ledger(let entry):
                return entry.createdAt
            }
        }
    }

    private var playerBets: [Bet] {
        allBets.filter { $0.player?.id == player.id }
    }

    private var playerLedgerEntries: [LedgerEntry] {
        allLedgerEntries.filter { $0.player?.id == player.id }
    }

    /// Map bet ID → settlement ledger entry date (for sorting graded bets to top)
    private var settlementDates: [UUID: Date] {
        var map: [UUID: Date] = [:]
        for entry in playerLedgerEntries where entry.type == .settlement {
            if let bet = entry.bet {
                map[bet.id] = entry.createdAt
            }
        }
        return map
    }

    private var activities: [ActivityItem] {
        var items: [ActivityItem] = []

        // Add bets (each bet appears once — consolidated with its settlement)
        let dates = settlementDates
        for bet in playerBets {
            items.append(.bet(bet, settlementDate: dates[bet.id]))
        }

        // Add non-settlement ledger entries (adjustments, settle ups, reversals)
        for entry in playerLedgerEntries where entry.type != .settlement {
            items.append(.ledger(entry))
        }

        return items.sorted { $0.date > $1.date }
    }

    private func eventName(for bet: Bet) -> String {
        if let desc = bet.eventDescription { return desc }
        if let event = events.first(where: { $0.id.uuidString.lowercased() == bet.eventId.lowercased() }) {
            return "\(event.awayTeam) @ \(event.homeTeam)"
        }
        return "Unknown Event"
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            if activities.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 40))
                        .foregroundStyle(Theme.textMuted)
                    Text("No activity yet")
                        .font(Theme.bodyFont(size: 15))
                        .foregroundStyle(Theme.textSecondary)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(activities.enumerated()), id: \.element.id) { index, item in
                            activityRow(item)
                            if index < activities.count - 1 {
                                Divider().overlay(Theme.elevatedBackground)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    .cardStyle()
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
        }
        .navigationTitle("\(player.bookieDisplayName) — History")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func activityRow(_ item: ActivityItem) -> some View {
        switch item {
        case .bet(let bet, _):
            NavigationLink {
                BetDetailView(bet: bet)
            } label: {
                BetHistoryRow(bet: bet, eventName: eventName(for: bet))
            }
            .buttonStyle(.plain)
        case .ledger(let entry):
            NavigationLink {
                BookieTransactionDetailView(entry: entry)
            } label: {
                LedgerHistoryRow(entry: entry)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Bookie Transaction Detail View

/// Transaction detail view for bookies — uses bookie convention (positive = player owes more).
struct BookieTransactionDetailView: View {
    let entry: LedgerEntry

    private var amountColor: Color {
        entry.amount >= 0 ? Theme.accent : Theme.danger
    }

    private var typeLabel: String {
        switch entry.type {
        case .settlement: return "Pick Graded"
        case .adjustment: return "Balance Adjustment"
        case .paymentLogged: return "Settled Up"
        case .reversal: return "Reversal"
        }
    }

    private var typeIcon: String {
        switch entry.type {
        case .settlement: return "checkmark.circle.fill"
        case .adjustment: return "plusminus.circle.fill"
        case .paymentLogged: return "banknote.fill"
        case .reversal: return "arrow.uturn.backward.circle.fill"
        }
    }

    private var typeColor: Color {
        switch entry.type {
        case .settlement: return Theme.scheduled
        case .adjustment: return Theme.warning
        case .paymentLogged: return Theme.accent
        case .reversal: return Color.purple
        }
    }

    private var formattedAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        let absAmount = entry.amount < 0 ? -entry.amount : entry.amount
        let formatted = formatter.string(from: absAmount as NSDecimalNumber) ?? "$\(absAmount)"
        return entry.amount >= 0 ? "+\(formatted)" : "-\(formatted)"
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: entry.createdAt)
    }

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.cardBackground)
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.border, lineWidth: 0.5)
        }
        .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Amount hero
                VStack(spacing: 8) {
                    Image(systemName: typeIcon)
                        .font(.system(size: 44))
                        .foregroundStyle(typeColor)

                    Text(formattedAmount)
                        .font(Theme.font(size: 36, weight: .bold))
                        .foregroundStyle(amountColor)

                    Text(typeLabel)
                        .font(Theme.bodyFont(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(cardBackground)

                // Details card
                VStack(spacing: 0) {
                    detailsHeader

                    VStack(spacing: 10) {
                        labeledRow(label: "Date", value: formattedDate)

                        if !entry.entryDescription.isEmpty {
                            labeledRow(label: "Description", value: entry.entryDescription)
                        }

                        labeledRow(label: "Type", value: typeLabel)

                        if let playerName = entry.player?.bookieDisplayName {
                            labeledRow(label: "Member", value: playerName)
                        }

                        Divider().background(Theme.divider)

                        labeledRow(
                            label: "Transaction ID",
                            value: String(entry.id.uuidString.prefix(8)) + "...",
                            valueColor: Theme.textMuted
                        )
                    }
                    .padding(12)
                }
                .background(cardBackground)
            }
            .padding(16)
        }
        .background(Theme.background)
        .navigationTitle("Transaction")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var detailsHeader: some View {
        HStack {
            Text("DETAILS")
                .font(Theme.caption)
                .fontWeight(.semibold)
                .tracking(1)
                .foregroundStyle(Theme.textMuted)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 4)
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
                .multilineTextAlignment(.trailing)
        }
    }
}
