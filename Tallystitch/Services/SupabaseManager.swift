import Foundation
import Supabase

// Why: a single shared Supabase client for the whole app, configured from
// Secrets.xcconfig (URL + publishable key only — never the service-role key,
// which would ship inside the .ipa). The PKCE flow + a keychain-backed session
// store give us "stay logged in across launches" the same way AsyncStorage
// does on the RN app.
enum SupabaseConfig {
    static var url: URL {
        guard
            let s = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
            let u = URL(string: s)
        else { fatalError("SUPABASE_URL missing from Info.plist / Secrets.xcconfig") }
        return u
    }
    static var anonKey: String {
        guard let k = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
              !k.isEmpty
        else { fatalError("SUPABASE_ANON_KEY missing from Info.plist / Secrets.xcconfig") }
        return k
    }
}

final class SupabaseManager {
    static let shared = SupabaseManager()

    let client: SupabaseClient

    private init() {
        client = SupabaseClient(
            supabaseURL: SupabaseConfig.url,
            supabaseKey: SupabaseConfig.anonKey
        )
    }
}

/// Convenience accessor used throughout the services.
var supabase: SupabaseClient { SupabaseManager.shared.client }
