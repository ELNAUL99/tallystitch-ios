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
    // Set when a recovery deep link lands: the user has a (recovery) session but
    // must choose a new password before using the app. RootView presents the
    // set-new-password screen over everything while this is true.
    @Published var passwordRecovery = false

    private var authTask: Task<Void, Never>?

    init() {
        // Seed from the stored session, then subscribe to changes.
        authTask = Task { [weak self] in
            // Stored session (cold start).
            self?.session = try? await supabase.auth.session
            self?.loading = false

            // Live updates: signed in / out / token refreshed / recovery.
            for await change in supabase.auth.authStateChanges {
                self?.session = change.session
                self?.loading = false
                if change.event == .passwordRecovery {
                    self?.passwordRecovery = true
                }
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

    // MARK: - Password reset

    // Sends a recovery email. The link reopens the app via the same
    // tallystitch://auth/callback deep link; authStateChanges then emits
    // .passwordRecovery, which flips `passwordRecovery` above.
    func resetPassword(email: String) async throws {
        try await supabase.auth.resetPasswordForEmail(
            email,
            redirectTo: DeepLink.authCallbackURL
        )
    }

    // Sets the new password using the recovery session, then clears the flag so
    // the app drops the user straight into their (now signed-in) workshop.
    func updatePassword(_ newPassword: String) async throws {
        _ = try await supabase.auth.update(user: UserAttributes(password: newPassword))
        passwordRecovery = false
    }

    func signOut() async {
        try? await supabase.auth.signOut()
    }
}
