import SwiftUI
import SwiftData

@main
struct BookiApp: App {
    @State private var authManager = AuthManager()
    @State private var syncService = SyncService()
    @StateObject private var realtimeService = RealtimeService()
    @StateObject private var networkMonitor = NetworkMonitor()

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
            UserAgreement.self,
            AuditEvent.self,
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

        // Apply sensible defaults for new accounts
        if UserDefaults.standard.object(forKey: "default_credit_limit") == nil {
            UserDefaults.standard.set(500.0, forKey: "default_credit_limit")
        }
    }

    var body: some Scene {
        WindowGroup {
            AuthGateView()
                .preferredColorScheme(.dark)
                .environment(authManager)
                .environment(syncService)
                .environmentObject(realtimeService)
                .environmentObject(networkMonitor)
                .onAppear {
                    // Configure sync service with model context
                    let context = sharedModelContainer.mainContext
                    syncService.configure(modelContext: context, authManager: authManager)
                    realtimeService.configure(modelContext: context, authManager: authManager)
                }
        }
        .modelContainer(sharedModelContainer)
    }

    /// Configure global UIKit appearances for dark theme
    private func configureAppAppearance() {
        if #unavailable(iOS 26) {
            // Tab bar appearance — opaque dark background for iOS 18-25
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

            // Navigation bar appearance — opaque dark background for iOS 18-25
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
        // On iOS 26+, system Liquid Glass translucency applies automatically
    }
}
