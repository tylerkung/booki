import Foundation
import SwiftUI
import SwiftData
import Supabase

/// Represents the current sync status
enum SyncStatus: Equatable {
    case idle
    case syncing
    case error(String)
    case offline

    var displayText: String {
        switch self {
        case .idle:
            return "Synced"
        case .syncing:
            return "Syncing..."
        case .error(let message):
            return "Sync Error: \(message)"
        case .offline:
            return "Offline"
        }
    }

    var iconName: String {
        switch self {
        case .idle:
            return "checkmark.icloud"
        case .syncing:
            return "arrow.triangle.2.circlepath.icloud"
        case .error:
            return "exclamationmark.icloud"
        case .offline:
            return "icloud.slash"
        }
    }

    var iconColor: Color {
        switch self {
        case .idle:
            return Theme.accent
        case .syncing:
            return Theme.gold
        case .error:
            return Theme.danger
        case .offline:
            return Theme.textMuted
        }
    }
}

/// Enum listing all tables that can be synced with Supabase
enum SyncableTable: String, CaseIterable {
    case players
    case events
    case bets
    case ledgerEntries = "ledger_entries"
    case acceptancePolicies = "acceptance_policies"
    case settlementPeriods = "settlement_periods"
    case playerSettlements = "player_settlements"

    /// Display name for the table
    var displayName: String {
        switch self {
        case .players:
            return "Players"
        case .events:
            return "Events"
        case .bets:
            return "Bets"
        case .ledgerEntries:
            return "Ledger Entries"
        case .acceptancePolicies:
            return "Acceptance Policies"
        case .settlementPeriods:
            return "Settlement Periods"
        case .playerSettlements:
            return "Player Settlements"
        }
    }
}

/// Error types for sync operations
enum SyncServiceError: Error, LocalizedError {
    case notAuthenticated
    case noBookieId
    case networkError(Error)
    case databaseError(String)
    case conflictDetected(recordId: UUID, localVersion: Int, serverVersion: Int)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User is not authenticated"
        case .noBookieId:
            return "No bookie ID available for sync"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .databaseError(let message):
            return "Database error: \(message)"
        case .conflictDetected(let recordId, let localVersion, let serverVersion):
            return "Conflict detected for record \(recordId): local v\(localVersion) vs server v\(serverVersion)"
        }
    }
}

/// Central coordinator for all sync operations between SwiftData and Supabase
/// Manages bidirectional sync, tracks sync state, and coordinates download/upload cycles
@MainActor
final class SyncService: ObservableObject {

    // MARK: - Published Properties

    /// Current sync status
    @Published private(set) var syncStatus: SyncStatus = .idle

    /// When sync was last completed successfully
    @Published private(set) var lastSyncedAt: Date?

    /// Number of local records waiting to be uploaded
    @Published private(set) var pendingChangesCount: Int = 0

    // MARK: - Private Properties

    private let supabase: SupabaseClient
    private weak var authManager: AuthManager?
    private var modelContext: ModelContext?

    // MARK: - Initialization

    init(authManager: AuthManager? = nil) {
        self.supabase = SupabaseClientManager.shared.client
        self.authManager = authManager
    }

    /// Configure the sync service with required dependencies
    /// - Parameters:
    ///   - modelContext: SwiftData model context for local database access
    ///   - authManager: Auth manager for authentication state
    func configure(modelContext: ModelContext, authManager: AuthManager) {
        self.modelContext = modelContext
        self.authManager = authManager
    }

    // MARK: - Public Sync Methods

    /// Performs a full sync cycle: download from server, then upload pending changes
    /// This is the primary method for syncing all data
    func sync() async {
        guard let bookieId = authManager?.currentBookieId else {
            syncStatus = .error("Not authenticated")
            return
        }

        guard modelContext != nil else {
            syncStatus = .error("Database not configured")
            return
        }

        syncStatus = .syncing

        do {
            // Phase 1: Download all data from server
            try await downloadAll(bookieId: bookieId)

            // Phase 2: Upload pending local changes
            try await uploadPendingChanges(bookieId: bookieId)

            // Update sync state
            lastSyncedAt = Date()
            syncStatus = .idle

            // Refresh pending count
            await updatePendingChangesCount()
        } catch {
            syncStatus = .error(error.localizedDescription)
            print("Sync failed: \(error)")
        }
    }

    /// Sync a specific table only
    /// - Parameter table: The table to sync
    func syncTable(_ table: SyncableTable) async {
        guard let bookieId = authManager?.currentBookieId else {
            syncStatus = .error("Not authenticated")
            return
        }

        guard modelContext != nil else {
            syncStatus = .error("Database not configured")
            return
        }

        syncStatus = .syncing

        do {
            // Download and upload for the specific table
            try await downloadTable(table, bookieId: bookieId)
            try await uploadTableChanges(table, bookieId: bookieId)

            syncStatus = .idle
            await updatePendingChangesCount()
        } catch {
            syncStatus = .error(error.localizedDescription)
            print("Sync for \(table.displayName) failed: \(error)")
        }
    }

    /// Mark sync as offline (called when network is unavailable)
    func setOffline() {
        syncStatus = .offline
    }

    /// Mark sync as ready (called when network becomes available)
    func setOnline() {
        if syncStatus == .offline {
            syncStatus = .idle
        }
    }

    /// Update the count of pending changes
    func updatePendingChangesCount() async {
        guard let context = modelContext else {
            pendingChangesCount = 0
            return
        }

        var count = 0

        // Count pending players
        let playerDescriptor = FetchDescriptor<Player>(predicate: #Predicate { $0.needsSync == true })
        count += (try? context.fetchCount(playerDescriptor)) ?? 0

        // Count pending events
        let eventDescriptor = FetchDescriptor<Event>(predicate: #Predicate { $0.needsSync == true })
        count += (try? context.fetchCount(eventDescriptor)) ?? 0

        // Count pending bets
        let betDescriptor = FetchDescriptor<Bet>(predicate: #Predicate { $0.needsSync == true })
        count += (try? context.fetchCount(betDescriptor)) ?? 0

        // Count pending ledger entries
        let ledgerDescriptor = FetchDescriptor<LedgerEntry>(predicate: #Predicate { $0.needsSync == true })
        count += (try? context.fetchCount(ledgerDescriptor)) ?? 0

        // Count pending acceptance policies
        let policyDescriptor = FetchDescriptor<AcceptancePolicy>(predicate: #Predicate { $0.needsSync == true })
        count += (try? context.fetchCount(policyDescriptor)) ?? 0

        // Count pending settlement periods
        let periodDescriptor = FetchDescriptor<SettlementPeriod>(predicate: #Predicate { $0.needsSync == true })
        count += (try? context.fetchCount(periodDescriptor)) ?? 0

        // Count pending player settlements
        let settlementDescriptor = FetchDescriptor<PlayerSettlement>(predicate: #Predicate { $0.needsSync == true })
        count += (try? context.fetchCount(settlementDescriptor)) ?? 0

        pendingChangesCount = count
    }

    // MARK: - Private Download Methods

    /// Download all data from server for the authenticated bookie
    private func downloadAll(bookieId: UUID) async throws {
        for table in SyncableTable.allCases {
            try await downloadTable(table, bookieId: bookieId)
        }
    }

    /// Download data for a specific table
    /// Placeholder implementation - actual sync logic will be in US-006
    private func downloadTable(_ table: SyncableTable, bookieId: UUID) async throws {
        // TODO: Implement in US-006 (Download Sync)
        // This is a placeholder to establish the service structure
        print("Would download \(table.displayName) for bookie \(bookieId)")
    }

    // MARK: - Private Upload Methods

    /// Upload all pending local changes to the server
    private func uploadPendingChanges(bookieId: UUID) async throws {
        for table in SyncableTable.allCases {
            try await uploadTableChanges(table, bookieId: bookieId)
        }
    }

    /// Upload pending changes for a specific table
    /// Placeholder implementation - actual sync logic will be in US-007
    private func uploadTableChanges(_ table: SyncableTable, bookieId: UUID) async throws {
        // TODO: Implement in US-007 (Upload Sync)
        // This is a placeholder to establish the service structure
        print("Would upload pending \(table.displayName) changes for bookie \(bookieId)")
    }
}

// MARK: - Sync Status Indicator View

/// A compact sync status indicator for display in the toolbar
struct SyncStatusIndicator: View {
    @ObservedObject var syncService: SyncService

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: syncService.syncStatus.iconName)
                .foregroundStyle(syncService.syncStatus.iconColor)
                .font(.system(size: 14))
                .symbolEffect(.pulse, isActive: syncService.syncStatus == .syncing)

            if syncService.pendingChangesCount > 0 && syncService.syncStatus != .syncing {
                Text("\(syncService.pendingChangesCount)")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.cardBackground.opacity(0.8))
        .cornerRadius(Theme.cornerRadiusSmall)
    }
}

// MARK: - Preview

#Preview("Sync Status - Idle") {
    let service = SyncService()
    return SyncStatusIndicator(syncService: service)
        .padding()
        .background(Theme.background)
}
