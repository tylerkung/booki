import SwiftUI
import SwiftData

struct ContentView: View {
    @AppStorage("isPlayerMode") private var isPlayerMode: Bool = false
    @AppStorage("selectedPlayerID") private var selectedPlayerID: String = ""

    @Query private var players: [Player]

    /// The currently selected player for player mode
    private var selectedPlayer: Player? {
        guard !selectedPlayerID.isEmpty else { return nil }
        return players.first { $0.id.uuidString == selectedPlayerID }
    }

    var body: some View {
        if isPlayerMode, let player = selectedPlayer {
            // Player Mode UI
            playerModeView(player: player)
        } else {
            // Bookie Mode UI (default)
            bookieModeView
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
                AccountView(player: player)
            }
            .tabItem {
                Label("Account", systemImage: "person.circle.fill")
            }

            NavigationStack {
                GamesView(player: player)
            }
            .tabItem {
                Label("Games", systemImage: "sportscourt.fill")
            }

            NavigationStack {
                PlayerHistoryView(player: player)
            }
            .tabItem {
                Label("My Bets", systemImage: "list.bullet.rectangle")
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
