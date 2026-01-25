import Foundation
import Supabase

/// Singleton wrapper for Supabase client access
/// Provides centralized access to Supabase auth and database services
final class SupabaseClientManager {

    /// Shared singleton instance
    static let shared = SupabaseClientManager()

    /// The underlying Supabase client
    /// Access auth via `client.auth` and database via `client.from(tableName)`
    let client: SupabaseClient

    private init() {
        client = SupabaseClient(
            supabaseURL: SupabaseConfig.url,
            supabaseKey: SupabaseConfig.anonKey,
            options: SupabaseClientOptions(
                auth: SupabaseClientOptions.AuthOptions(
                    flowType: .pkce,
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }
}
