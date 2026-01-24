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
    /// Uploads tables in dependency order: players first (others depend on player_id)
    private func uploadPendingChanges(bookieId: UUID) async throws {
        // Upload in dependency order: players before bets/ledger entries
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
            syncProgressDescription = "Uploading \(table.displayName)..."
            try await uploadTableChanges(table, bookieId: bookieId)
        }
    }

    /// Upload pending changes for a specific table
    /// Finds records with needsSync=true and upserts them to Supabase
    private func uploadTableChanges(_ table: SyncableTable, bookieId: UUID) async throws {
        guard let context = modelContext else {
            throw SyncServiceError.databaseError("Model context not configured")
        }

        switch table {
        case .players:
            try await uploadPlayers(bookieId: bookieId, context: context)
        case .events:
            try await uploadEvents(bookieId: bookieId, context: context)
        case .bets:
            try await uploadBets(bookieId: bookieId, context: context)
        case .ledgerEntries:
            try await uploadLedgerEntries(bookieId: bookieId, context: context)
        case .acceptancePolicies:
            try await uploadAcceptancePolicies(bookieId: bookieId, context: context)
        case .settlementPeriods:
            // Settlement tables not yet in DB schema - skip for now
            print("Skipping settlement_periods upload - table not yet in database schema")
        case .playerSettlements:
            // Settlement tables not yet in DB schema - skip for now
            print("Skipping player_settlements upload - table not yet in database schema")
        }
    }

    // MARK: - Upload Individual Tables

    /// Upload pending players to Supabase
    private func uploadPlayers(bookieId: UUID, context: ModelContext) async throws {
        let descriptor = FetchDescriptor<Player>(predicate: #Predicate { $0.needsSync == true })
        let pendingPlayers = try context.fetch(descriptor)

        guard !pendingPlayers.isEmpty else { return }

        // Check for conflicts and upload each player
        for player in pendingPlayers {
            do {
                // Check for version conflict before uploading
                if try await hasConflict(table: "players", id: player.id, localVersion: player.version) {
                    // Conflict detected - fetch server version and update local
                    try await resolvePlayerConflict(player, bookieId: bookieId, context: context)
                    continue
                }

                // Create upsert payload
                let upsert = PlayerUpsert(from: player, bookieId: bookieId)

                // Upsert to Supabase (insert or update based on id)
                try await supabase
                    .from("players")
                    .upsert(upsert, onConflict: "id")
                    .execute()

                // Mark as synced and increment version
                player.needsSync = false
                player.lastSyncedAt = Date()
                player.version += 1
                player.bookieId = bookieId

            } catch {
                // Log error but continue with other records
                print("Failed to upload player \(player.id): \(error)")
                // Keep needsSync = true so it will retry next time
            }
        }

        try context.save()
    }

    /// Upload pending events to Supabase
    private func uploadEvents(bookieId: UUID, context: ModelContext) async throws {
        let descriptor = FetchDescriptor<Event>(predicate: #Predicate { $0.needsSync == true })
        let pendingEvents = try context.fetch(descriptor)

        guard !pendingEvents.isEmpty else { return }

        for event in pendingEvents {
            do {
                // Check for version conflict
                if try await hasConflict(table: "events", id: event.id, localVersion: event.version) {
                    try await resolveEventConflict(event, bookieId: bookieId, context: context)
                    continue
                }

                let upsert = EventUpsert(from: event, bookieId: bookieId)

                try await supabase
                    .from("events")
                    .upsert(upsert, onConflict: "id")
                    .execute()

                event.needsSync = false
                event.lastSyncedAt = Date()
                event.version += 1
                event.bookieId = bookieId

            } catch {
                print("Failed to upload event \(event.id): \(error)")
            }
        }

        try context.save()
    }

    /// Upload pending bets to Supabase
    private func uploadBets(bookieId: UUID, context: ModelContext) async throws {
        let descriptor = FetchDescriptor<Bet>(predicate: #Predicate { $0.needsSync == true })
        let pendingBets = try context.fetch(descriptor)

        guard !pendingBets.isEmpty else { return }

        for bet in pendingBets {
            do {
                // Check for version conflict
                if try await hasConflict(table: "bets", id: bet.id, localVersion: bet.version) {
                    try await resolveBetConflict(bet, bookieId: bookieId, context: context)
                    continue
                }

                // Create upsert payload (requires player relationship)
                guard let upsert = BetUpsert(from: bet, bookieId: bookieId) else {
                    print("Skipping bet \(bet.id) - no associated player")
                    continue
                }

                try await supabase
                    .from("bets")
                    .upsert(upsert, onConflict: "id")
                    .execute()

                bet.needsSync = false
                bet.lastSyncedAt = Date()
                bet.version += 1
                bet.bookieId = bookieId

            } catch {
                print("Failed to upload bet \(bet.id): \(error)")
            }
        }

        try context.save()
    }

    /// Upload pending ledger entries to Supabase
    /// Note: Ledger entries are append-only - only insert new records, never update
    private func uploadLedgerEntries(bookieId: UUID, context: ModelContext) async throws {
        let descriptor = FetchDescriptor<LedgerEntry>(predicate: #Predicate { $0.needsSync == true })
        let pendingEntries = try context.fetch(descriptor)

        guard !pendingEntries.isEmpty else { return }

        for entry in pendingEntries {
            do {
                // Ledger entries are append-only, so we just insert (no conflict check)
                // If the entry already exists on server, the upsert will succeed without change
                guard let insert = LedgerEntryInsert(from: entry, bookieId: bookieId) else {
                    print("Skipping ledger entry \(entry.id) - no associated player")
                    continue
                }

                try await supabase
                    .from("ledger_entries")
                    .upsert(insert, onConflict: "id")
                    .execute()

                entry.needsSync = false
                entry.lastSyncedAt = Date()
                entry.bookieId = bookieId

            } catch {
                print("Failed to upload ledger entry \(entry.id): \(error)")
            }
        }

        try context.save()
    }

    /// Upload pending acceptance policies to Supabase
    private func uploadAcceptancePolicies(bookieId: UUID, context: ModelContext) async throws {
        let descriptor = FetchDescriptor<AcceptancePolicy>(predicate: #Predicate { $0.needsSync == true })
        let pendingPolicies = try context.fetch(descriptor)

        guard !pendingPolicies.isEmpty else { return }

        for policy in pendingPolicies {
            do {
                // Check for version conflict
                if try await hasConflict(table: "acceptance_policies", id: policy.id, localVersion: policy.version) {
                    try await resolveAcceptancePolicyConflict(policy, bookieId: bookieId, context: context)
                    continue
                }

                let upsert = AcceptancePolicyUpsert(from: policy, bookieId: bookieId)

                try await supabase
                    .from("acceptance_policies")
                    .upsert(upsert, onConflict: "id")
                    .execute()

                policy.needsSync = false
                policy.lastSyncedAt = Date()
                policy.version += 1
                policy.bookieId = bookieId

            } catch {
                print("Failed to upload acceptance policy \(policy.id): \(error)")
            }
        }

        try context.save()
    }

    // MARK: - Conflict Detection and Resolution

    /// Check if a record on the server has a higher version than local
    /// Returns true if there's a conflict (server version > local version)
    private func hasConflict(table: String, id: UUID, localVersion: Int) async throws -> Bool {
        // Query server for the record's version
        let response: [VersionRecord] = try await supabase
            .from(table)
            .select("version")
            .eq("id", value: id.uuidString)
            .execute()
            .value

        // If record doesn't exist on server, no conflict
        guard let serverRecord = response.first else {
            return false
        }

        // Conflict if server version is higher
        return serverRecord.version > localVersion
    }

    /// Resolve player conflict by fetching server version
    private func resolvePlayerConflict(_ player: Player, bookieId: UUID, context: ModelContext) async throws {
        let records: [PlayerRecord] = try await supabase
            .from("players")
            .select()
            .eq("id", value: player.id.uuidString)
            .execute()
            .value

        if let serverRecord = records.first {
            // Log the conflict
            print("Conflict detected for player \(player.id): local v\(player.version) vs server v\(serverRecord.updatedAt)")

            // Update local with server data
            try upsertPlayer(serverRecord, bookieId: bookieId, context: context)

            // Post notification for UI to show conflict message
            NotificationCenter.default.post(
                name: .syncConflictDetected,
                object: nil,
                userInfo: ["table": "players", "id": player.id, "message": "Player '\(player.name)' was modified elsewhere. Your changes were not saved."]
            )
        }
    }

    /// Resolve event conflict by fetching server version
    private func resolveEventConflict(_ event: Event, bookieId: UUID, context: ModelContext) async throws {
        let records: [EventRecord] = try await supabase
            .from("events")
            .select()
            .eq("id", value: event.id.uuidString)
            .execute()
            .value

        if let serverRecord = records.first {
            print("Conflict detected for event \(event.id): local v\(event.version)")
            try upsertEvent(serverRecord, bookieId: bookieId, context: context)

            NotificationCenter.default.post(
                name: .syncConflictDetected,
                object: nil,
                userInfo: ["table": "events", "id": event.id, "message": "Event '\(event.homeTeam) vs \(event.awayTeam)' was modified elsewhere. Your changes were not saved."]
            )
        }
    }

    /// Resolve bet conflict by fetching server version
    private func resolveBetConflict(_ bet: Bet, bookieId: UUID, context: ModelContext) async throws {
        let records: [BetRecord] = try await supabase
            .from("bets")
            .select()
            .eq("id", value: bet.id.uuidString)
            .execute()
            .value

        if let serverRecord = records.first {
            print("Conflict detected for bet \(bet.id): local v\(bet.version)")
            try upsertBet(serverRecord, bookieId: bookieId, context: context)

            NotificationCenter.default.post(
                name: .syncConflictDetected,
                object: nil,
                userInfo: ["table": "bets", "id": bet.id, "message": "A bet was modified elsewhere. Your changes were not saved."]
            )
        }
    }

    /// Resolve acceptance policy conflict by fetching server version
    private func resolveAcceptancePolicyConflict(_ policy: AcceptancePolicy, bookieId: UUID, context: ModelContext) async throws {
        let records: [AcceptancePolicyRecord] = try await supabase
            .from("acceptance_policies")
            .select()
            .eq("id", value: policy.id.uuidString)
            .execute()
            .value

        if let serverRecord = records.first {
            print("Conflict detected for acceptance policy \(policy.id): local v\(policy.version)")
            try upsertAcceptancePolicy(serverRecord, bookieId: bookieId, context: context)

            NotificationCenter.default.post(
                name: .syncConflictDetected,
                object: nil,
                userInfo: ["table": "acceptance_policies", "id": policy.id, "message": "Acceptance policy was modified elsewhere. Your changes were not saved."]
            )
        }
    }

    // MARK: - Public Upload Trigger

    /// Trigger upload for pending changes after a local write
    /// Call this after creating/updating/deleting local records
    func triggerUpload() async {
        guard let bookieId = authManager?.currentBookieId else {
            print("Cannot trigger upload: no bookie ID")
            return
        }

        // Don't trigger if already syncing
        guard syncStatus != .syncing else { return }

        do {
            syncStatus = .syncing
            try await uploadPendingChanges(bookieId: bookieId)
            syncStatus = .idle
            await updatePendingChangesCount()
        } catch {
            print("Upload failed: \(error)")
            syncStatus = .error(error.localizedDescription)
        }
    }
}

// MARK: - Version Record for Conflict Detection

/// Minimal record for fetching just the version field
private struct VersionRecord: Codable {
    let version: Int
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when a sync conflict is detected
    /// userInfo contains: table (String), id (UUID), message (String)
    static let syncConflictDetected = Notification.Name("syncConflictDetected")
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
