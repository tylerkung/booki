import SwiftUI
import SwiftData

/// Main view for players after they log in
/// Shows the full betting experience with Games, Track, and Account tabs
struct PlayerMainView: View {

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Environment(NetworkMonitor.self) private var networkMonitor
    @Query private var players: [Player]
    @Query private var ledgerEntries: [LedgerEntry]

    // MARK: - State

    /// Synthetic player for standalone users (no bookie, no player record)
    @State private var standalonePlayer: Player?

    // MARK: - Computed Properties

    /// Default credit limit for standalone users
    private static let standaloneCredit: Decimal = 10_000

    /// Get the current player based on player ID, or standalone synthetic player
    private var currentPlayer: Player? {
        if let playerId = authManager.currentPlayerId {
            return players.first { $0.id == playerId }
        }
        // Standalone user — use synthetic player
        if authManager.isStandaloneUser {
            return standalonePlayer
        }
        return nil
    }

    /// Calculate display balance for the player
    /// Note: Internal balance has opposite sign (positive = owes), so we negate for display
    private var playerBalance: Decimal {
        guard let player = currentPlayer else { return 0 }
        let playerLedger = ledgerEntries.filter { $0.player?.id == player.id }
        let internalBalance = BalanceService.balanceOwed(from: playerLedger)
        return -internalBalance  // Negate for display: positive = credit, negative = debt
    }

    @State private var selectedTab = 0

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Offline Banner
            OfflineBannerView()
                .animation(.easeInOut(duration: 0.3), value: networkMonitor.isConnected)

            // Main Content
            if let player = currentPlayer {
                TabView(selection: $selectedTab) {
                    Tab("GAMES", systemImage: "house.fill", value: 0) {
                        PlayerTabView(player: player, balance: playerBalance, title: "Games", onLogoTap: { selectedTab = 0 }) {
                            GamesView(player: player)
                        }
                    }

                    Tab("SEARCH", systemImage: "magnifyingglass", value: 1) {
                        PlayerTabView(player: player, balance: playerBalance, title: "Search", onLogoTap: { selectedTab = 0 }) {
                            SearchView(player: player)
                        }
                    }

                    Tab("TRACK", systemImage: "list.bullet.rectangle", value: 2) {
                        PlayerTabView(player: player, balance: playerBalance, title: "Track", onLogoTap: { selectedTab = 0 }) {
                            TrackView(player: player)
                        }
                    }

                    Tab("ACCOUNT", systemImage: "person.circle", value: 3) {
                        PlayerTabView(player: player, balance: playerBalance, title: "Account", showBalance: false, onLogoTap: { selectedTab = 0 }) {
                            AccountView(player: player)
                        }
                    }
                }
                .tint(Theme.accent)
            } else {
                // Branded splash while player data loads
                VStack(spacing: 20) {
                    Image("BookiLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 200)
                        .shadow(color: Theme.accent.opacity(0.4), radius: 40)

                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Theme.accent))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background)
            }
        }
        .onAppear {
            ensureStandalonePlayer()
            // Handle deep link waiting from cold start
            handleDeepLink(NotificationService.shared.pendingDeepLink)
        }
        .onChange(of: NotificationService.shared.pendingDeepLink) { _, deepLink in
            handleDeepLink(deepLink)
        }
        // Retry pending deep link once player data is ready
        .onChange(of: currentPlayer?.id) { _, _ in
            handleDeepLink(NotificationService.shared.pendingDeepLink)
        }
    }

    /// Route a deep link to the appropriate tab
    private func handleDeepLink(_ deepLink: String?) {
        guard let deepLink else { return }
        // Don't navigate before the player/tab view is ready
        guard currentPlayer != nil else { return }
        guard let url = URL(string: deepLink) else {
            NotificationService.shared.pendingDeepLink = nil
            return
        }

        let host = url.host

        switch host {
        case "bet", "ticket":
            selectedTab = 2 // TRACK tab
        case "picks":
            selectedTab = 2 // TRACK tab
        case "account":
            selectedTab = 3 // ACCOUNT tab
        default:
            break
        }

        // Consume the deep link
        NotificationService.shared.pendingDeepLink = nil
    }

    /// Create a synthetic local-only player for standalone users
    private func ensureStandalonePlayer() {
        guard authManager.isStandaloneUser, standalonePlayer == nil else { return }
        let player = Player(
            name: "Standalone",
            creditLimit: Self.standaloneCredit,
            status: .active
        )
        player.needsSync = false
        modelContext.insert(player)
        standalonePlayer = player
        // Set the player ID on AuthManager so views that check currentPlayerId work
        authManager.setCurrentPlayerId(player.id)
    }
}

#Preview {
    PlayerMainView()
        .modelContainer(for: [Player.self, Bet.self, LedgerEntry.self, Event.self], inMemory: true)
        .environment(AuthManager())
        .environment(NetworkMonitor())
}
