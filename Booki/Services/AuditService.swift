import Foundation
@preconcurrency import Supabase

/// Error types for audit service operations
enum AuditServiceError: Error, LocalizedError, @unchecked Sendable {
    case notAuthenticated
    case networkError(Error)
    case databaseError(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User is not authenticated"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .databaseError(let message):
            return "Database error: \(message)"
        }
    }
}

/// Service for fetching audit history from Supabase
/// This service communicates with the audit_events table to retrieve state change history
final class AuditService: @unchecked Sendable {

    // MARK: - Private Properties

    private let supabase: SupabaseClient

    // MARK: - Initialization

    init() {
        self.supabase = SupabaseClientManager.shared.client
    }

    // MARK: - Public Methods

    /// Fetch audit history for a specific entity
    /// - Parameters:
    ///   - entityType: The type of entity (e.g., "bet", "ledger_entry", "player", "event")
    ///   - entityId: The UUID of the entity
    /// - Returns: Array of AuditEvent records ordered by created_at descending (most recent first)
    /// - Throws: AuditServiceError on failure
    func fetchAuditHistory(entityType: String, entityId: UUID) async throws -> [AuditEvent] {
        do {
            let records: [AuditEventRecord] = try await supabase
                .from("audit_events")
                .select()
                .eq("entity_type", value: entityType)
                .eq("entity_id", value: entityId.uuidString)
                .order("created_at", ascending: false)
                .execute()
                .value

            return records.map { $0.toAuditEvent() }
        } catch {
            throw AuditServiceError.networkError(error)
        }
    }

    /// Fetch recent audit events for a bookie
    /// - Parameters:
    ///   - bookieId: The UUID of the bookie
    ///   - limit: Maximum number of events to return (default 50)
    /// - Returns: Array of AuditEvent records ordered by created_at descending (most recent first)
    /// - Throws: AuditServiceError on failure
    func fetchRecentAuditEvents(bookieId: UUID, limit: Int = 50) async throws -> [AuditEvent] {
        do {
            let records: [AuditEventRecord] = try await supabase
                .from("audit_events")
                .select()
                .eq("bookie_id", value: bookieId.uuidString)
                .order("created_at", ascending: false)
                .limit(limit)
                .execute()
                .value

            return records.map { $0.toAuditEvent() }
        } catch {
            throw AuditServiceError.networkError(error)
        }
    }
}

// MARK: - Supabase Record Types

/// Record type for reading from audit_events table
private struct AuditEventRecord: Codable {
    let id: UUID
    let bookieId: UUID
    let actorUserId: UUID
    let entityType: String
    let entityId: UUID
    let actionType: String
    let previousState: String?
    let newState: String
    let reason: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case bookieId = "bookie_id"
        case actorUserId = "actor_user_id"
        case entityType = "entity_type"
        case entityId = "entity_id"
        case actionType = "action_type"
        case previousState = "previous_state"
        case newState = "new_state"
        case reason
        case createdAt = "created_at"
    }

    /// Convert the Supabase record to an AuditEvent model
    func toAuditEvent() -> AuditEvent {
        return AuditEvent(
            id: id,
            bookieId: bookieId,
            actorUserId: actorUserId,
            entityType: entityType,
            entityId: entityId,
            actionType: actionType,
            previousState: previousState,
            newState: newState,
            reason: reason,
            createdAt: createdAt
        )
    }
}
