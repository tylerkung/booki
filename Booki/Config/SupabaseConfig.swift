import Foundation

/// Configuration for Supabase client
/// Values are read from Info.plist (SUPABASE_URL and SUPABASE_ANON_KEY)
/// Replace placeholder values with your actual Supabase project credentials
enum SupabaseConfig {

    /// Supabase project URL
    static var url: URL {
        guard let urlString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              !urlString.isEmpty,
              urlString != "YOUR_SUPABASE_URL_HERE",
              let url = URL(string: urlString) else {
            fatalError("SUPABASE_URL not configured in Info.plist. Please add your Supabase project URL.")
        }
        return url
    }

    /// Supabase anonymous key for client-side access
    static var anonKey: String {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
              !key.isEmpty,
              key != "YOUR_SUPABASE_ANON_KEY_HERE" else {
            fatalError("SUPABASE_ANON_KEY not configured in Info.plist. Please add your Supabase anon key.")
        }
        return key
    }

    /// Check if Supabase is properly configured
    static var isConfigured: Bool {
        guard let urlString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              let keyString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String else {
            return false
        }
        return !urlString.isEmpty &&
               urlString != "YOUR_SUPABASE_URL_HERE" &&
               !keyString.isEmpty &&
               keyString != "YOUR_SUPABASE_ANON_KEY_HERE"
    }
}
