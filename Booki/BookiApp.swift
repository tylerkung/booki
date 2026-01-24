import SwiftUI
import SwiftData

@main
struct BookiApp: App {
    @StateObject private var authManager = AuthManager()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Bookie.self,
            Player.self,
            Bet.self,
            LedgerEntry.self,
            Event.self,
            Market.self,
            AcceptancePolicy.self,
            SettlementPeriod.self,
            PlayerSettlement.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        configureAppAppearance()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .environmentObject(authManager)
        }
        .modelContainer(sharedModelContainer)
    }

    /// Configure global UIKit appearances for dark theme
    private func configureAppAppearance() {
        // Tab bar appearance
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        tabBarAppearance.backgroundColor = UIColor(Theme.background)

        // Selected tab color
        tabBarAppearance.stackedLayoutAppearance.selected.iconColor = UIColor(Theme.accent)
        tabBarAppearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor(Theme.accent)]

        // Unselected tab color
        tabBarAppearance.stackedLayoutAppearance.normal.iconColor = UIColor(Theme.textSecondary)
        tabBarAppearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor(Theme.textSecondary)]

        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance

        // Navigation bar appearance
        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithOpaqueBackground()
        navBarAppearance.backgroundColor = UIColor(Theme.background)
        navBarAppearance.titleTextAttributes = [.foregroundColor: UIColor(Theme.textPrimary)]
        navBarAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor(Theme.textPrimary)]

        UINavigationBar.appearance().standardAppearance = navBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance
        UINavigationBar.appearance().compactAppearance = navBarAppearance
        UINavigationBar.appearance().tintColor = UIColor(Theme.accent)
    }
}
