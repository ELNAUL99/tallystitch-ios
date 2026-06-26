import Foundation
import Supabase
import TallystitchCore

// Why: the single source of truth for auth state — mirrors the RN AuthProvider.
// It seeds from the persisted session on launch, then listens to auth state
// changes. @MainActor + @Published so SwiftUI views react automatically.
@MainActor
final class AuthStore: ObservableObject {
    @Published var session: Session?
    @Published var loading = true

    private var authTask: Task<Void, Never>?

    init() {
        // Seed from the stored session, then subscribe to changes.
        authTask = Task { [weak self] in
            // Stored session (cold start).
            self?.session = try? await supabase.auth.session
            self?.loading = false

            // Live updates: signed in / out / token refreshed.
            for await change in supabase.auth.authStateChanges {
                self?.session = change.session
                self?.loading = false
            }
        }
    }

    deinit { authTask?.cancel() }

    var isSignedIn: Bool { session != nil }

    // MARK: - Email + password

    func signIn(email: String, password: String) async throws {
        _ = try await supabase.auth.signIn(email: email, password: password)
    }

    func signUp(email: String, password: String) async throws -> Bool {
        let response = try await supabase.auth.signUp(
            email: email,
            password: password,
            redirectTo: DeepLink.authCallbackURL
        )
        // When email confirmation is on, no session comes back yet.
        return response.session != nil
    }

    // MARK: - Magic link

    func sendMagicLink(email: String) async throws {
        try await supabase.auth.signInWithOTP(
            email: email,
            redirectTo: DeepLink.authCallbackURL
        )
    }

    func signOut() async {
        try? await supabase.auth.signOut()
    }
}
