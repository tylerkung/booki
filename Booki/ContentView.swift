import SwiftUI
import SwiftData

// MARK: - Sync Conflict Model

/// Model representing a sync conflict for UI display
struct SyncConflict: Identifiable, Equatable {
    let id: UUID
    let table: String
    let recordId: UUID
    let message: String
    let timestamp: Date

    init(table: String, recordId: UUID, message: String) {
        self.id = UUID()
        self.table = table
        self.recordId = recordId
        self.message = message
        self.timestamp = Date()
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    // Alert Threshold settings
    @AppStorage("balanceThreshold") private var balanceThreshold: Double = 500.0
    @AppStorage("agingThreshold") private var agingThreshold: Int = 7

    @Query private var players: [Player]
    @Query private var ledgerEntries: [LedgerEntry]

    // MARK: - Environment Objects

    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @EnvironmentObject private var syncService: SyncService

    // MARK: - Conflict Alert State

    /// The current sync conflict to display (nil when no conflict)
    @State private var currentConflict: SyncConflict?

    /// Whether to show the conflict alert
    @State private var showConflictAlert: Bool = false

    /// Navigation to view the conflicting record
    @State private var navigateToConflictRecord: Bool = false

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
        VStack(spacing: 0) {
            // MARK: - Offline Banner
            OfflineBannerView()
                .animation(.easeInOut(duration: 0.3), value: networkMonitor.isConnected)

            // MARK: - Main Content
            bookieModeView
        }
        // MARK: - Sync Conflict Alert
        .alert("Sync Conflict", isPresented: $showConflictAlert) {
            Button("View Current") {
                // Navigate to the conflicting record
                navigateToConflictRecord = true
            }
            Button("OK", role: .cancel) {
                currentConflict = nil
            }
        } message: {
            if let conflict = currentConflict {
                Text(conflict.message)
            } else {
                Text("This record was modified elsewhere. Your changes were not saved.")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .syncConflictDetected)) { notification in
            handleSyncConflictNotification(notification)
        }
    }

    // MARK: - Conflict Handling

    /// Handle sync conflict notification and show alert
    private func handleSyncConflictNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let table = userInfo["table"] as? String,
              let recordId = userInfo["id"] as? UUID,
              let message = userInfo["message"] as? String else {
            return
        }

        // Create conflict model for UI
        let conflict = SyncConflict(table: table, recordId: recordId, message: message)
        currentConflict = conflict
        showConflictAlert = true

        // Log conflict for debugging (enhanced logging as per US-009)
        logConflict(conflict)
    }

    /// Log conflict details for debugging purposes
    private func logConflict(_ conflict: SyncConflict) {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate, .withFullTime, .withFractionalSeconds]

        print("""
        ⚠️ SYNC CONFLICT DETECTED
        ━━━━━━━━━━━━━━━━━━━━━━━━
        Table: \(conflict.table)
        Record ID: \(conflict.recordId)
        Message: \(conflict.message)
        Timestamp: \(dateFormatter.string(from: conflict.timestamp))
        Resolution: First-write-wins - server version kept, local changes discarded
        ━━━━━━━━━━━━━━━━━━━━━━━━
        """)
    }

    // MARK: - Bookie Mode

    private var bookieModeView: some View {
        TabView {
            AnalyticsDashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "chart.bar.fill")
                }

            BetsListView()
                .tabItem {
                    Label("Picks", systemImage: "list.bullet.rectangle")
                }

            PlayersListView()
                .tabItem {
                    Label("Members", systemImage: "person.2.fill")
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

}

// MARK: - Player Tab View Wrapper

/// Wrapper view that adds the persistent header to each player tab
struct PlayerTabView<Content: View>: View {
    let player: Player
    let balance: Decimal
    var onLogoTap: (() -> Void)? = nil
    @ViewBuilder let content: Content

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Persistent header at top
                AppHeaderView(
                    player: player,
                    balance: balance,
                    onLogoTap: onLogoTap
                )

                // Tab content
                content
            }
        }
    }
}

// MARK: - Player Settings Content

/// Settings content view without NavigationStack (wrapper provides it)
struct PlayerSettingsContent: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var authManager: AuthManager

    @State private var showingLogoutConfirmation = false
    @State private var showingLogoutError = false
    @State private var logoutErrorMessage = ""

    var body: some View {
        List {
            // Account Section
            Section {
                Button(role: .destructive) {
                    showingLogoutConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("Log Out")
                    }
                    .font(Theme.headline)
                    .textCase(.uppercase)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.danger)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            } header: {
                Text("Account")
            }
            .listRowBackground(Theme.cardBackground)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Settings")
        .alert("Log Out", isPresented: $showingLogoutConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Log Out", role: .destructive) {
                Task {
                    do {
                        SyncService.clearLocalData(context: modelContext)
                        try await authManager.signOut()
                    } catch {
                        logoutErrorMessage = error.localizedDescription
                        showingLogoutError = true
                    }
                }
            }
        } message: {
            Text("Are you sure you want to log out?")
        }
        .alert("Logout Error", isPresented: $showingLogoutError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(logoutErrorMessage)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Player.self, Bet.self, LedgerEntry.self, Event.self], inMemory: true)
        .environmentObject(NetworkMonitor())
        .environmentObject(SyncService())
}
