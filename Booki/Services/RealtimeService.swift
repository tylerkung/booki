import Foundation
import SwiftUI
import SwiftData
@preconcurrency import Supabase
import Realtime

/// Manages Supabase Realtime subscriptions for live data sync
/// Subscribes to database changes and updates local SwiftData models
@MainActor
@Observable
final class RealtimeService {

    // MARK: - Published Properties

    /// Whether realtime subscriptions are active
    private(set) var isConnected: Bool = false

    /// Current connection status message
    private(set) var connectionStatus: String = "Disconnected"

    // MARK: - Private Properties

    private let supabase: SupabaseClient
    private weak var authManager: AuthManager?
    private var modelContext: ModelContext?

    /// Active realtime channels
    private var channels: [RealtimeChannelV2] = []

    /// Whether we should attempt to reconnect on connection loss
    private var shouldReconnect: Bool = false

    /// Tables to subscribe to for realtime updates
    private let subscribedTables: [SyncableTable] = [
        .players,
        .events,
        .bets,
        .ledgerEntries,
        .acceptancePolicies
    ]

    // MARK: - Initialization

    init() {
        self.supabase = SupabaseClientManager.shared.client
    }

    /// Configure the realtime service with required dependencies
    /// - Parameters:
    ///   - modelContext: SwiftData model context for local database access
    ///   - authManager: Auth manager for authentication state
    func configure(modelContext: ModelContext, authManager: AuthManager) {
        self.modelContext = modelContext
        self.authManager = authManager
    }

    // MARK: - Public Methods

    /// Subscribe to realtime updates for all tenant tables
    /// Call this after successful login
    func subscribe() async {
        guard let bookieId = authManager?.currentBookieId else {
            print("RealtimeService: Cannot subscribe - no bookie ID")
            return
        }

        guard modelContext != nil else {
            print("RealtimeService: Cannot subscribe - model context not configured")
            return
        }

        // Mark that we want to stay connected
        shouldReconnect = true
        connectionStatus = "Connecting..."

        // Subscribe to each table
        for table in subscribedTables {
            await subscribeToTable(table, bookieId: bookieId)
        }

        isConnected = true
        connectionStatus = "Connected"
        print("RealtimeService: Subscribed to \(subscribedTables.count) tables")
    }

    /// Unsubscribe from all realtime channels
    /// Call this on logout
    func unsubscribe() async {
        shouldReconnect = false
        connectionStatus = "Disconnecting..."

        // Remove all channels
        for channel in channels {
            await supabase.realtimeV2.removeChannel(channel)
        }
        channels.removeAll()

        isConnected = false
        connectionStatus = "Disconnected"
        print("RealtimeService: Unsubscribed from all channels")
    }

    /// Attempt to reconnect after network loss
    /// Called when network becomes available again
    func reconnect() async {
        guard shouldReconnect else {
            print("RealtimeService: Reconnect not needed - not subscribed")
            return
        }

        guard let bookieId = authManager?.currentBookieId else {
            print("RealtimeService: Cannot reconnect - no bookie ID")
            return
        }

        connectionStatus = "Reconnecting..."

        // Remove existing channels first
        for channel in channels {
            await supabase.realtimeV2.removeChannel(channel)
        }
        channels.removeAll()

        // Re-subscribe to all tables
        for table in subscribedTables {
            await subscribeToTable(table, bookieId: bookieId)
        }

        isConnected = true
        connectionStatus = "Connected"
        print("RealtimeService: Reconnected to \(subscribedTables.count) tables")
    }

    // MARK: - Private Subscription Methods

    /// Subscribe to a specific table's realtime changes
    private func subscribeToTable(_ table: SyncableTable, bookieId: UUID) async {
        let tableName = table.rawValue

        // Create channel for this table
        let channel = supabase.realtimeV2.channel(tableName)

        // Subscribe to postgres changes for the table
        // RLS policies automatically filter by bookie_id
        let changes = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: tableName
        )

        // Start listening for changes
        Task {
            for await change in changes {
                await handlePostgresChange(change, table: table, bookieId: bookieId)
            }
        }

        // Subscribe to the channel
        await channel.subscribe()

        // Keep track of the channel
        channels.append(channel)

        print("RealtimeService: Subscribed to \(tableName)")
    }

    /// Handle a postgres change event
    private func handlePostgresChange(_ change: AnyAction, table: SyncableTable, bookieId: UUID) async {
        guard let context = modelContext else {
            print("RealtimeService: No model context for handling change")
            return
        }

        switch change {
        case .insert(let action):
            await handleInsert(action, table: table, bookieId: bookieId, context: context)
        case .update(let action):
            await handleUpdate(action, table: table, bookieId: bookieId, context: context)
        case .delete(let action):
            await handleDelete(action, table: table, context: context)
        }
    }

    /// Handle INSERT event - add new record to local SwiftData
    private func handleInsert(_ action: InsertAction, table: SyncableTable, bookieId: UUID, context: ModelContext) async {
        print("RealtimeService: INSERT on \(table.rawValue)")

        do {
            switch table {
            case .players:
                if let record: PlayerRecord = decodeRecord(from: action.record) {
                    try upsertPlayer(record, bookieId: bookieId, context: context)
                }
            case .events:
                if let record: EventRecord = decodeRecord(from: action.record) {
                    try upsertEvent(record, bookieId: bookieId, context: context)
                }
            case .bets:
                if let record: BetRecord = decodeRecord(from: action.record) {
                    try upsertBet(record, bookieId: bookieId, context: context)
                }
            case .ledgerEntries:
                if let record: LedgerEntryRecord = decodeRecord(from: action.record) {
                    try upsertLedgerEntry(record, bookieId: bookieId, context: context)
                }
            case .acceptancePolicies:
                if let record: AcceptancePolicyRecord = decodeRecord(from: action.record) {
                    try upsertAcceptancePolicy(record, bookieId: bookieId, context: context)
                }
            case .settlementPeriods, .playerSettlements:
                // Not yet implemented in DB schema
                break
            }

            try context.save()
        } catch {
            print("RealtimeService: Failed to handle INSERT for \(table.rawValue): \(error)")
        }
    }

    /// Handle UPDATE event - update existing record in local SwiftData
    private func handleUpdate(_ action: UpdateAction, table: SyncableTable, bookieId: UUID, context: ModelContext) async {
        print("RealtimeService: UPDATE on \(table.rawValue)")

        do {
            switch table {
            case .players:
                if let record: PlayerRecord = decodeRecord(from: action.record) {
                    try upsertPlayer(record, bookieId: bookieId, context: context)
                }
            case .events:
                if let record: EventRecord = decodeRecord(from: action.record) {
                    try upsertEvent(record, bookieId: bookieId, context: context)
                }
            case .bets:
                if let record: BetRecord = decodeRecord(from: action.record) {
                    try upsertBet(record, bookieId: bookieId, context: context)
                }
            case .ledgerEntries:
                // Ledger entries are append-only, updates should not happen
                print("RealtimeService: Ignoring UPDATE for ledger entry (append-only)")
            case .acceptancePolicies:
                if let record: AcceptancePolicyRecord = decodeRecord(from: action.record) {
                    try upsertAcceptancePolicy(record, bookieId: bookieId, context: context)
                }
            case .settlementPeriods, .playerSettlements:
                // Not yet implemented in DB schema
                break
            }

            try context.save()
        } catch {
            print("RealtimeService: Failed to handle UPDATE for \(table.rawValue): \(error)")
        }
    }

    /// Handle DELETE event - remove record from local SwiftData
    private func handleDelete(_ action: DeleteAction, table: SyncableTable, context: ModelContext) async {
        print("RealtimeService: DELETE on \(table.rawValue)")

        // Get the ID from old_record
        guard let idString = action.oldRecord["id"]?.stringValue,
              let recordId = UUID(uuidString: idString) else {
            print("RealtimeService: Could not extract ID from DELETE event")
            return
        }

        do {
            switch table {
            case .players:
                try deletePlayer(id: recordId, context: context)
            case .events:
                try deleteEvent(id: recordId, context: context)
            case .bets:
                try deleteBet(id: recordId, context: context)
            case .ledgerEntries:
                try deleteLedgerEntry(id: recordId, context: context)
            case .acceptancePolicies:
                try deleteAcceptancePolicy(id: recordId, context: context)
            case .settlementPeriods, .playerSettlements:
                // Not yet implemented in DB schema
                break
            }

            try context.save()
        } catch {
            print("RealtimeService: Failed to handle DELETE for \(table.rawValue): \(error)")
        }
    }

    // MARK: - Decode Helpers

    /// Decode a record from the realtime payload
    private func decodeRecord<T: Decodable>(from dict: [String: AnyJSON]) -> T? {
        do {
            let jsonData = try JSONEncoder().encode(dict)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let dateString = try container.decode(String.self)

                // Try ISO8601 with fractional seconds
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = formatter.date(from: dateString) {
                    return date
                }

                // Try ISO8601 without fractional seconds
                formatter.formatOptions = [.withInternetDateTime]
                if let date = formatter.date(from: dateString) {
                    return date
                }

                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date: \(dateString)")
            }
            return try decoder.decode(T.self, from: jsonData)
        } catch {
            print("RealtimeService: Failed to decode record: \(error)")
            return nil
        }
    }

    // MARK: - Upsert Methods (reused from SyncService patterns)

    /// Upsert a player record from realtime event
    private func upsertPlayer(_ record: PlayerRecord, bookieId: UUID, context: ModelContext) throws {
        let recordId = record.id
        let descriptor = FetchDescriptor<Player>(predicate: #Predicate { $0.id == recordId })
        let existingPlayers = try context.fetch(descriptor)

        if let existing = existingPlayers.first {
            // Update existing record (realtime updates are always newer)
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

    /// Upsert an event record from realtime event
    private func upsertEvent(_ record: EventRecord, bookieId: UUID, context: ModelContext) throws {
        let recordId = record.id
        let descriptor = FetchDescriptor<Event>(predicate: #Predicate { $0.id == recordId })
        let existingEvents = try context.fetch(descriptor)

        if let existing = existingEvents.first {
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
        } else {
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

    /// Upsert a bet record from realtime event
    private func upsertBet(_ record: BetRecord, bookieId: UUID, context: ModelContext) throws {
        let recordId = record.id
        let descriptor = FetchDescriptor<Bet>(predicate: #Predicate { $0.id == recordId })
        let existingBets = try context.fetch(descriptor)

        // Find the player for this bet
        let playerId = record.playerId
        let playerDescriptor = FetchDescriptor<Player>(predicate: #Predicate { $0.id == playerId })
        let player = try context.fetch(playerDescriptor).first

        if let existing = existingBets.first {
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
        } else {
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

    /// Upsert a ledger entry record from realtime event
    private func upsertLedgerEntry(_ record: LedgerEntryRecord, bookieId: UUID, context: ModelContext) throws {
        let recordId = record.id
        let descriptor = FetchDescriptor<LedgerEntry>(predicate: #Predicate { $0.id == recordId })
        let existingEntries = try context.fetch(descriptor)

        // Only insert if doesn't exist (append-only)
        if existingEntries.first == nil {
            let playerId = record.playerId
            let playerDescriptor = FetchDescriptor<Player>(predicate: #Predicate { $0.id == playerId })
            guard let player = try context.fetch(playerDescriptor).first else {
                print("RealtimeService: Skipping ledger entry - player not found")
                return
            }

            var bet: Bet? = nil
            if let betId = record.betId {
                let betDescriptor = FetchDescriptor<Bet>(predicate: #Predicate { $0.id == betId })
                bet = try context.fetch(betDescriptor).first
            }

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

    /// Upsert an acceptance policy record from realtime event
    private func upsertAcceptancePolicy(_ record: AcceptancePolicyRecord, bookieId: UUID, context: ModelContext) throws {
        let recordId = record.id
        let descriptor = FetchDescriptor<AcceptancePolicy>(predicate: #Predicate { $0.id == recordId })
        let existingPolicies = try context.fetch(descriptor)

        if let existing = existingPolicies.first {
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
        } else {
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

    // MARK: - Delete Methods

    /// Delete a player from local SwiftData
    private func deletePlayer(id: UUID, context: ModelContext) throws {
        let descriptor = FetchDescriptor<Player>(predicate: #Predicate { $0.id == id })
        if let player = try context.fetch(descriptor).first {
            context.delete(player)
            print("RealtimeService: Deleted player \(id)")
        }
    }

    /// Delete an event from local SwiftData
    private func deleteEvent(id: UUID, context: ModelContext) throws {
        let descriptor = FetchDescriptor<Event>(predicate: #Predicate { $0.id == id })
        if let event = try context.fetch(descriptor).first {
            context.delete(event)
            print("RealtimeService: Deleted event \(id)")
        }
    }

    /// Delete a bet from local SwiftData
    private func deleteBet(id: UUID, context: ModelContext) throws {
        let descriptor = FetchDescriptor<Bet>(predicate: #Predicate { $0.id == id })
        if let bet = try context.fetch(descriptor).first {
            context.delete(bet)
            print("RealtimeService: Deleted bet \(id)")
        }
    }

    /// Delete a ledger entry from local SwiftData
    private func deleteLedgerEntry(id: UUID, context: ModelContext) throws {
        let descriptor = FetchDescriptor<LedgerEntry>(predicate: #Predicate { $0.id == id })
        if let entry = try context.fetch(descriptor).first {
            context.delete(entry)
            print("RealtimeService: Deleted ledger entry \(id)")
        }
    }

    /// Delete an acceptance policy from local SwiftData
    private func deleteAcceptancePolicy(id: UUID, context: ModelContext) throws {
        let descriptor = FetchDescriptor<AcceptancePolicy>(predicate: #Predicate { $0.id == id })
        if let policy = try context.fetch(descriptor).first {
            context.delete(policy)
            print("RealtimeService: Deleted acceptance policy \(id)")
        }
    }
}

// MARK: - AnyJSON String Extension

private extension AnyJSON {
    /// Get string value from AnyJSON
    var stringValue: String? {
        switch self {
        case .string(let value):
            return value
        default:
            return nil
        }
    }
}
