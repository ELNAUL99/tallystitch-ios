import SwiftUI

// App entry. Stores are created once at the root and injected via
// environmentObject — the SwiftUI analogue of the RN context providers.
// .onOpenURL handles the magic-link deep link.
@main
struct TallystitchApp: App {
    @StateObject private var auth = AuthStore()
    @StateObject private var profile = ProfileStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .environmentObject(profile)
                .tint(Palette.clay600)
                .onOpenURL { url in
                    Task { await auth.handleDeepLink(url) }
                }
        }
    }
}
