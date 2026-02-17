import SwiftUI
import SwiftData

/// Main view for players after they log in
/// Shows the full betting experience with Games, Track, and Account tabs
struct PlayerMainView: View {

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @Query private var players: [Player]
    @Query private var ledgerEntries: [LedgerEntry]

    // MARK: - Computed Properties

    /// Get the current player based on player ID
    private var currentPlayer: Player? {
        guard let playerId = authManager.currentPlayerId else { return nil }
        return players.first { $0.id == playerId }
    }

    /// Calculate display balance for the player
    /// Note: Internal balance has opposite sign (positive = owes), so we negate for display
    private var playerBalance: Decimal {
        guard let player = currentPlayer else { return 0 }
        let playerLedger = ledgerEntries.filter { $0.player?.id == player.id }
        let internalBalance = BalanceService.balanceOwed(from: playerLedger)
        return -internalBalance  // Negate for display: positive = credit, negative = debt
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Offline Banner
            OfflineBannerView()
                .animation(.easeInOut(duration: 0.3), value: networkMonitor.isConnected)

            // Main Content
            if let player = currentPlayer {
                TabView {
                    PlayerTabView(player: player, balance: playerBalance) {
                        GamesView(player: player)
                    }
                    .tabItem {
                        Label("Games", systemImage: "house.fill")
                    }

                    PlayerTabView(player: player, balance: playerBalance) {
                        TrackView(player: player)
                    }
                    .tabItem {
                        Label("Track", systemImage: "list.bullet.rectangle")
                    }

                    PlayerTabView(player: player, balance: playerBalance) {
                        AccountView(player: player)
                    }
                    .tabItem {
                        Label("Account", systemImage: "person.circle")
                    }
                }
                .tint(Theme.accent)
            } else {
                // Loading state while player data loads
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Theme.accent))
                    Text("Loading your account...")
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background)
            }
        }
    }
}

#Preview {
    PlayerMainView()
        .modelContainer(for: [Player.self, Bet.self, LedgerEntry.self, Event.self], inMemory: true)
        .environmentObject(AuthManager())
        .environmentObject(NetworkMonitor())
}
