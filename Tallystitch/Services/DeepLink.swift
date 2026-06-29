import Foundation

// Why: magic-link + email-confirm emails reopen the app via the custom scheme
// (tallystitch://auth/callback?code=...). SwiftUI hands us the URL through
// .onOpenURL; we trade the code for a session here. PKCE stored the verifier
// in the keychain when the link was requested, so this completes on the same
// device — the normal "tap the link on my phone" flow. Mirrors the RN
// completeAuthFromUrl helper.
// The custom scheme + callback URL used as the Supabase `redirectTo`. The
// actual code-for-session exchange lives in AuthStore.handleDeepLink so it can
// report failures to the UI.
enum DeepLink {
    static let scheme = "tallystitch"
    static var authCallbackURL: URL { URL(string: "\(scheme)://auth/callback")! }
}
