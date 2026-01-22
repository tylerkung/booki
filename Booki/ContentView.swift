import SwiftUI

struct ContentView: View {
    var body: some View {
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

            GradingView()
                .tabItem {
                    Label("Grading", systemImage: "checkmark.circle.fill")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
    }
}

#Preview {
    ContentView()
}
