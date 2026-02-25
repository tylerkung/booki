import SwiftUI
import SwiftData

/// Full picks list for a specific player with open/graded toggle.
struct PlayerPicksListView: View {
    let player: Player
    let initialFilter: PlayerAnalyticsDetailView.PicksFilter

    @Query private var allBets: [Bet]
    @Query private var allEvents: [Event]
    @State private var picksFilter: PlayerAnalyticsDetailView.PicksFilter = .open

    private var playerBets: [Bet] {
        allBets.filter { $0.player?.id == player.id }
    }

    private var openBets: [Bet] {
        playerBets
            .filter { [.pending, .accepted, .readyToGrade].contains($0.status) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var gradedBets: [Bet] {
        playerBets
            .filter { [BetStatus.graded, .settled, .void].contains($0.status) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var filteredBets: [Bet] {
        picksFilter == .open ? openBets : gradedBets
    }

    private func eventName(for bet: Bet) -> String {
        if let desc = bet.eventDescription { return desc }
        if let event = allEvents.first(where: { $0.id.uuidString.lowercased() == bet.eventId.lowercased() }) {
            return "\(event.awayTeam) @ \(event.homeTeam)"
        }
        return "Unknown Event"
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 12) {
                    Picker("Filter", selection: $picksFilter) {
                        ForEach(PlayerAnalyticsDetailView.PicksFilter.allCases, id: \.self) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)

                    if filteredBets.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "list.bullet.rectangle")
                                .font(.system(size: 40))
                                .foregroundStyle(Theme.textMuted)
                            Text(picksFilter == .open ? "No open picks" : "No graded picks")
                                .font(Theme.bodyFont(size: 15))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(filteredBets.enumerated()), id: \.element.id) { index, bet in
                                BetHistoryRow(bet: bet, eventName: eventName(for: bet))
                                if index < filteredBets.count - 1 {
                                    Divider().overlay(Theme.elevatedBackground)
                                }
                            }
                        }
                        .cardStyle()
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.top, 8)
            }
        }
        .navigationTitle("\(player.name) — Picks")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            picksFilter = initialFilter
        }
    }
}
