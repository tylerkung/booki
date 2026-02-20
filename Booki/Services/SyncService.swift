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

    /// Tracks whether the first sync after login has completed.
    /// clearLocalData only runs on the first sync to avoid flickering on pull-to-refresh.
    private var hasCompletedInitialSync = false

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
        self.hasCompletedInitialSync = false
    }

    // MARK: - Data Clearing

    /// Deletes all locally cached SwiftData records.
    /// Call before logout or before a fresh sync to prevent data leaking between accounts.
    static func clearLocalData(context: ModelContext) {
        do {
            try context.delete(model: Bet.self)
            try context.delete(model: Player.self)
            try context.delete(model: Event.self)
            try context.delete(model: Market.self)
            try context.delete(model: LedgerEntry.self)
            try context.delete(model: AcceptancePolicy.self)
            try context.delete(model: SettlementPeriod.self)
            try context.delete(model: PlayerSettlement.self)
            try context.delete(model: UserAgreement.self)
            try context.delete(model: AuditEvent.self)
            try context.delete(model: Bookie.self)
            try context.save()
        } catch {
            print("Failed to clear local data: \(error)")
        }
    }

    // MARK: - Server-Side Game Sync

    /// Triggers the sync_games Edge Function to fetch fresh odds from the Odds API.
    /// This is idempotent — the server only fetches from the API once per morning/afternoon window.
    /// Safe to call on every pull-to-refresh.
    func triggerServerGameSync() async {
        let baseURL = SupabaseConfig.url
        guard let url = URL(string: "\(baseURL.absoluteString)/functions/v1/sync_games") else {
            print("DEBUG triggerServerGameSync: Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add auth token if available (sync_games doesn't require it, but good practice)
        if let session = try? await supabase.auth.session {
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                print("DEBUG triggerServerGameSync: status=\(httpResponse.statusCode)")
                if httpResponse.statusCode == 200, let body = String(data: data, encoding: .utf8) {
                    print("DEBUG triggerServerGameSync: \(body.prefix(200))")
                }
            }
        } catch {
            // Non-fatal — the local sync still works, odds just won't be refreshed
            print("DEBUG triggerServerGameSync: \(error.localizedDescription)")
        }
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

        // Guard against concurrent syncs
        guard syncStatus != .syncing else { return }

        syncStatus = .syncing

        // Run sync in a detached task so SwiftUI view redraws
        // (triggered by @Published changes) don't cancel the network requests.
        // .refreshable cancels its task on re-render, causing NSURLError -999.
        await withCheckedContinuation { continuation in
            Task.detached { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }
                do {
                    // Clear stale data only on the first sync after login to prevent
                    // cross-bookie data leakage. Subsequent refreshes skip the clear
                    // to avoid UI flickering (empty state flash).
                    let needsClear = await MainActor.run { !self.hasCompletedInitialSync }
                    if needsClear, let context = await MainActor.run(body: { self.modelContext }) {
                        await MainActor.run {
                            SyncService.clearLocalData(context: context)
                        }
                    }

                    // Phase 1: Download all data from server
                    try await self.downloadAll(bookieId: bookieId)

                    // Phase 2: Upload pending local changes
                    try await self.uploadPendingChanges(bookieId: bookieId)

                    // Update sync state on main actor
                    await MainActor.run {
                        self.hasCompletedInitialSync = true
                        self.lastSyncedAt = Date()
                        self.syncStatus = .idle
                    }

                    // Refresh pending count
                    await self.updatePendingChangesCount()
                } catch {
                    await MainActor.run {
                        self.syncStatus = .error(error.localizedDescription)
                    }
                    print("Sync failed: \(error)")
                }
                continuation.resume()
            }
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
            // Also download markets (they depend on events)
            try await downloadMarkets(bookieId: bookieId, context: context)
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
    /// Fetches both bookie-specific events AND shared events (bookie_id is NULL)
    private func downloadEvents(bookieId: UUID, context: ModelContext) async throws {
        // First, download bookie-specific events
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

        // Then, download shared events (bookie_id is NULL) - from Odds API
        offset = 0
        hasMore = true

        print("DEBUG downloadEvents: Fetching shared events (bookie_id is NULL)")
        while hasMore {
            do {
                let records: [EventRecord] = try await supabase
                    .from("events")
                    .select()
                    .is("bookie_id", value: nil)
                    .order("created_at")
                    .range(from: offset, to: offset + pageLimit - 1)
                    .execute()
                    .value

                print("DEBUG downloadEvents: Got \(records.count) shared events")
                for record in records {
                    try upsertEvent(record, bookieId: bookieId, context: context)
                }

                hasMore = records.count == pageLimit
                offset += pageLimit
            } catch {
                print("DEBUG downloadEvents: Error fetching shared events: \(error)")
                throw error
            }
        }

        try context.save()
    }

    /// Download markets from Supabase and upsert into SwiftData
    /// Fetches both bookie-specific markets AND shared markets (bookie_id = NULL)
    private func downloadMarkets(bookieId: UUID, context: ModelContext) async throws {
        // First, download bookie-specific markets
        var offset = 0
        var hasMore = true

        while hasMore {
            let records: [MarketRecord] = try await supabase
                .from("markets")
                .select()
                .eq("bookie_id", value: bookieId.uuidString)
                .order("created_at")
                .range(from: offset, to: offset + pageLimit - 1)
                .execute()
                .value

            for record in records {
                try upsertMarket(record, context: context)
            }

            hasMore = records.count == pageLimit
            offset += pageLimit
        }

        // Then, download shared markets (bookie_id is NULL) - from Odds API
        offset = 0
        hasMore = true

        print("DEBUG downloadMarkets: Fetching shared markets (bookie_id is NULL)")
        while hasMore {
            do {
                let records: [MarketRecord] = try await supabase
                    .from("markets")
                    .select()
                    .is("bookie_id", value: nil)
                    .order("created_at")
                    .range(from: offset, to: offset + pageLimit - 1)
                    .execute()
                    .value

                print("DEBUG downloadMarkets: Got \(records.count) shared markets")
                for record in records {
                    try upsertMarket(record, context: context)
                }

                hasMore = records.count == pageLimit
                offset += pageLimit
            } catch {
                print("DEBUG downloadMarkets: Error fetching shared markets: \(error)")
                throw error
            }
        }

        try context.save()
    }

    /// Download bets from Supabase and upsert into SwiftData
    private func downloadBets(bookieId: UUID, context: ModelContext) async throws {
        var offset = 0
        var hasMore = true

        while hasMore {
            // Players can only read their own bets via RLS, but we still filter by bookie_id
            // to match the query pattern. RLS handles the player_id filtering server-side.
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
    /// Handles both bookie-specific events and shared events (bookie_id = NULL)
    private func upsertEvent(_ record: EventRecord, bookieId: UUID, context: ModelContext) throws {
        let recordId = record.id
        let descriptor = FetchDescriptor<Event>(predicate: #Predicate { $0.id == recordId })
        let existingEvents = try context.fetch(descriptor)

        // Use the record's bookieId if present, otherwise use the provided bookieId
        let effectiveBookieId = record.bookieId ?? bookieId

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
                existing.homeScore = record.homeScore
                existing.awayScore = record.awayScore
                existing.externalId = record.externalId
                existing.externalSource = record.externalSource
                existing.bookieId = effectiveBookieId
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
                bookieId: effectiveBookieId,
                needsSync: false,
                lastSyncedAt: Date()
            )
            event.homeScore = record.homeScore
            event.awayScore = record.awayScore
            event.externalId = record.externalId
            event.externalSource = record.externalSource
            context.insert(event)
        }
    }

    /// Upsert a market record from server into local SwiftData
    private func upsertMarket(_ record: MarketRecord, context: ModelContext) throws {
        let recordId = record.id
        let descriptor = FetchDescriptor<Market>(predicate: #Predicate { $0.id == recordId })
        let existingMarkets = try context.fetch(descriptor)

        // Find the event for this market
        let eventId = record.eventId
        let eventDescriptor = FetchDescriptor<Event>(predicate: #Predicate { $0.id == eventId })
        let event = try context.fetch(eventDescriptor).first

        guard let event = event else {
            // Event not found - skip this market
            print("DEBUG upsertMarket: Event \(record.eventId) not found for market \(record.id)")
            return
        }

        if let existing = existingMarkets.first {
            // Update if server is newer
            if record.updatedAt > existing.updatedAt {
                existing.type = MarketType(rawValue: record.type) ?? .moneyline
                existing.sideA = record.sideA
                existing.sideB = record.sideB
                existing.oddsA = record.oddsA
                existing.oddsB = record.oddsB
                existing.event = event
                existing.updatedAt = record.updatedAt
            }
        } else {
            // Insert new record
            let market = Market(
                id: record.id,
                type: MarketType(rawValue: record.type) ?? .moneyline,
                sideA: record.sideA,
                sideB: record.sideB,
                oddsA: record.oddsA,
                oddsB: record.oddsB,
                event: event,
                updatedAt: record.updatedAt
            )
            context.insert(market)
        }
    }

    /// Upsert a bet record from server into local SwiftData
    private func upsertBet(_ record: BetRecord, bookieId: UUID, context: ModelContext) throws {
        let recordId = record.id
        let descriptor = FetchDescriptor<Bet>(predicate: #Predicate { $0.id == recordId })
        let existingBets = try context.fetch(descriptor)

        // Find the player for this bet (players must be downloaded first so this lookup succeeds)
        let playerId = record.playerId
        let playerDescriptor = FetchDescriptor<Player>(predicate: #Predicate { $0.id == playerId })
        let player = try context.fetch(playerDescriptor).first
        if player == nil {
            print("⚠️ upsertBet: player \(record.playerId) not found for bet \(record.id) — bet will have nil player relationship")
        }

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

        print("DEBUG uploadTableChanges: Processing table \(table.displayName)")

        switch table {
        case .players:
            try await uploadPlayers(bookieId: bookieId, context: context)
        case .events:
            print("DEBUG uploadTableChanges: About to call uploadEvents")
            try await uploadEvents(bookieId: bookieId, context: context)
            print("DEBUG uploadTableChanges: Finished uploadEvents")
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
        // Debug: Check all players first
        let allPlayersDescriptor = FetchDescriptor<Player>()
        let allPlayers = try context.fetch(allPlayersDescriptor)
        print("DEBUG uploadPlayers: Total players in database: \(allPlayers.count)")
        for p in allPlayers {
            print("DEBUG: Player '\(p.name)' needsSync=\(p.needsSync), inviteCode=\(p.inviteCode ?? "nil")")
        }

        let descriptor = FetchDescriptor<Player>(predicate: #Predicate { $0.needsSync == true })
        let pendingPlayers = try context.fetch(descriptor)
        print("DEBUG uploadPlayers: Players needing sync: \(pendingPlayers.count)")

        guard !pendingPlayers.isEmpty else {
            print("DEBUG uploadPlayers: No players to upload")
            return
        }

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

        print("DEBUG uploadEvents: Found \(pendingEvents.count) events with needsSync=true")

        guard !pendingEvents.isEmpty else {
            print("DEBUG uploadEvents: No pending events to upload")
            return
        }

        for event in pendingEvents {
            do {
                print("DEBUG uploadEvents: Uploading event \(event.id) - \(event.awayTeam) @ \(event.homeTeam)")

                // Check for version conflict
                if try await hasConflict(table: "events", id: event.id, localVersion: event.version) {
                    print("DEBUG uploadEvents: Version conflict for event \(event.id), resolving...")
                    try await resolveEventConflict(event, bookieId: bookieId, context: context)
                    continue
                }

                let upsert = EventUpsert(from: event, bookieId: bookieId)

                try await supabase
                    .from("events")
                    .upsert(upsert, onConflict: "id")
                    .execute()

                print("DEBUG uploadEvents: Successfully uploaded event \(event.id)")
                event.needsSync = false
                event.lastSyncedAt = Date()
                event.version += 1
                event.bookieId = bookieId

            } catch {
                print("DEBUG uploadEvents: Failed to upload event \(event.id): \(error)")
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
    /// First-write-wins: the first successful write to the server is kept
    private func resolvePlayerConflict(_ player: Player, bookieId: UUID, context: ModelContext) async throws {
        // First, get the server version number for detailed logging
        let versionRecords: [VersionRecord] = try await supabase
            .from("players")
            .select("version")
            .eq("id", value: player.id.uuidString)
            .execute()
            .value

        let serverVersion = versionRecords.first?.version ?? 0

        let records: [PlayerRecord] = try await supabase
            .from("players")
            .select()
            .eq("id", value: player.id.uuidString)
            .execute()
            .value

        if let serverRecord = records.first {
            // Log the conflict with full version details for debugging
            logConflictDetails(
                table: "players",
                recordId: player.id,
                localVersion: player.version,
                serverVersion: serverVersion,
                recordDescription: "Player '\(player.name)'"
            )

            // Update local with server data (first-write-wins)
            try upsertPlayer(serverRecord, bookieId: bookieId, context: context)

            // Post notification for UI to show conflict message
            NotificationCenter.default.post(
                name: .syncConflictDetected,
                object: nil,
                userInfo: [
                    "table": "players",
                    "id": player.id,
                    "message": "Player '\(player.name)' was modified elsewhere. Your changes were not saved.",
                    "localVersion": player.version,
                    "serverVersion": serverVersion
                ]
            )
        }
    }

    /// Resolve event conflict by fetching server version
    /// First-write-wins: the first successful write to the server is kept
    private func resolveEventConflict(_ event: Event, bookieId: UUID, context: ModelContext) async throws {
        // First, get the server version number for detailed logging
        let versionRecords: [VersionRecord] = try await supabase
            .from("events")
            .select("version")
            .eq("id", value: event.id.uuidString)
            .execute()
            .value

        let serverVersion = versionRecords.first?.version ?? 0

        let records: [EventRecord] = try await supabase
            .from("events")
            .select()
            .eq("id", value: event.id.uuidString)
            .execute()
            .value

        if let serverRecord = records.first {
            // Log the conflict with full version details for debugging
            logConflictDetails(
                table: "events",
                recordId: event.id,
                localVersion: event.version,
                serverVersion: serverVersion,
                recordDescription: "Event '\(event.homeTeam) vs \(event.awayTeam)'"
            )

            // Update local with server data (first-write-wins)
            try upsertEvent(serverRecord, bookieId: bookieId, context: context)

            NotificationCenter.default.post(
                name: .syncConflictDetected,
                object: nil,
                userInfo: [
                    "table": "events",
                    "id": event.id,
                    "message": "Event '\(event.homeTeam) vs \(event.awayTeam)' was modified elsewhere. Your changes were not saved.",
                    "localVersion": event.version,
                    "serverVersion": serverVersion
                ]
            )
        }
    }

    /// Resolve bet conflict by fetching server version
    /// First-write-wins: the first successful write to the server is kept
    private func resolveBetConflict(_ bet: Bet, bookieId: UUID, context: ModelContext) async throws {
        // First, get the server version number for detailed logging
        let versionRecords: [VersionRecord] = try await supabase
            .from("bets")
            .select("version")
            .eq("id", value: bet.id.uuidString)
            .execute()
            .value

        let serverVersion = versionRecords.first?.version ?? 0

        let records: [BetRecord] = try await supabase
            .from("bets")
            .select()
            .eq("id", value: bet.id.uuidString)
            .execute()
            .value

        if let serverRecord = records.first {
            // Log the conflict with full version details for debugging
            let description = bet.player?.name != nil
                ? "Bet from '\(bet.player!.name)' ($\(bet.stake))"
                : "Bet ($\(bet.stake))"
            logConflictDetails(
                table: "bets",
                recordId: bet.id,
                localVersion: bet.version,
                serverVersion: serverVersion,
                recordDescription: description
            )

            // Update local with server data (first-write-wins)
            try upsertBet(serverRecord, bookieId: bookieId, context: context)

            NotificationCenter.default.post(
                name: .syncConflictDetected,
                object: nil,
                userInfo: [
                    "table": "bets",
                    "id": bet.id,
                    "message": "A bet was modified elsewhere. Your changes were not saved.",
                    "localVersion": bet.version,
                    "serverVersion": serverVersion
                ]
            )
        }
    }

    /// Resolve acceptance policy conflict by fetching server version
    /// First-write-wins: the first successful write to the server is kept
    private func resolveAcceptancePolicyConflict(_ policy: AcceptancePolicy, bookieId: UUID, context: ModelContext) async throws {
        // First, get the server version number for detailed logging
        let versionRecords: [VersionRecord] = try await supabase
            .from("acceptance_policies")
            .select("version")
            .eq("id", value: policy.id.uuidString)
            .execute()
            .value

        let serverVersion = versionRecords.first?.version ?? 0

        let records: [AcceptancePolicyRecord] = try await supabase
            .from("acceptance_policies")
            .select()
            .eq("id", value: policy.id.uuidString)
            .execute()
            .value

        if let serverRecord = records.first {
            // Log the conflict with full version details for debugging
            logConflictDetails(
                table: "acceptance_policies",
                recordId: policy.id,
                localVersion: policy.version,
                serverVersion: serverVersion,
                recordDescription: "Acceptance Policy"
            )

            // Update local with server data (first-write-wins)
            try upsertAcceptancePolicy(serverRecord, bookieId: bookieId, context: context)

            NotificationCenter.default.post(
                name: .syncConflictDetected,
                object: nil,
                userInfo: [
                    "table": "acceptance_policies",
                    "id": policy.id,
                    "message": "Acceptance policy was modified elsewhere. Your changes were not saved.",
                    "localVersion": policy.version,
                    "serverVersion": serverVersion
                ]
            )
        }
    }

    // MARK: - Conflict Logging

    /// Log detailed conflict information for debugging
    /// Includes record ID, local version, server version, and timestamp
    private func logConflictDetails(
        table: String,
        recordId: UUID,
        localVersion: Int,
        serverVersion: Int,
        recordDescription: String
    ) {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate, .withFullTime, .withFractionalSeconds]
        let timestamp = dateFormatter.string(from: Date())

        print("""

        ⚠️ SYNC CONFLICT DETECTED
        ════════════════════════════════════════════════════════
        Table:           \(table)
        Record ID:       \(recordId)
        Description:     \(recordDescription)
        Local Version:   \(localVersion)
        Server Version:  \(serverVersion)
        Timestamp:       \(timestamp)
        ────────────────────────────────────────────────────────
        Resolution:      First-write-wins
                         Server version (v\(serverVersion)) will be kept
                         Local changes (v\(localVersion)) will be discarded
        ════════════════════════════════════════════════════════

        """)
    }

    // MARK: - Player Data Sync

    /// Sync player data for a logged-in player (fetches their record from Supabase)
    /// This is called when a player logs in to ensure their local data includes bookie_id
    func syncPlayerData(authUserId: UUID) async throws {
        guard let context = modelContext else {
            throw SyncServiceError.databaseError("No model context available")
        }

        print("DEBUG: Syncing player data for auth_user_id: \(authUserId)")

        // Fetch player record from Supabase using auth_user_id
        // Use maybeSingle() instead of single() to handle case where player doesn't exist
        let response = try await supabase
            .from("players")
            .select()
            .eq("auth_user_id", value: authUserId.uuidString)
            .limit(1)
            .execute()

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let records = try decoder.decode([PlayerRecord].self, from: response.data)

        guard let record = records.first else {
            print("DEBUG: No player found for auth_user_id: \(authUserId)")
            return
        }

        print("DEBUG: Fetched player from Supabase: \(record.name), bookie_id: \(record.bookieId)")

        // Upsert the player record locally
        try await MainActor.run {
            try upsertPlayer(record, bookieId: record.bookieId, context: context)
            try context.save()
        }

        print("DEBUG: Player data synced successfully")
    }

    // MARK: - Public Upload Trigger

    /// Trigger upload for pending changes after a local write
    /// Call this after creating/updating/deleting local records
    func triggerUpload() async {
        print("DEBUG triggerUpload: Starting upload...")
        guard let bookieId = authManager?.currentBookieId else {
            print("DEBUG triggerUpload: Cannot trigger upload - no bookie ID (authManager: \(String(describing: authManager)))")
            return
        }
        print("DEBUG triggerUpload: bookie ID = \(bookieId)")

        // Don't trigger if already syncing
        guard syncStatus != .syncing else {
            print("DEBUG triggerUpload: Already syncing, skipping")
            return
        }

        do {
            syncStatus = .syncing
            try await uploadPendingChanges(bookieId: bookieId)
            print("DEBUG triggerUpload: Upload completed successfully")
            syncStatus = .idle
            await updatePendingChangesCount()
        } catch {
            print("DEBUG triggerUpload: Upload failed: \(error)")
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
                .font(Theme.font(size: 14))
                .symbolEffect(.pulse, isActive: syncService.syncStatus == .syncing)

            if syncService.syncStatus == .syncing && showProgress && !syncService.syncProgressDescription.isEmpty {
                Text(syncService.syncProgressDescription)
                    .font(Theme.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            } else if syncService.pendingChangesCount > 0 && syncService.syncStatus != .syncing {
                Text("\(syncService.pendingChangesCount)")
                    .font(Theme.caption2)
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
                    .font(Theme.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text("Syncing...")
                    .font(Theme.subheadline)
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
