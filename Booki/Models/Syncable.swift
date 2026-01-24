import Foundation

/// Protocol defining the properties required for bidirectional sync with Supabase
/// Syncable models can track their sync state and participate in the sync lifecycle
protocol Syncable {
    /// The bookie this record belongs to (for multi-tenant isolation)
    /// Nil for records created offline before first sync
    var bookieId: UUID? { get set }

    /// Whether this record has local changes that need to be uploaded
    var needsSync: Bool { get set }

    /// When this record was last successfully synced with the server
    var lastSyncedAt: Date? { get set }

    /// Version number for optimistic locking / conflict detection
    /// Incremented on each successful sync
    var version: Int { get set }
}
