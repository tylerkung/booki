import SwiftUI
import SwiftData

/// Full pick history for a specific player — all bets and ledger entries in reverse chronological order.
struct PlayerPickHistoryView: View {
    let player: Player

    @Query private var allBets: [Bet]
    @Query private var allLedgerEntries: [LedgerEntry]
    @Query private var events: [Event]

    private enum ActivityItem: Identifiable {
        case bet(Bet)
        case ledger(LedgerEntry)

        var id: String {
            switch self {
            case .bet(let bet): return "bet-\(bet.id)"
            case .ledger(let entry): return "ledger-\(entry.id)"
            }
        }

        var date: Date {
            switch self {
            case .bet(let bet): return bet.createdAt
            case .ledger(let entry): return entry.createdAt
            }
        }
    }

    private var playerBets: [Bet] {
        allBets.filter { $0.player?.id == player.id }
    }

    private var playerLedgerEntries: [LedgerEntry] {
        allLedgerEntries.filter { $0.player?.id == player.id }
    }

    private var activities: [ActivityItem] {
        var items: [ActivityItem] = []
        for bet in playerBets {
            items.append(.bet(bet))
        }
        for entry in playerLedgerEntries {
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
        case .bet(let bet):
            BetHistoryRow(bet: bet, eventName: eventName(for: bet))
        case .ledger(let entry):
            LedgerHistoryRow(entry: entry)
        }
    }
}
