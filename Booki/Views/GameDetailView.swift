import SwiftUI
import SwiftData

/// US-010: Game Detail View
/// Displays comprehensive game info with all available betting markets
/// Replaces MarketSelectionView for players with a more compact, sports-app style layout
struct GameDetailView: View {
    let player: Player
    let event: Event

    /// Bet slip manager for persistent selections
    @ObservedObject private var betSlipManager = BetSlipManager.shared

    /// Show bet slip sheet
    @State private var showingBetSlipSheet: Bool = false

    /// Query bets and ledger for balance calculation
    @Query private var bets: [Bet]
    @Query private var ledgerEntries: [LedgerEntry]

    // MARK: - Computed Properties

    /// Formatted start time for display
    private var formattedStartTime: String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(event.startTime) {
            formatter.dateFormat = "h:mm a"
            return "Today \(formatter.string(from: event.startTime))"
        } else if Calendar.current.isDateInTomorrow(event.startTime) {
            formatter.dateFormat = "h:mm a"
            return "Tomorrow \(formatter.string(from: event.startTime))"
        } else {
            formatter.dateFormat = "E, MMM d • h:mm a"
            return formatter.string(from: event.startTime)
        }
    }

    /// Player balance summary for bet slip
    private var balanceSummary: PlayerBalanceSummary {
        let playerBets = bets.filter { $0.player?.id == player.id }
        let playerLedgerEntries = ledgerEntries.filter { $0.player?.id == player.id }
        return BalanceService.playerSummary(
            for: player,
            bets: playerBets,
            ledgerEntries: playerLedgerEntries
        )
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Game header
            gameHeader

            // Markets content
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Placeholder for US-011, US-012, US-013 content
                    Text("Markets coming soon")
                        .foregroundColor(Theme.textSecondary)
                        .padding(.top, 40)
                }
            }
            .background(Theme.background)

            // US-014: Floating bet slip indicator
            if !betSlipManager.isEmpty {
                betSlipIndicator
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingBetSlipSheet) {
            BetSlipSheet(availableCredit: balanceSummary.availableCredit, player: player)
                .presentationDetents([.large])
        }
    }

    // MARK: - Game Header

    @ViewBuilder
    private var gameHeader: some View {
        VStack(spacing: 12) {
            // Time and status row
            HStack {
                Text(formattedStartTime)
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)

                Spacer()

                // Live indicator
                if event.status == .live {
                    Text("LIVE")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Theme.live)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Theme.live.opacity(0.15))
                        )
                }

                // Postponed indicator
                if event.status == .postponed {
                    Text("PPD")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Theme.warning)
                }

                // Canceled indicator
                if event.status == .canceled {
                    Text("CANCELED")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Theme.danger)
                }
            }

            // Matchup - Away vs Home
            HStack {
                Text(event.awayTeam)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(Theme.textPrimary)

                Text("vs")
                    .font(.subheadline)
                    .foregroundColor(Theme.textSecondary)
                    .padding(.horizontal, 8)

                Text(event.homeTeam)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(Theme.textPrimary)
            }

            // Sport and league
            HStack {
                Text(event.sport)
                Text("•")
                    .foregroundColor(Theme.textSecondary)
                Text(event.league)
                    .foregroundColor(Theme.textSecondary)
            }
            .font(.caption)
            .foregroundColor(Theme.textSecondary)
        }
        .padding(16)
        .background(Theme.cardBackground)
    }

    // MARK: - Bet Slip Indicator (US-014)

    @ViewBuilder
    private var betSlipIndicator: some View {
        Button(action: {
            showingBetSlipSheet = true
        }) {
            HStack {
                Image(systemName: "ticket.fill")
                    .foregroundStyle(.white)

                Text("\(betSlipManager.count) Selection\(betSlipManager.count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)

                Spacer()

                Image(systemName: "chevron.up")
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.blue)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    let event = Event(
        sport: "NBA",
        league: "NBA",
        homeTeam: "Lakers",
        awayTeam: "Celtics",
        startTime: Date(),
        status: .live
    )

    return NavigationStack {
        GameDetailView(
            player: Player(name: "Test", email: "test@test.com", creditLimit: 1000),
            event: event
        )
    }
    .modelContainer(for: [Player.self, Event.self, Bet.self, LedgerEntry.self], inMemory: true)
    .preferredColorScheme(.dark)
}
