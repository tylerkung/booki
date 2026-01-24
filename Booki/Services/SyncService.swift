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

    /// Current sync progress description (e.g., "Downloading Players...")
    @Published private(set) var syncProgressDescription: String = ""

    // MARK: - Private Properties

    private let supabase: SupabaseClient
    private weak var authManager: AuthManager?
    private var modelContext: ModelContext?

    /// Maximum records to fetch per page for pagination
    private let pageLimit = 1000

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
    /// Downloads tables in order: players first (for relationships), then events, bets, etc.
    private func downloadAll(bookieId: UUID) async throws {
        // Download in dependency order: players before bets/ledger entries
        let orderedTables: [SyncableTable] = [
            .players,
            .events,
            .acceptancePolicies,
            .bets,
            .ledgerEntries,
            .settlementPeriods,
            .playerSettlements
        ]

        for table in orderedTables {
            syncProgressDescription = "Downloading \(table.displayName)..."
            try await downloadTable(table, bookieId: bookieId)
        }

        syncProgressDescription = ""
    }

    /// Download data for a specific table
    /// Fetches records from Supabase and upserts into local SwiftData
    private func downloadTable(_ table: SyncableTable, bookieId: UUID) async throws {
        guard let context = modelContext else {
            throw SyncServiceError.databaseError("Model context not configured")
        }

        switch table {
        case .players:
            try await downloadPlayers(bookieId: bookieId, context: context)
        case .events:
            try await downloadEvents(bookieId: bookieId, context: context)
        case .bets:
            try await downloadBets(bookieId: bookieId, context: context)
        case .ledgerEntries:
            try await downloadLedgerEntries(bookieId: bookieId, context: context)
        case .acceptancePolicies:
            try await downloadAcceptancePolicies(bookieId: bookieId, context: context)
        case .settlementPeriods:
            // Settlement tables not yet in DB schema - skip for now
            print("Skipping settlement_periods - table not yet in database schema")
        case .playerSettlements:
            // Settlement tables not yet in DB schema - skip for now
            print("Skipping player_settlements - table not yet in database schema")
        }
    }

    // MARK: - Download Individual Tables

    /// Download players from Supabase and upsert into SwiftData
    private func downloadPlayers(bookieId: UUID, context: ModelContext) async throws {
        var offset = 0
        var hasMore = true

        while hasMore {
            let records: [PlayerRecord] = try await supabase
                .from("players")
                .select()
                .eq("bookie_id", value: bookieId.uuidString)
                .order("created_at")
                .range(from: offset, to: offset + pageLimit - 1)
                .execute()
                .value

            for record in records {
                try upsertPlayer(record, bookieId: bookieId, context: context)
            }

            // Check if there are more records
            hasMore = records.count == pageLimit
            offset += pageLimit
        }

        try context.save()
    }

    /// Download events from Supabase and upsert into SwiftData
    private func downloadEvents(bookieId: UUID, context: ModelContext) async throws {
        var offset = 0
        var hasMore = true

        while hasMore {
            let records: [EventRecord] = try await supabase
                .from("events")
                .select()
                .eq("bookie_id", value: bookieId.uuidString)
                .order("created_at")
                .range(from: offset, to: offset + pageLimit - 1)
                .execute()
                .value

            for record in records {
                try upsertEvent(record, bookieId: bookieId, context: context)
            }

            hasMore = records.count == pageLimit
            offset += pageLimit
        }

        try context.save()
    }

    /// Download bets from Supabase and upsert into SwiftData
    private func downloadBets(bookieId: UUID, context: ModelContext) async throws {
        var offset = 0
        var hasMore = true

        while hasMore {
            let records: [BetRecord] = try await supabase
                .from("bets")
                .select()
                .eq("bookie_id", value: bookieId.uuidString)
                .order("created_at")
                .range(from: offset, to: offset + pageLimit - 1)
                .execute()
                .value

            for record in records {
                try upsertBet(record, bookieId: bookieId, context: context)
            }

            hasMore = records.count == pageLimit
            offset += pageLimit
        }

        try context.save()
    }

    /// Download ledger entries from Supabase and upsert into SwiftData
    private func downloadLedgerEntries(bookieId: UUID, context: ModelContext) async throws {
        var offset = 0
        var hasMore = true

        while hasMore {
            let records: [LedgerEntryRecord] = try await supabase
                .from("ledger_entries")
                .select()
                .eq("bookie_id", value: bookieId.uuidString)
                .order("created_at")
                .range(from: offset, to: offset + pageLimit - 1)
                .execute()
                .value

            for record in records {
                try upsertLedgerEntry(record, bookieId: bookieId, context: context)
            }

            hasMore = records.count == pageLimit
            offset += pageLimit
        }

        try context.save()
    }

    /// Download acceptance policies from Supabase and upsert into SwiftData
    private func downloadAcceptancePolicies(bookieId: UUID, context: ModelContext) async throws {
        // Acceptance policies are unique per bookie, so no pagination needed
        let records: [AcceptancePolicyRecord] = try await supabase
            .from("acceptance_policies")
            .select()
            .eq("bookie_id", value: bookieId.uuidString)
            .execute()
            .value

        for record in records {
            try upsertAcceptancePolicy(record, bookieId: bookieId, context: context)
        }

        try context.save()
    }

    // MARK: - Upsert Methods

    /// Upsert a player record from server into local SwiftData
    private func upsertPlayer(_ record: PlayerRecord, bookieId: UUID, context: ModelContext) throws {
        // Try to find existing local record
        let recordId = record.id
        let descriptor = FetchDescriptor<Player>(predicate: #Predicate { $0.id == recordId })
        let existingPlayers = try context.fetch(descriptor)

        if let existing = existingPlayers.first {
            // Update if server is newer
            if record.updatedAt > (existing.lastSyncedAt ?? .distantPast) {
                existing.name = record.name
                existing.email = record.email
                existing.creditLimit = record.creditLimit
                existing.status = PlayerStatus(rawValue: record.status) ?? .active
                existing.collectionStatus = record.collectionStatus.flatMap { CollectionStatus(rawValue: $0) }
                existing.collectionStatusDate = record.collectionStatusDate
                existing.promisedPaymentDate = record.promisedPaymentDate
                existing.username = record.username
                existing.passwordHash = record.passwordHash
                existing.createdAt = record.createdAt
                existing.updatedAt = record.updatedAt
                existing.bookieId = bookieId
                existing.needsSync = false
                existing.lastSyncedAt = Date()
            }
        } else {
            // Insert new record
            let player = Player(
                id: record.id,
                name: record.name,
                email: record.email,
                creditLimit: record.creditLimit,
                status: PlayerStatus(rawValue: record.status) ?? .active,
                collectionStatus: record.collectionStatus.flatMap { CollectionStatus(rawValue: $0) },
                collectionStatusDate: record.collectionStatusDate,
                promisedPaymentDate: record.promisedPaymentDate,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt,
                bookieId: bookieId,
                needsSync: false,
                lastSyncedAt: Date()
            )
            player.username = record.username
            player.passwordHash = record.passwordHash
            context.insert(player)
        }
    }

    /// Upsert an event record from server into local SwiftData
    private func upsertEvent(_ record: EventRecord, bookieId: UUID, context: ModelContext) throws {
        let recordId = record.id
        let descriptor = FetchDescriptor<Event>(predicate: #Predicate { $0.id == recordId })
        let existingEvents = try context.fetch(descriptor)

        if let existing = existingEvents.first {
            // Update if server is newer
            if record.updatedAt > (existing.lastSyncedAt ?? .distantPast) {
                existing.sport = record.sport
                existing.league = record.league ?? ""
                existing.homeTeam = record.homeTeam
                existing.awayTeam = record.awayTeam
                existing.startTime = record.startTime
                existing.status = EventStatus(rawValue: record.status) ?? .scheduled
                existing.finalScore = record.finalScore
                existing.bookieId = bookieId
                existing.needsSync = false
                existing.lastSyncedAt = Date()
            }
        } else {
            // Insert new record
            let event = Event(
                id: record.id,
                sport: record.sport,
                league: record.league ?? "",
                homeTeam: record.homeTeam,
                awayTeam: record.awayTeam,
                startTime: record.startTime,
                status: EventStatus(rawValue: record.status) ?? .scheduled,
                finalScore: record.finalScore,
                bookieId: bookieId,
                needsSync: false,
                lastSyncedAt: Date()
            )
            context.insert(event)
        }
    }

    /// Upsert a bet record from server into local SwiftData
    private func upsertBet(_ record: BetRecord, bookieId: UUID, context: ModelContext) throws {
        let recordId = record.id
        let descriptor = FetchDescriptor<Bet>(predicate: #Predicate { $0.id == recordId })
        let existingBets = try context.fetch(descriptor)

        // Find the player for this bet
        let playerId = record.playerId
        let playerDescriptor = FetchDescriptor<Player>(predicate: #Predicate { $0.id == playerId })
        let player = try context.fetch(playerDescriptor).first

        if let existing = existingBets.first {
            // Update if server is newer
            if record.updatedAt > (existing.lastSyncedAt ?? .distantPast) {
                existing.eventId = record.eventId
                existing.market = record.market ?? ""
                existing.side = record.side
                existing.odds = record.odds
                existing.stake = record.stake
                existing.status = BetStatus(rawValue: record.status) ?? .pending
                existing.gradeResult = record.gradeResult.flatMap { GradeResult(rawValue: $0) }
                existing.ticketId = record.ticketId
                existing.policyViolationReason = record.policyViolationReason
                existing.isParlay = record.isParlay
                existing.parlayLegs = record.parlayLegs
                existing.player = player
                existing.bookieId = bookieId
                existing.needsSync = false
                existing.lastSyncedAt = Date()
            }
        } else {
            // Insert new record
            let bet = Bet(
                id: record.id,
                eventId: record.eventId,
                market: record.market ?? "",
                side: record.side,
                odds: record.odds,
                stake: record.stake,
                status: BetStatus(rawValue: record.status) ?? .pending,
                gradeResult: record.gradeResult.flatMap { GradeResult(rawValue: $0) },
                player: player,
                createdAt: record.createdAt,
                ticketId: record.ticketId,
                policyViolationReason: record.policyViolationReason,
                isParlay: record.isParlay,
                parlayLegs: record.parlayLegs,
                bookieId: bookieId,
                needsSync: false,
                lastSyncedAt: Date()
            )
            context.insert(bet)
        }
    }

    /// Upsert a ledger entry record from server into local SwiftData
    private func upsertLedgerEntry(_ record: LedgerEntryRecord, bookieId: UUID, context: ModelContext) throws {
        let recordId = record.id
        let descriptor = FetchDescriptor<LedgerEntry>(predicate: #Predicate { $0.id == recordId })
        let existingEntries = try context.fetch(descriptor)

        // Find the player for this entry
        let playerId = record.playerId
        let playerDescriptor = FetchDescriptor<Player>(predicate: #Predicate { $0.id == playerId })
        guard let player = try context.fetch(playerDescriptor).first else {
            // Skip if player not found (may be deleted)
            print("Skipping ledger entry \(record.id) - player \(record.playerId) not found")
            return
        }

        // Find the bet if associated
        var bet: Bet? = nil
        if let betId = record.betId {
            let betDescriptor = FetchDescriptor<Bet>(predicate: #Predicate { $0.id == betId })
            bet = try context.fetch(betDescriptor).first
        }

        if existingEntries.first != nil {
            // Ledger entries are append-only, so we don't update existing ones
            // Just skip if it already exists
        } else {
            // Insert new record
            let entry = LedgerEntry(
                id: record.id,
                amount: record.amount,
                type: EntryType(rawValue: record.type) ?? .adjustment,
                entryDescription: record.description,
                player: player,
                bet: bet,
                createdAt: record.createdAt,
                bookieId: bookieId,
                needsSync: false,
                lastSyncedAt: Date()
            )
            context.insert(entry)
        }
    }

    /// Upsert an acceptance policy record from server into local SwiftData
    private func upsertAcceptancePolicy(_ record: AcceptancePolicyRecord, bookieId: UUID, context: ModelContext) throws {
        let recordId = record.id
        let descriptor = FetchDescriptor<AcceptancePolicy>(predicate: #Predicate { $0.id == recordId })
        let existingPolicies = try context.fetch(descriptor)

        if let existing = existingPolicies.first {
            // Update if server is newer
            if record.updatedAt > (existing.lastSyncedAt ?? .distantPast) {
                existing.autoAcceptMaxStake = record.maxStake
                existing.requireReviewAboveStake = record.requireApprovalAbove ?? 0
                existing.autoAcceptNewPlayers = record.autoAcceptNewPlayers
                existing.newPlayerBetThreshold = record.newPlayerBetThreshold
                existing.autoAcceptParlays = record.autoAcceptParlays
                existing.parlayMaxLegs = record.parlayMaxLegs
                existing.eventLockOffsetMinutes = record.eventLockOffsetMinutes
                existing.parlayPushVoidPolicy = record.parlayPushVoidPolicy
                existing.createdAt = record.createdAt
                existing.updatedAt = record.updatedAt
                existing.bookieId = bookieId
                existing.needsSync = false
                existing.lastSyncedAt = Date()
            }
        } else {
            // Insert new record
            let policy = AcceptancePolicy(
                id: record.id,
                autoAcceptMaxStake: record.maxStake,
                requireReviewAboveStake: record.requireApprovalAbove ?? 0,
                autoAcceptNewPlayers: record.autoAcceptNewPlayers,
                newPlayerBetThreshold: record.newPlayerBetThreshold,
                autoAcceptParlays: record.autoAcceptParlays,
                parlayMaxLegs: record.parlayMaxLegs,
                eventLockOffsetMinutes: record.eventLockOffsetMinutes,
                parlayPushVoidPolicy: record.parlayPushVoidPolicy,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt,
                bookieId: bookieId,
                needsSync: false,
                lastSyncedAt: Date()
            )
            context.insert(policy)
        }
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

    /// Whether to show the expanded progress view (default: false for compact toolbar display)
    var showProgress: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: syncService.syncStatus.iconName)
                .foregroundStyle(syncService.syncStatus.iconColor)
                .font(.system(size: 14))
                .symbolEffect(.pulse, isActive: syncService.syncStatus == .syncing)

            if syncService.syncStatus == .syncing && showProgress && !syncService.syncProgressDescription.isEmpty {
                Text(syncService.syncProgressDescription)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            } else if syncService.pendingChangesCount > 0 && syncService.syncStatus != .syncing {
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

/// A larger sync progress view for display during initial sync
struct SyncProgressView: View {
    @ObservedObject var syncService: SyncService

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: Theme.accent))
                .scaleEffect(1.2)

            if !syncService.syncProgressDescription.isEmpty {
                Text(syncService.syncProgressDescription)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text("Syncing...")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding()
    }
}

// MARK: - Preview

#Preview("Sync Status - Idle") {
    let service = SyncService()
    return SyncStatusIndicator(syncService: service)
        .padding()
        .background(Theme.background)
}
