import Foundation
import Supabase
import TallystitchCore

// Why: hoists the profile into one observable store — mirror of the RN
// ProfileProvider. One fetch feeds the subscription gate and every screen's
// currency, instead of each screen re-querying profiles. refresh() is called
// after a settings edit so the whole UI reflows at once.
@MainActor
final class ProfileStore: ObservableObject {
    @Published var profile: Profile?
    @Published var loading = true

    var currency: String { profile?.currency ?? "USD" }

    func refresh() async {
        guard let userId = try? await supabase.auth.session.user.id else {
            profile = nil
            loading = false
            return
        }
        do {
            let result: Profile = try await supabase
                .from("profiles")
                .select()
                .eq("id", value: userId)
                .single()
                .execute()
                .value
            profile = result
        } catch {
            profile = nil
        }
        loading = false
    }

    func clear() {
        profile = nil
        loading = true
    }

    // MARK: - Mutations

    func updateBusiness(name: String, currency: String) async throws {
        let userId = try await supabase.auth.session.user.id
        struct Patch: Encodable { let business_name: String?; let currency: String }
        try await supabase
            .from("profiles")
            .update(Patch(business_name: name.isEmpty ? nil : name, currency: currency))
            .eq("id", value: userId)
            .execute()
        await refresh()
    }

    func markOnboardingComplete() async throws {
        let userId = try await supabase.auth.session.user.id
        struct Patch: Encodable { let onboarding_completed_at: String }
        let iso = ISO8601DateFormatter().string(from: Date())
        try await supabase
            .from("profiles")
            .update(Patch(onboarding_completed_at: iso))
            .eq("id", value: userId)
            .execute()
        await refresh()
    }
}
