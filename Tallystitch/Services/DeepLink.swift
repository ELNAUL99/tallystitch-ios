import Foundation
import Supabase

// Why: magic-link + email-confirm emails reopen the app via the custom scheme
// (tallystitch://auth/callback?code=...). SwiftUI hands us the URL through
// .onOpenURL; we trade the code for a session here. PKCE stored the verifier
// in the keychain when the link was requested, so this completes on the same
// device — the normal "tap the link on my phone" flow. Mirrors the RN
// completeAuthFromUrl helper.
enum DeepLink {
    static let scheme = "tallystitch"
    static var authCallbackURL: URL { URL(string: "\(scheme)://auth/callback")! }

    static func handle(_ url: URL) async {
        do {
            try await supabase.auth.session(from: url)
            // On success the AuthStore's authStateChanges stream flips session.
        } catch {
            // A stale or already-used link shouldn't crash the app; the user
            // stays on login and can request a fresh one.
            print("Deep-link auth failed: \(error.localizedDescription)")
        }
    }
}
