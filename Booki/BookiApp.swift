import SwiftUI
import SwiftData
import UserNotifications

// MARK: - App Delegate for Remote Notifications

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { await NotificationService.shared.registerToken(deviceToken) }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("AppDelegate: Failed to register for remote notifications: \(error)")
    }
}

@main
struct BookiApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var authManager = AuthManager()
    @State private var syncService = SyncService()
    @State private var realtimeService = RealtimeService()
    @State private var networkMonitor = NetworkMonitor()

    /// Pending invite code from booki://invite/{code} deep link
    @State private var pendingInviteCode: String?

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
            Invite.self,
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
            AuthGateView(pendingInviteCode: $pendingInviteCode)
                .font(Theme.body)
                .preferredColorScheme(.dark)
                .environment(authManager)
                .environment(syncService)
                .environment(realtimeService)
                .environment(networkMonitor)
                .onAppear {
                    // Configure sync service with model context
                    let context = sharedModelContainer.mainContext
                    syncService.configure(modelContext: context, authManager: authManager)
                    realtimeService.configure(modelContext: context, authManager: authManager)

                    // Start StoreKit transaction listener + check entitlements
                    StoreKitService.shared.startTransactionListener()
                    Task { await StoreKitService.shared.checkCurrentEntitlement() }

                    // Set up push notification delegate
                    UNUserNotificationCenter.current().delegate = NotificationService.shared
                }
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        NotificationService.shared.clearBadge()
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }

    /// Parse booki:// deep links (invite, bet, ticket, members, picks, account)
    private func handleIncomingURL(_ url: URL) {
        guard url.scheme == "booki" else { return }

        if url.host == "invite" {
            // Extract invite code from path: booki://invite/{CODE}
            let code = url.pathComponents.first { $0 != "/" }
            guard let code, !code.isEmpty else { return }

            if authManager.isAuthenticated && authManager.userRole == .bookie {
                pendingInviteCode = nil
            } else {
                pendingInviteCode = code
            }
        } else {
            // All other deep links (bet, ticket, members, picks, account)
            // Route through NotificationService's pendingDeepLink
            NotificationService.shared.pendingDeepLink = url.absoluteString
        }
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

            // Badge styling — teal background, dark text, Space Grotesk font
            let badgeBg = UIColor(Theme.accent)
            let badgeFg = UIColor(Theme.background)
            let badgeFont = UIFont(name: "SpaceGrotesk-Bold", size: 11) ?? .boldSystemFont(ofSize: 11)
            let badgeAttrs: [NSAttributedString.Key: Any] = [.font: badgeFont, .foregroundColor: badgeFg]
            let badgeOffset = UIOffset(horizontal: -8, vertical: -4)
            for layout in [tabBarAppearance.stackedLayoutAppearance, tabBarAppearance.inlineLayoutAppearance, tabBarAppearance.compactInlineLayoutAppearance] {
                layout.normal.badgeBackgroundColor = badgeBg
                layout.normal.badgeTextAttributes = badgeAttrs
                layout.normal.badgePositionAdjustment = badgeOffset
                layout.selected.badgeBackgroundColor = badgeBg
                layout.selected.badgeTextAttributes = badgeAttrs
                layout.selected.badgePositionAdjustment = badgeOffset
            }

            UITabBar.appearance().standardAppearance = tabBarAppearance
            UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance

            // Navigation bar appearance — opaque dark background for iOS 18-25
            let navBarAppearance = UINavigationBarAppearance()
            navBarAppearance.configureWithOpaqueBackground()
            navBarAppearance.backgroundColor = UIColor(Theme.background)
            let navTitleFont = UIFont(name: "SpaceGrotesk-Bold", size: 17) ?? .boldSystemFont(ofSize: 17)
            let navLargeTitleFont = UIFont(name: "SpaceGrotesk-Bold", size: 34) ?? .boldSystemFont(ofSize: 34)
            navBarAppearance.titleTextAttributes = [
                .foregroundColor: UIColor(Theme.textPrimary),
                .font: navTitleFont
            ]
            navBarAppearance.largeTitleTextAttributes = [
                .foregroundColor: UIColor(Theme.textPrimary),
                .font: navLargeTitleFont
            ]

            // Back button font
            let backButtonFont = UIFont(name: "IBMPlexSans-Medm", size: 17) ?? .systemFont(ofSize: 17, weight: .medium)
            let backButtonAppearance = UIBarButtonItemAppearance()
            backButtonAppearance.normal.titleTextAttributes = [.font: backButtonFont]
            navBarAppearance.backButtonAppearance = backButtonAppearance

            UINavigationBar.appearance().standardAppearance = navBarAppearance
            UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance
            UINavigationBar.appearance().compactAppearance = navBarAppearance
            UINavigationBar.appearance().tintColor = UIColor(Theme.accent)
        }
        // On iOS 26+, system Liquid Glass translucency applies automatically
    }
}
