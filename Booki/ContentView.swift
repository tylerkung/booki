import SwiftUI
import SwiftData

struct ContentView: View {
    @AppStorage("isPlayerMode") private var isPlayerMode: Bool = false
    @AppStorage("selectedPlayerID") private var selectedPlayerID: String = ""

    // Alert Threshold settings
    @AppStorage("balanceThreshold") private var balanceThreshold: Double = 500.0
    @AppStorage("agingThreshold") private var agingThreshold: Int = 7

    @Query private var players: [Player]
    @Query private var ledgerEntries: [LedgerEntry]

    /// The currently selected player for player mode
    private var selectedPlayer: Player? {
        guard !selectedPlayerID.isEmpty else { return nil }
        return players.first { $0.id.uuidString == selectedPlayerID }
    }

    /// Count of flagged players based on alert thresholds (for badge)
    private var flaggedPlayersCount: Int {
        let thresholdDecimal = Decimal(balanceThreshold)

        return players.filter { player in
            guard player.status == .active else { return false }

            let playerLedger = ledgerEntries.filter { $0.player?.id == player.id }
            let balance = BalanceService.balanceOwed(from: playerLedger)

            // Only flag players who owe money (positive balance)
            guard balance > 0 else { return false }

            // Find days since last activity
            let lastEntryDate = playerLedger.map { $0.createdAt }.max()
            let daysSinceLastActivity: Int = lastEntryDate.map { lastDate in
                Calendar.current.dateComponents([.day], from: lastDate, to: Date()).day ?? 0
            } ?? 0

            // Check thresholds
            let isHighBalance = balance >= thresholdDecimal
            let isAging = daysSinceLastActivity >= agingThreshold

            return isHighBalance || isAging
        }.count
    }

    var body: some View {
        if isPlayerMode, let player = selectedPlayer {
            // Player Mode UI
            playerModeView(player: player)
                // US-053: Smooth transition when switching between modes
                .transition(.opacity.animation(.easeInOut(duration: 0.2)))
        } else {
            // Bookie Mode UI (default)
            bookieModeView
                // US-053: Smooth transition when switching between modes
                .transition(.opacity.animation(.easeInOut(duration: 0.2)))
        }
    }

    // MARK: - Bookie Mode

    private var bookieModeView: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "chart.bar.fill")
                }

            BetsListView()
                .tabItem {
                    Label("Bets", systemImage: "list.bullet.rectangle")
                }

            PlayersListView()
                .tabItem {
                    Label("Players", systemImage: "person.2.fill")
                }
                .badge(flaggedPlayersCount > 0 ? flaggedPlayersCount : 0)

            EventsListView()
                .tabItem {
                    Label("Events", systemImage: "sportscourt.fill")
                }

            GradingView()
                .tabItem {
                    Label("Grading", systemImage: "checkmark.circle.fill")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .tint(Theme.accent)
    }

    // MARK: - Player Mode

    private func playerModeView(player: Player) -> some View {
        TabView {
            NavigationStack {
                GamesView(player: player)
            }
            .tabItem {
                Label("Games", systemImage: "house.fill")
            }

            NavigationStack {
                PlayerHistoryView(player: player)
            }
            .tabItem {
                Label("Track", systemImage: "list.bullet.rectangle")
            }

            PlayerSettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .tint(Theme.accent)
    }
}

// MARK: - Player Settings View

/// Minimal settings view for player mode with option to switch back to bookie mode
struct PlayerSettingsView: View {
    @AppStorage("isPlayerMode") private var isPlayerMode: Bool = false
    @AppStorage("selectedPlayerID") private var selectedPlayerID: String = ""

    @Query private var players: [Player]

    private var selectedPlayer: Player? {
        guard !selectedPlayerID.isEmpty else { return nil }
        return players.first { $0.id.uuidString == selectedPlayerID }
    }

    var body: some View {
        NavigationStack {
            List {
                // Current Player Info
                if let player = selectedPlayer {
                    Section {
                        LabeledContent("Name", value: player.name)
                        if let email = player.email {
                            LabeledContent("Email", value: email)
                        }
                    } header: {
                        Text("Player Account")
                    }
                }

                // Switch to Bookie Mode
                Section {
                    Button {
                        isPlayerMode = false
                    } label: {
                        Label("Switch to Bookie Mode", systemImage: "arrow.left.arrow.right")
                    }
                } header: {
                    Text("Test Mode")
                } footer: {
                    Text("Switch back to the bookie view to manage bets and players.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Player.self, Bet.self, LedgerEntry.self, Event.self], inMemory: true)
}
